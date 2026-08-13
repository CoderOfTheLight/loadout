import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/time.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/approval/domain/proposal.dart';
import 'package:loadout/features/approval/infrastructure/drift_command_applier.dart';
import 'package:loadout/features/inventory/domain/inventory_ledger.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../support/test_doubles.dart';
import 'fixtures.dart';

/// Shared driver for the §11.1 write-path test families: a real encrypted
/// in-memory database behind the full DriftCommandApplier, with
/// deterministic ids, a FixedClock, and a recording Diag.
final class WritePathHarness {
  WritePathHarness()
    : db = openTestDb(),
      ids = SequentialIdGenerator(),
      clock = FixedClock(const Instant(1700000000000000)),
      diag = RecordingDiag() {
    applier = DriftCommandApplier(
      db,
      idGenerator: ids,
      clock: clock,
      diag: diag,
    );
  }

  final AppDatabase db;
  final SequentialIdGenerator ids;
  final FixedClock clock;
  final RecordingDiag diag;
  late final DriftCommandApplier applier;

  Future<void> close() => db.close();

  Future<Result<CommandReceipt>> submit(
    WorkspaceCommand command, {
    String? commandId,
  }) => applier.submit(
    Proposal(
      commandId: CommandId(commandId ?? ids.newId()),
      origin: ProposalOrigin.form,
      command: command,
      createdAt: clock.now(),
    ),
  );

  Future<CommandReceipt> ok(
    WorkspaceCommand command, {
    String? commandId,
  }) async {
    final result = await submit(command, commandId: commandId);
    return result.fold(
      (receipt) => receipt,
      (error) => fail('expected Ok, got ${error.code}: ${error.message}'),
    );
  }

  Future<DomainError> err(WorkspaceCommand command, {String? commandId}) async {
    final result = await submit(command, commandId: commandId);
    return result.fold(
      (receipt) => fail('expected Err, got receipt for ${receipt.commandId}'),
      (error) => error,
    );
  }

  // ------------------------------------------------------------- builders

  Future<String> createItem({
    required String name,
    ItemUnit unit = ItemUnit.each,
    int packMicros = 1000000,
    int? servesPerUnitMicros,
    int openingMicros = 0,
    String? category,
  }) async {
    final receipt = await ok(
      CreateItem(
        name: name,
        unit: unit,
        packSize: Quantity.fromMicros(packMicros),
        servesPerUnit: servesPerUnitMicros == null
            ? null
            : Quantity.fromMicros(servesPerUnitMicros),
        openingCount: openingMicros == 0
            ? null
            : Quantity.fromMicros(openingMicros),
        category: category,
      ),
    );
    return receipt.createdRecordIds.first;
  }

  Future<String> createEvent({
    required String name,
    String scheduledDate = '2026-08-01',
    int? plannedExposure,
    List<String> plannedItemIds = const [],
  }) async {
    final receipt = await ok(
      CreateEvent(
        name: name,
        scheduledDate: scheduledDate,
        plannedExposure: plannedExposure,
        plannedItemIds: [for (final id in plannedItemIds) ItemId(id)],
      ),
    );
    return receipt.createdRecordIds.first;
  }

  Future<String> receive(String itemId, int micros) async {
    final receipt = await ok(
      AppendMovement(
        MovementDraft(
          itemId: ItemId(itemId),
          kind: MovementKind.receive,
          deltaMicros: micros,
        ),
      ),
    );
    return receipt.createdRecordIds.first;
  }

  // -------------------------------------------------------------- queries

  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> onHand(String itemId) => db.ledgerDao.onHandMicros(itemId);

  Future<Command> commandRow(String id) =>
      (db.select(db.commands)..where((c) => c.id.equals(id))).getSingle();

  Future<InventoryMovement> movementRow(String id) => (db.select(
    db.inventoryMovements,
  )..where((m) => m.id.equals(id))).getSingle();

  Future<Event> eventRow(String id) =>
      (db.select(db.events)..where((e) => e.id.equals(id))).getSingle();

  Future<Item> itemRow(String id) =>
      (db.select(db.items)..where((i) => i.id.equals(id))).getSingle();

  /// Row counts across every record table — for "nothing written" checks.
  Future<Map<String, int>> effectCounts() async => {
    for (final table in const [
      'items',
      'events',
      'event_items',
      'inventory_movements',
      'event_closeouts',
      'closeout_lines',
      'recipes',
      'recipe_revisions',
      'recipe_lines',
      'forecast_snapshots',
      'forecast_lines',
      'forecast_evidence',
      'forecast_overrides',
    ])
      table: await count(table),
  };
}
