/// §11.1 family B (pure fold parts): empty ledger, per-kind sign effects,
/// determinism under permutation, inclusive as-of boundary, and reversals
/// taking effect at their own occurredAt. The write-path halves of family B
/// (receipt warnings, recordedAt monotonicity, reversal rejection) live in
/// test/db/ledger_write_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/time.dart';
import 'package:loadout/features/inventory/domain/ledger_math.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

Movement m(
  String id, {
  required MovementKind kind,
  required int delta,
  int occurredAt = 1000,
  int recordedAt = 1000,
  String? reverses,
}) => Movement(
  id: MovementId(id.padRight(26, '0')),
  itemId: const ItemId('ITEM00000000000000000000I1'),
  kind: kind,
  deltaMicros: delta,
  reverses: reverses == null ? null : MovementId(reverses.padRight(26, '0')),
  occurredAt: Instant(occurredAt),
  recordedAt: Instant(recordedAt),
  sourceCommandId: const CommandId('CMD00000000000000000000001'),
);

void main() {
  group('LedgerMath.position', () {
    test('empty ledger folds to zero and is not negative', () {
      final position = LedgerMath.position(const []);
      expect(position.onHandMicros, 0);
      expect(position.isNegative, isFalse);
      expect(position.onHand.micros, 0);
    });

    test('per-kind sign effects sum exactly', () {
      final position = LedgerMath.position([
        m('M1', kind: MovementKind.receive, delta: 5000000),
        m('M2', kind: MovementKind.consume, delta: -2000000),
        m('M3', kind: MovementKind.waste, delta: -1000000),
        m('M4', kind: MovementKind.adjust, delta: -500000),
        m('M5', kind: MovementKind.adjust, delta: 250000),
        m('M6', kind: MovementKind.reversal, delta: 1000000, reverses: 'M3'),
      ]);
      expect(position.onHandMicros, 2750000);
    });

    test('negative sums stay signed; display view clamps', () {
      final position = LedgerMath.position([
        m('M1', kind: MovementKind.waste, delta: -1500000),
      ]);
      expect(position.onHandMicros, -1500000);
      expect(position.isNegative, isTrue);
      expect(position.onHand.micros, 0); // clamped display view
    });

    test('fold is deterministic under permutation (tie-broken sort)', () {
      // Same occurredAt everywhere: ties broken by recordedAt then id.
      final movements = [
        m('M1', kind: MovementKind.receive, delta: 3000000, recordedAt: 5),
        m('M2', kind: MovementKind.waste, delta: -1000000, recordedAt: 5),
        m('M3', kind: MovementKind.adjust, delta: 400000, recordedAt: 4),
        m('M4', kind: MovementKind.adjust, delta: -150000, recordedAt: 6),
      ];
      final expected = LedgerMath.position(movements).onHandMicros;
      final permutations = [
        [movements[3], movements[2], movements[1], movements[0]],
        [movements[1], movements[3], movements[0], movements[2]],
        [movements[2], movements[0], movements[3], movements[1]],
      ];
      for (final permutation in permutations) {
        expect(LedgerMath.position(permutation).onHandMicros, expected);
      }
      expect(expected, 2250000);
    });

    test('asOf is inclusive on occurredAt; +1 µs falls outside', () {
      final movements = [
        m('M1', kind: MovementKind.receive, delta: 1000000, occurredAt: 100),
        m('M2', kind: MovementKind.receive, delta: 2000000, occurredAt: 101),
      ];
      expect(
        LedgerMath.position(movements, asOf: const Instant(100)).onHandMicros,
        1000000,
      );
      expect(
        LedgerMath.position(movements, asOf: const Instant(101)).onHandMicros,
        3000000,
      );
      expect(
        LedgerMath.position(movements, asOf: const Instant(99)).onHandMicros,
        0,
      );
    });

    test('a reversal takes effect at ITS OWN occurredAt', () {
      final movements = [
        m('M1', kind: MovementKind.receive, delta: 4000000, occurredAt: 100),
        m(
          'M2',
          kind: MovementKind.reversal,
          delta: -4000000,
          occurredAt: 200,
          reverses: 'M1',
        ),
      ];
      // As-of before the reversal: the original still shows.
      expect(
        LedgerMath.position(movements, asOf: const Instant(150)).onHandMicros,
        4000000,
      );
      // As-of at/after the reversal: net zero.
      expect(
        LedgerMath.position(movements, asOf: const Instant(200)).onHandMicros,
        0,
      );
      expect(LedgerMath.position(movements).onHandMicros, 0);
    });
  });
}
