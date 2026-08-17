import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/money.dart';

void main() {
  group('construction', () {
    test('fromCents accepts zero and positive amounts', () {
      expect(Money.fromCents(0).cents, 0);
      expect(Money.fromCents(1).cents, 1);
      expect(Money.fromCents(100000000).cents, 100000000);
      expect(Money.zero.cents, 0);
    });

    test('negative cents are programmer error', () {
      expect(() => Money.fromCents(-1), throwsArgumentError);
    });

    test('no upper bound on Money itself: an event TOTAL may exceed the '
        'per-unit price cap', () {
      // The 1e8-cent cap belongs to a stored unit price (validator+CHECK);
      // Money must be able to carry legitimate sums above it.
      expect(Money.fromCents(100000001).cents, 100000001);
    });

    test('value equality and ordering', () {
      expect(Money.fromCents(1250), Money.fromCents(1250));
      expect(Money.fromCents(1250).hashCode, Money.fromCents(1250).hashCode);
      expect(Money.fromCents(1), isNot(Money.fromCents(2)));
      expect(Money.fromCents(1).compareTo(Money.fromCents(2)), lessThan(0));
      expect(Money.fromCents(2).compareTo(Money.fromCents(2)), 0);
    });
  });

  group('arithmetic', () {
    test('plus is exact integer addition', () {
      expect(
        Money.fromCents(1250).plus(Money.fromCents(99)),
        Money.fromCents(1349),
      );
      expect(Money.zero.plus(Money.zero), Money.zero);
    });

    test('times whole counts', () {
      expect(Money.fromCents(299).times(3), Money.fromCents(897));
      expect(Money.fromCents(299).times(0), Money.zero);
      expect(() => Money.fromCents(1).times(-1), throwsArgumentError);
    });

    test('timesQuantityMicros: exact integer cost of fractional amounts', () {
      // 1.5 units at $2.99 = 448.5 cents → TRUNCATES to 448 (documented).
      expect(
        Money.fromCents(299).timesQuantityMicros(1500000),
        Money.fromCents(448),
      );
      // Whole units are exact.
      expect(
        Money.fromCents(299).timesQuantityMicros(3000000),
        Money.fromCents(897),
      );
      expect(Money.fromCents(299).timesQuantityMicros(0), Money.zero);
      expect(
        () => Money.fromCents(1).timesQuantityMicros(-1),
        throwsArgumentError,
      );
    });

    test('PINNED: timesQuantityMicros survives the full envelope without '
        'wrapping — cap price × cap depletion needs BigInt', () {
      // 1e8 cents × 1e12 micros = 1e20 intermediate (> int64), ÷ 1e6 = 1e14.
      expect(
        Money.fromCents(100000000).timesQuantityMicros(1000000000000),
        Money.fromCents(100000000000000),
      );
      // And the ledger's own 1e15-micros magnitude cap stays safe too.
      expect(
        Money.fromCents(100000000).timesQuantityMicros(1000000000000000),
        Money.fromCents(100000000000000000),
      );
    });
  });
}
