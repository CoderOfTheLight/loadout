/// §11.1 family F (general write path): idempotency, unknown-id rejection
/// for every command type, archived/cancelled/closed write defense,
/// unit-lock, audit-row coherence, Diag wiring, and the frozen v1
/// ApprovalService agent-path stubs.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/approval/domain/proposal.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/forecasting/domain/snapshot.dart';
import 'package:loadout/features/inventory/domain/inventory_ledger.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import 'fixtures.dart';
import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;

  setUp(() => h = WritePathHarness());

  tearDown(() => h.close());

  group('idempotency', () {
    test('same commandId twice → one write and the original receipt', () async {
      final command = CreateItem(
        name: 'Tortillas',
        unit: ItemUnit.each,
        packSize: Quantity.whole(12),
      );
      final first = await h.ok(command, commandId: tid('CMD1'));
      final second = await h.ok(command, commandId: tid('CMD1'));
      expect(await h.count('items'), 1);
      expect(await h.count('commands'), 1);
      expect(second.commandId as String, first.commandId as String);
      expect(second.createdRecordIds, first.createdRecordIds);
      expect(second.appliedAt.epochMicrosUtc, first.appliedAt.epochMicrosUtc);
      expect(second.warnings, first.warnings);
    });

    test('same commandId with different payload → DuplicateIdError', () async {
      await h.ok(
        CreateItem(
          name: 'Tortillas',
          unit: ItemUnit.each,
          packSize: Quantity.whole(12),
        ),
        commandId: tid('CMD1'),
      );
      final error = await h.err(
        CreateItem(
          name: 'Salsa',
          unit: ItemUnit.kg,
          packSize: Quantity.whole(1),
        ),
        commandId: tid('CMD1'),
      );
      expect(error, isA<DuplicateIdError>());
      expect(await h.count('items'), 1);
    });

    test('replaying a rejected commandId returns the original error', () async {
      final command = UpdateItem(itemId: ItemId(tid('NOPE')), name: 'X');
      final first = await h.err(command, commandId: tid('CMD2'));
      final second = await h.err(command, commandId: tid('CMD2'));
      expect(first, isA<NotFoundError>());
      expect(second, isA<NotFoundError>());
      expect(second.message, first.message);
      expect(await h.count('commands'), 1);
    });

    test('malformed commandId (not 26 chars) is rejected up front', () async {
      final error = await h.err(
        CreateItem(
          name: 'Tortillas',
          unit: ItemUnit.each,
          packSize: Quantity.whole(12),
        ),
        commandId: 'short',
      );
      expect(error, isA<ValidationError>());
      expect(await h.count('commands'), 0);
    });
  });

  group('unknown ids → NotFoundError, nothing written', () {
    test('every command type with a reference', () async {
      // A live snapshot line for the override case's "line exists" check is
      // deliberately absent — everything here must be NOT_FOUND.
      final unknownItem = ItemId(tid('NOITEM'));
      final unknownEvent = EventId(tid('NOEVENT'));
      final commands = <String, WorkspaceCommand>{
        'UpdateItem': UpdateItem(itemId: unknownItem, name: 'X'),
        'SetItemArchived': SetItemArchived(itemId: unknownItem, archived: true),
        'CreateEvent (planned item)': CreateEvent(
          name: 'E',
          scheduledDate: '2026-08-01',
          plannedItemIds: [unknownItem],
        ),
        'UpdateEvent': UpdateEvent(eventId: unknownEvent, name: 'X'),
        'ActivateEvent': ActivateEvent(unknownEvent),
        'CancelEvent': CancelEvent(eventId: unknownEvent, reason: 'because'),
        'AppendMovement': AppendMovement(
          MovementDraft(
            itemId: unknownItem,
            kind: MovementKind.receive,
            deltaMicros: 1000000,
          ),
        ),
        'CorrectMovement': CorrectMovement(
          target: MovementId(tid('NOMOVE')),
          reason: 'fix',
        ),
        'RecordCloseout': RecordCloseout(
          eventId: unknownEvent,
          confirmedExposure: 10,
          lines: const [],
        ),
        'ReviseCloseout': ReviseCloseout(
          eventId: unknownEvent,
          confirmedExposure: 10,
          lines: const [],
        ),
        'CreateRecipe': CreateRecipe(
          outputItemId: unknownItem,
          name: 'R',
          firstRevision: RecipeRevisionDraft(
            yieldQuantity: Quantity.whole(1),
            lines: [
              RecipeLineDraft(
                ingredientItemId: unknownItem,
                quantityPerBatch: Quantity.whole(1),
              ),
            ],
          ),
        ),
        'AddRecipeRevision': AddRecipeRevision(
          recipeId: RecipeId(tid('NORECIPE')),
          revision: RecipeRevisionDraft(
            yieldQuantity: Quantity.whole(1),
            lines: [
              RecipeLineDraft(
                ingredientItemId: unknownItem,
                quantityPerBatch: Quantity.whole(1),
              ),
            ],
          ),
        ),
        'SetRecipeArchived': SetRecipeArchived(
          recipeId: RecipeId(tid('NORECIPE')),
          archived: true,
        ),
        'SaveForecastSnapshot': SaveForecastSnapshot(
          ForecastSnapshotDraft(
            eventId: unknownEvent,
            policy: PlanningPolicy.balanced,
            upcomingExposure: 100,
            historyWindow: 12,
            inputsHash: 'a' * 64,
            assumptionsJson: '{}',
            lines: const [],
          ),
        ),
        'OverrideForecastLine': OverrideForecastLine(
          snapshotId: ForecastSnapshotId(tid('NOSNAP')),
          itemId: unknownItem,
          overrideLoad: Quantity.whole(1),
          reason: 'baseline',
        ),
      };
      final before = await h.effectCounts();
      for (final entry in commands.entries) {
        final error = await h.err(entry.value);
        expect(
          error,
          isA<NotFoundError>(),
          reason:
              '${entry.key} must reject unknown ids with NOT_FOUND, '
              'got ${error.code}',
        );
      }
      expect(await h.effectCounts(), before, reason: 'nothing written');
      // Every attempt is auditable: one rejected commands row each.
      final rows = await h.db.select(h.db.commands).get();
      expect(rows.length, commands.length);
      expect(rows.every((r) => r.status == 'rejected'), isTrue);
      expect(
        rows.every((r) => r.rejectedReason!.startsWith('NOT_FOUND')),
        isTrue,
      );
    });
  });

  group('archived / cancelled / closed defense', () {
    test('archived item rejects writes', () async {
      final itemId = await h.createItem(name: 'Tortillas');
      await h.ok(SetItemArchived(itemId: ItemId(itemId), archived: true));
      final update = await h.err(
        UpdateItem(itemId: ItemId(itemId), name: 'New name'),
      );
      expect(update, isA<ValidationError>());
      final movement = await h.err(
        AppendMovement(
          MovementDraft(
            itemId: ItemId(itemId),
            kind: MovementKind.receive,
            deltaMicros: 1000000,
          ),
        ),
      );
      expect(movement, isA<ValidationError>());
      final recipe = await h.err(
        CreateRecipe(
          outputItemId: ItemId(itemId),
          name: 'R',
          firstRevision: RecipeRevisionDraft(
            yieldQuantity: Quantity.whole(1),
            lines: [
              RecipeLineDraft(
                ingredientItemId: ItemId(itemId),
                quantityPerBatch: Quantity.whole(1),
              ),
            ],
          ),
        ),
      );
      expect(recipe, isA<ValidationError>());
    });

    test('cancelled event rejects writes', () async {
      final itemId = await h.createItem(name: 'Tortillas');
      final eventId = await h.createEvent(name: 'Market');
      await h.ok(CancelEvent(eventId: EventId(eventId), reason: 'rain'));
      expect(
        await h.err(UpdateEvent(eventId: EventId(eventId), name: 'X')),
        isA<ValidationError>(),
      );
      expect(
        await h.err(
          AppendMovement(
            MovementDraft(
              itemId: ItemId(itemId),
              kind: MovementKind.waste,
              deltaMicros: -1000000,
              eventId: EventId(eventId),
            ),
          ),
        ),
        isA<ValidationError>(),
      );
    });

    test('activate and cancel are legal only from planned', () async {
      final eventId = await h.createEvent(name: 'Market');
      await h.ok(ActivateEvent(EventId(eventId)));
      expect(
        await h.err(ActivateEvent(EventId(eventId))),
        isA<ValidationError>(),
      );
      expect(
        await h.err(CancelEvent(eventId: EventId(eventId), reason: 'rain')),
        isA<ValidationError>(),
        reason: 'an activated event must be closed out, not cancelled',
      );
    });
  });

  group('unit lock (§4, family F)', () {
    test('unit is editable before the first movement, locked after', () async {
      final itemId = await h.createItem(name: 'Flour', unit: ItemUnit.each);

      // Pre-movement: unit change applies.
      await h.ok(UpdateItem(itemId: ItemId(itemId), unit: ItemUnit.kg));
      expect((await h.itemRow(itemId)).unit, 'kg');

      await h.receive(itemId, 5000000);

      final locked = await h.err(
        UpdateItem(itemId: ItemId(itemId), unit: ItemUnit.g),
      );
      expect(locked, isA<ImmutableRecordError>());
      expect((await h.itemRow(itemId)).unit, 'kg');

      // Same-unit and non-unit updates still pass.
      await h.ok(
        UpdateItem(
          itemId: ItemId(itemId),
          unit: ItemUnit.kg,
          name: 'Masa flour',
        ),
      );
      expect((await h.itemRow(itemId)).name, 'Masa flour');
    });
  });

  group('audit rows and Diag', () {
    test('applied command row is terminal and coherent', () async {
      await h.ok(
        CreateItem(
          name: 'Tortillas',
          unit: ItemUnit.each,
          packSize: Quantity.whole(12),
        ),
        commandId: tid('CMD1'),
      );
      final row = await h.commandRow(tid('CMD1'));
      expect(row.status, 'applied');
      expect(row.kind, 'CreateItem');
      expect(row.origin, 'form');
      expect(row.appliedAtMicros, isNotNull);
      expect(row.rejectedReason, isNull);
      expect(row.payloadJson, contains('"name":"Tortillas"'));
    });

    test('rejected command row carries the machine-readable reason', () async {
      await h.err(
        UpdateItem(itemId: ItemId(tid('NOPE')), name: 'X'),
        commandId: tid('CMD2'),
      );
      final row = await h.commandRow(tid('CMD2'));
      expect(row.status, 'rejected');
      expect(row.appliedAtMicros, isNull);
      expect(row.rejectedReason, startsWith('NOT_FOUND: '));
    });

    test(
      'Diag receives commandApplied / commandRejected, content-free',
      () async {
        final receipt = await h.ok(
          CreateItem(
            name: 'Tortillas',
            unit: ItemUnit.each,
            packSize: Quantity.whole(12),
          ),
        );
        await h.err(UpdateItem(itemId: ItemId(tid('NOPE')), name: 'X'));
        final applied = h.diag.ofType(DiagEvent.commandApplied);
        expect(applied, hasLength(1));
        expect(applied.single.count, receipt.createdRecordIds.length);
        final rejected = h.diag.ofType(DiagEvent.commandRejected);
        expect(rejected, hasLength(1));
        expect(rejected.single.errorType, 'NotFoundError');
      },
    );
  });

  group('live-name uniqueness', () {
    test('duplicate live name rejected; archived frees the name', () async {
      final itemId = await h.createItem(name: 'Tortillas');
      expect(
        await h.err(
          CreateItem(
            name: 'tortillas', // case-insensitive
            unit: ItemUnit.each,
            packSize: Quantity.whole(1),
          ),
        ),
        isA<ValidationError>(),
      );
      await h.ok(SetItemArchived(itemId: ItemId(itemId), archived: true));
      await h.createItem(name: 'Tortillas');
      // Unarchiving the old one would now collide.
      expect(
        await h.err(SetItemArchived(itemId: ItemId(itemId), archived: false)),
        isA<ValidationError>(),
      );
    });
  });

  group('v1 ApprovalService agent path (frozen Gate 4 seam)', () {
    test(
      'stage/approve/reject return NotAvailableError; pending is empty',
      () async {
        final proposal = Proposal(
          commandId: CommandId(tid('CMD9')),
          origin: ProposalOrigin.agent,
          command: CreateItem(
            name: 'Agent item',
            unit: ItemUnit.each,
            packSize: Quantity.whole(1),
          ),
          createdAt: h.clock.now(),
        );
        final staged = await h.applier.stage(proposal);
        staged.fold(
          (_) => fail('stage must not succeed in v1'),
          (error) => expect(error, isA<NotAvailableError>()),
        );
        final approved = await h.applier.approve(CommandId(tid('CMD9')));
        approved.fold(
          (_) => fail('approve must not succeed in v1'),
          (error) => expect(error, isA<NotAvailableError>()),
        );
        final rejected = await h.applier.reject(
          CommandId(tid('CMD9')),
          reason: 'no',
        );
        rejected.fold(
          (_) => fail('reject must not succeed in v1'),
          (error) => expect(error, isA<NotAvailableError>()),
        );
        expect(await h.applier.pending(), isEmpty);
        expect(await h.count('commands'), 0, reason: 'stage writes nothing');
      },
    );
  });
}
