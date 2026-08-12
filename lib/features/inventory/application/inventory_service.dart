import 'package:drift/drift.dart' hide Column;

import '../../../core/errors.dart';
import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../../../data/db/app_database.dart';
import '../../approval/domain/approval_service.dart';
import '../../approval/domain/commands.dart';
import '../../approval/domain/proposal.dart';
import '../domain/inventory_ledger.dart';
import '../domain/ledger_math.dart';
import '../domain/movement.dart';

/// The manual-entry movement form (design §9 MovementEntryScreen). The UI
/// never does ledger math: quantities are positive and the service derives
/// the signed delta per kind.
final class MovementFormDraft {
  const MovementFormDraft({
    required this.itemId,
    required this.kind,
    required this.quantity,
    this.negativeAdjust = false,
    this.eventId,
    this.occurredAt,
    this.note = '',
  });

  final String itemId;

  /// receive | waste | adjust — nothing else is form-submittable.
  final MovementKind kind;
  final Quantity quantity;

  /// Direction for `adjust` drafts (correction replacements); ignored for
  /// receive/waste. The Count screen uses [InventoryService.recordCount]
  /// instead.
  final bool negativeAdjust;
  final String? eventId;
  final DateTime? occurredAt;
  final String note;
}

final class MovementFilter {
  const MovementFilter({
    this.itemId,
    this.eventId,
    this.kinds,
    this.limit = 200,
  });

  final String? itemId;
  final String? eventId;
  final Set<MovementKind>? kinds;
  final int limit;
}

/// One activity row: the movement plus display fields and correction links.
final class MovementView {
  const MovementView({
    required this.movement,
    required this.itemName,
    required this.itemUnit,
    this.reversedByMovementId,
  });

  final Movement movement;
  final String itemName;
  final ItemUnit itemUnit;

  /// Set when a reversal targets this row ("Corrected" strike-through).
  final String? reversedByMovementId;
}

/// Screen-facing ledger surface (design §6.5) — the application layer over
/// the [InventoryLedger] port.
abstract interface class InventoryService {
  Future<Result<CommandReceipt>> record(MovementFormDraft draft);

  /// Count mode: the service computes the signed adjust from
  /// `counted - derived`. A count equal to the derived on-hand records
  /// nothing and returns an empty receipt.
  Future<Result<CommandReceipt>> recordCount({
    required String itemId,
    required Quantity countedOnHand,
    DateTime? occurredAt,
    String? note,
  });

  Future<Result<CommandReceipt>> correct({
    required String movementId,
    MovementFormDraft? replacement,
    required String reason,
  });

  Stream<StockPosition> watchPosition(String itemId);
  Stream<List<MovementView>> watchMovements(MovementFilter filter);
  Stream<int> watchVersion();
}

final class DriftInventoryService implements InventoryService {
  DriftInventoryService(
    AppDatabase db,
    ApprovalService approval, {
    required this._ledger,
    IdGenerator idGenerator = const UlidIdGenerator(),
    this._clock = const SystemClock(),
  }) : _db = db,
       _approval = approval,
       _ids = idGenerator;

  final AppDatabase _db;
  final ApprovalService _approval;
  final InventoryLedger _ledger;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<CommandReceipt>> record(MovementFormDraft draft) {
    final MovementDraft movement;
    try {
      movement = _toMovementDraft(draft);
    } on ArgumentError catch (e) {
      return Future.value(Err(ValidationError(e.message.toString())));
    }
    return _submit(AppendMovement(movement));
  }

  @override
  Future<Result<CommandReceipt>> recordCount({
    required String itemId,
    required Quantity countedOnHand,
    DateTime? occurredAt,
    String? note,
  }) async {
    final onHand = await _db.ledgerDao.onHandMicros(itemId);
    final delta = countedOnHand.micros - onHand;
    if (delta == 0) {
      // Nothing to reconcile; deltas are never zero (§5). No command is
      // submitted and the receipt carries no created records.
      return Ok(
        CommandReceipt(
          commandId: CommandId(_ids.newId()),
          appliedAt: _clock.now(),
          createdRecordIds: const [],
        ),
      );
    }
    return _submit(
      AppendMovement(
        MovementDraft(
          itemId: ItemId(itemId),
          kind: MovementKind.adjust,
          deltaMicros: delta,
          occurredAt: _instant(occurredAt),
          note: note ?? '',
        ),
      ),
    );
  }

