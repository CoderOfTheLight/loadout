import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/unit_ratio.dart';

void main() {
  test('gcd normalization', () {
    final ratio = UnitRatio(4, 6);
    expect(ratio.numerator, 2);
    expect(ratio.denominator, 3);
    expect(UnitRatio(1000000, 1000000), UnitRatio(1, 1));
  });

  test('equality and hashCode on the normalized pair', () {
    expect(UnitRatio(2, 4), UnitRatio(1, 2));
    expect(UnitRatio(2, 4).hashCode, UnitRatio(1, 2).hashCode);
    expect(UnitRatio(2, 3) == UnitRatio(3, 2), isFalse);
  });

  test('rejects non-positive components', () {
    expect(() => UnitRatio(0, 3), throwsArgumentError);
    expect(() => UnitRatio(3, 0), throwsArgumentError);
    expect(() => UnitRatio(-1, 3), throwsArgumentError);
    expect(() => UnitRatio(3, -1), throwsArgumentError);
  });

  test('applyCeil matches multiplyRatio across in-range inputs', () {
    const microsSamples = [0, 1, 2, 999999, 1000000, 1500000, 123456789];
    const ratios = [(1, 3), (110, 100), (120, 100), (7, 5), (1, 1), (13, 7)];
    for (final micros in microsSamples) {
      for (final (n, d) in ratios) {
        final q = Quantity.fromMicros(micros);
        expect(
          UnitRatio(n, d).applyCeil(q),
          q.multiplyRatio(n, d),
          reason: '$micros × $n/$d',
        );
      }
    }
  });

  test('applyCeil is exact where legacy int64 math would wrap', () {
    // micros × numerator ≈ 1.1e27 wraps int64; the exact result is in range.
    final value = Quantity.fromMicros(Quantity.maxMicros);
    final numerator = (1 << 40) + 1; // odd → no gcd cancellation
    final denominator = 1 << 41;
    final ratio = UnitRatio(numerator, denominator);
    final expected =
        (BigInt.from(Quantity.maxMicros) * BigInt.from(numerator) +
            BigInt.from(denominator) -
            BigInt.one) ~/
        BigInt.from(denominator);
    expect(
      expected <= BigInt.from(Quantity.maxMicros),
      isTrue,
      reason: 'test setup: exact result must be in range',
    );
    expect(ratio.applyCeil(value).micros, expected.toInt());
  });

  test(
    'applyCeil throws QuantityOverflowError when the result exceeds cap',
    () {
      final value = Quantity.fromMicros(Quantity.maxMicros);
      expect(
        () => UnitRatio(1 << 40, 1).applyCeil(value),
        throwsA(isA<QuantityOverflowError>()),
      );
      expect(
        () => UnitRatio(2, 1).applyCeil(value),
        throwsA(isA<QuantityOverflowError>()),
      );
    },
  );

  test('applyCeil at the cap exactly is legal', () {
    final value = Quantity.fromMicros(Quantity.maxMicros);
    expect(UnitRatio(1, 1).applyCeil(value).micros, Quantity.maxMicros);
  });
}
