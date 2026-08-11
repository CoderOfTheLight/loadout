/// §11.1 family B (write-path halves): sign-per-kind and draft-kind
/// enforcement, negative on-hand as a warning that never blocks, recordedAt
/// monotonicity under a same-microsecond FixedClock, corrections as
/// reversal+replacement, and the reversed-at-most-once rules.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/inventory_ledger.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/inventory/infrastructure/drift_inventory_ledger.dart';

import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;
  late String itemId;

  setUp(() async {
    h = WritePathHarness();
    itemId = await h.createItem(name: 'Tortillas');
  });

  tearDown(() => h.close());

  AppendMovement draft(MovementKind kind, int delta, {String? eventId}) =>
      AppendMovement(
        MovementDraft(
          itemId: ItemId(itemId),
          kind: kind,
          deltaMicros: delta,
          eventId: eventId == null ? null : EventId(eventId),
        ),
      );

  group('draft-kind and sign enforcement', () {
    test('consume is not form-submittable', () async {
      final error = await h.err(draft(MovementKind.consume, -1000000));
      expect(error, isA<ValidationError>());
      expect(error.message, contains('closeout'));
    });

    test('reversal is not a legal draft kind', () async {
      expect(
        await h.err(draft(MovementKind.reversal, 1000000)),
        isA<ValidationError>(),
      );
    });

    test('zero delta, wrong signs, and cap overflow rejected', () async {
      expect(
        await h.err(draft(MovementKind.adjust, 0)),
        isA<ValidationError>(),
      );
      expect(
        await h.err(draft(MovementKind.receive, -1000000)),
        isA<ValidationError>(),
      );
      expect(
        await h.err(draft(MovementKind.waste, 1000000)),
        isA<ValidationError>(),
      );
      expect(
        await h.err(draft(MovementKind.receive, Quantity.maxMicros + 1)),
        isA<DomainOverflowError>(),
      );
    });

    test('receive may not be event-linked', () async {
      final eventId = await h.createEvent(name: 'Market');
      expect(
        await h.err(draft(MovementKind.receive, 1000000, eventId: eventId)),
        isA<ValidationError>(),
      );
    });
  });

  group('negative on-hand (§5: warns, never blocks)', () {
    test('a movement driving on-hand negative succeeds with '
        'NEGATIVE_ON_HAND', () async {
      await h.receive(itemId, 2000000);
      final receipt = await h.ok(draft(MovementKind.waste, -5000000));
      expect(receipt.warnings, contains('NEGATIVE_ON_HAND'));
      expect(await h.onHand(itemId), -3000000);
      expect(await h.count('inventory_movements'), 2, reason: 'row written');
    });

    test('no warning while on-hand stays nonnegative', () async {
      final receipt = await h.ok(draft(MovementKind.receive, 2000000));
      expect(receipt.warnings, isEmpty);
    });
  });

  group('recordedAt monotonicity', () {
    test('same-microsecond FixedClock ties are bumped by 1 µs', () async {
      // The clock never advances: every recordedAt must still be strictly
      // increasing in application order.
      final ids = [
        await h.receive(itemId, 1000000),
        await h.receive(itemId, 2000000),
        await h.receive(itemId, 3000000),
      ];
      final recorded = [
        for (final id in ids) (await h.movementRow(id)).recordedAtMicros,
      ];
      expect(recorded[1], recorded[0] + 1);
      expect(recorded[2], recorded[1] + 1);
    });
  });

  group('corrections (§5)', () {
    test('reversal mirrors the target exactly; replacement lands in the '
        'same command', () async {
      final targetId = await h.receive(itemId, 5000000);
      final receipt = await h.ok(
        CorrectMovement(
          target: MovementId(targetId),
          replacement: MovementDraft(
            itemId: ItemId(itemId),
            kind: MovementKind.receive,
            deltaMicros: 4000000,
          ),
          reason: 'typo: was 5, actually 4',
        ),
      );
      expect(receipt.createdRecordIds, hasLength(2));
      final reversal = await h.movementRow(receipt.createdRecordIds[0]);
      expect(reversal.kind, 'reversal');
      expect(reversal.deltaMicros, -5000000);
      expect(reversal.itemId, itemId);
      expect(reversal.reversesMovementId, targetId);
      expect(reversal.note, 'typo: was 5, actually 4');
      final replacement = await h.movementRow(receipt.createdRecordIds[1]);
      expect(replacement.kind, 'receive');
      expect(replacement.deltaMicros, 4000000);
      // Both rows share the correcting command.
      expect(replacement.sourceCommandId, reversal.sourceCommandId);
      expect(await h.onHand(itemId), 4000000);
    });

    test('a movement is reversible at most once', () async {
      final targetId = await h.receive(itemId, 5000000);
      await h.ok(CorrectMovement(target: MovementId(targetId), reason: 'undo'));
      final error = await h.err(
        CorrectMovement(target: MovementId(targetId), reason: 'undo again'),
      );
      expect(error, isA<AlreadyReversedError>());
    });

    test('a reversal cannot be reversed', () async {
      final targetId = await h.receive(itemId, 5000000);
      final receipt = await h.ok(
        CorrectMovement(target: MovementId(targetId), reason: 'undo'),
      );
      final error = await h.err(
        CorrectMovement(
          target: MovementId(receipt.createdRecordIds.single),
          reason: 'meta-undo',
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('fresh original'));
    });
  });

  group('InventoryService count mode', () {
    test('computes the signed adjust from counted - derived', () async {
      final service = DriftInventoryService(
        h.db,
        h.applier,
        ledger: DriftInventoryLedger(h.db, idGenerator: h.ids),
        idGenerator: h.ids,
        clock: h.clock,
      );
      await h.receive(itemId, 5000000);
      final result = await service.recordCount(
        itemId: itemId,
        countedOnHand: Quantity.fromMicros(3500000),
      );
      final receipt = result.fold(
        (r) => r,
        (e) => fail('expected Ok, got ${e.code}'),
      );
      final adjust = await h.movementRow(receipt.createdRecordIds.single);
      expect(adjust.kind, 'adjust');
      expect(adjust.deltaMicros, -1500000);
      expect(await h.onHand(itemId), 3500000);

      // Counting the current value records nothing.
      final noop = await service.recordCount(
        itemId: itemId,
        countedOnHand: Quantity.fromMicros(3500000),
      );
      expect(
        noop.fold((r) => r.createdRecordIds, (e) => fail(e.code)),
        isEmpty,
      );
      expect(await h.count('inventory_movements'), 2);
    });
  });
}