  @override
  Future<Result<CommandReceipt>> correct({
    required String movementId,
    MovementFormDraft? replacement,
    required String reason,
  }) {
    MovementDraft? replacementDraft;
    if (replacement != null) {
      try {
        replacementDraft = _toMovementDraft(replacement);
      } on ArgumentError catch (e) {
        return Future.value(Err(ValidationError(e.message.toString())));
      }
    }
    return _submit(
      CorrectMovement(
        target: MovementId(movementId),
        replacement: replacementDraft,
        reason: reason,
      ),
    );
  }

  @override
  Stream<StockPosition> watchPosition(String itemId) =>
      _ledger.watchPosition(ItemId(itemId));

  @override
  Stream<List<MovementView>> watchMovements(MovementFilter filter) {
    final where = <String>[];
    final variables = <Variable>[];
    if (filter.itemId != null) {
      variables.add(Variable<String>(filter.itemId!));
      where.add('m.item_id = ?${variables.length}');
    }
    if (filter.eventId != null) {
      variables.add(Variable<String>(filter.eventId!));
      where.add('m.event_id = ?${variables.length}');
    }
    final kinds = filter.kinds;
    if (kinds != null && kinds.isNotEmpty) {
      final names = (kinds.map((k) => k.dbValue).toList()..sort())
          .map((k) => "'$k'")
          .join(', ');
      where.add('m.kind IN ($names)');
    }
    variables.add(Variable<int>(filter.limit));
    final sql =
        'SELECT m.*, i.name AS item_name, i.unit AS item_unit, '
        'r.id AS reversed_by '
        'FROM inventory_movements m '
        'JOIN items i ON i.id = m.item_id '
        'LEFT JOIN inventory_movements r ON r.reverses_movement_id = m.id '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
        // Business time first: the screens group these rows by occurredAt,
        // so ordering by id alone wedges a backdated entry between today's
        // and repeats the day header. Id breaks ties (same instant).
        'ORDER BY m.occurred_at_micros DESC, m.id DESC '
        'LIMIT ?${variables.length}';
    return _db
        .customSelect(
          sql,
          variables: variables,
          readsFrom: {_db.inventoryMovements, _db.items},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              MovementView(
                movement: Movement(
                  id: MovementId(row.read<String>('id')),
                  itemId: ItemId(row.read<String>('item_id')),
                  kind: MovementKind.fromDb(row.read<String>('kind')),
                  deltaMicros: row.read<int>('delta_micros'),
                  eventId: row.read<String?>('event_id') == null
                      ? null
                      : EventId(row.read<String>('event_id')),
                  reverses: row.read<String?>('reverses_movement_id') == null
                      ? null
                      : MovementId(row.read<String>('reverses_movement_id')),
                  occurredAt: Instant(row.read<int>('occurred_at_micros')),
                  recordedAt: Instant(row.read<int>('recorded_at_micros')),
                  sourceCommandId: CommandId(
                    row.read<String>('source_command_id'),
                  ),
                  note: row.read<String>('note'),
                ),
                itemName: row.read<String>('item_name'),
                itemUnit: ItemUnit.fromDb(row.read<String>('item_unit')),
                reversedByMovementId: row.read<String?>('reversed_by'),
              ),
          ],
        );
  }

  @override
  Stream<int> watchVersion() => _ledger.watchVersion();

  MovementDraft _toMovementDraft(MovementFormDraft draft) {
    if (draft.quantity.micros <= 0) {
      throw ArgumentError('quantity must be positive');
    }
    final delta = switch (draft.kind) {
      MovementKind.receive => draft.quantity.micros,
      MovementKind.waste => -draft.quantity.micros,
      MovementKind.adjust =>
        draft.negativeAdjust ? -draft.quantity.micros : draft.quantity.micros,
      MovementKind.consume || MovementKind.reversal => throw ArgumentError(
        'only receive, waste, and adjust are form-submittable',
      ),
    };
    return MovementDraft(
      itemId: ItemId(draft.itemId),
      kind: draft.kind,
      deltaMicros: delta,
      eventId: draft.eventId == null ? null : EventId(draft.eventId!),
      occurredAt: _instant(draft.occurredAt),
      note: draft.note,
    );
  }

  Instant? _instant(DateTime? value) =>
      value == null ? null : Instant(value.toUtc().microsecondsSinceEpoch);

  Future<Result<CommandReceipt>> _submit(WorkspaceCommand command) =>
      _approval.submit(
        Proposal(
          commandId: CommandId(_ids.newId()),
          origin: ProposalOrigin.form,
          command: command,
          createdAt: _clock.now(),
        ),
      );
}
