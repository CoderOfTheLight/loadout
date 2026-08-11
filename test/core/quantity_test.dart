import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/quantity.dart';

void main() {
  group('fromMicros', () {
    test('rejects negative', () {
      expect(() => Quantity.fromMicros(-1), throwsArgumentError);
    });

    test('accepts zero and the cap exactly', () {
      expect(Quantity.fromMicros(0), Quantity.zero);
      expect(
        Quantity.fromMicros(Quantity.maxMicros).micros,
        Quantity.maxMicros,
      );
    });

    test('throws QuantityOverflowError above the cap', () {
      expect(
        () => Quantity.fromMicros(Quantity.maxMicros + 1),
        throwsA(isA<QuantityOverflowError>()),
      );
    });

    test('cap is 1e15 micros', () {
      expect(Quantity.maxMicros, 1000000000000000);
    });
  });

  group('plus', () {
    test('adds exactly', () {
      expect(
        Quantity.fromMicros(1500000).plus(Quantity.fromMicros(2500000)),
        Quantity.fromMicros(4000000),
      );
    });

    test('reaching the cap exactly is legal', () {
      final sum = Quantity.fromMicros(
        Quantity.maxMicros - 1,
      ).plus(Quantity.fromMicros(1));
      expect(sum.micros, Quantity.maxMicros);
    });

    test('one micro over the cap throws', () {
      expect(
        () => Quantity.fromMicros(
          Quantity.maxMicros,
        ).plus(Quantity.fromMicros(1)),
        throwsA(isA<QuantityOverflowError>()),
      );
    });
  });

  group('subtractFloor', () {
    test('clamps at zero', () {
      expect(
        Quantity.fromMicros(5).subtractFloor(Quantity.fromMicros(7)),
        Quantity.zero,
      );
    });

    test('exact difference otherwise', () {
      expect(
        Quantity.fromMicros(7).subtractFloor(Quantity.fromMicros(5)),
        Quantity.fromMicros(2),
      );
      expect(
        Quantity.fromMicros(5).subtractFloor(Quantity.fromMicros(5)),
        Quantity.zero,
      );
    });
  });

  group('multiplyRatio', () {
    test('rounds up: 1 micro × 1/3 → 1 micro', () {
      expect(Quantity.fromMicros(1).multiplyRatio(1, 3).micros, 1);
    });

    test('exact multiples stay unrounded', () {
      expect(Quantity.fromMicros(300).multiplyRatio(1, 3).micros, 100);
      expect(Quantity.whole(20).multiplyRatio(110, 100), Quantity.whole(22));
    });

    test('numerator zero stays legal (frozen behavior)', () {
      expect(Quantity.fromMicros(123).multiplyRatio(0, 5), Quantity.zero);
    });

    test('invalid ratios throw', () {
      expect(
        () => Quantity.fromMicros(1).multiplyRatio(-1, 3),
        throwsArgumentError,
      );
      expect(
        () => Quantity.fromMicros(1).multiplyRatio(1, 0),
        throwsArgumentError,
      );
      expect(
        () => Quantity.fromMicros(1).multiplyRatio(1, -3),
        throwsArgumentError,
      );
    });

    test('result over the cap throws QuantityOverflowError', () {
      expect(
        () => Quantity.fromMicros(Quantity.maxMicros).multiplyRatio(2, 1),
        throwsA(isA<QuantityOverflowError>()),
      );
    });
  });

  group('roundUpTo', () {
    test('exact multiple stays put', () {
      expect(
        Quantity.whole(24).roundUpTo(Quantity.whole(12)),
        Quantity.whole(24),
      );
    });

    test('one micro above a multiple rounds to the next', () {
      expect(
        Quantity.fromMicros(12000001).roundUpTo(Quantity.whole(12)),
        Quantity.whole(24),
      );
    });

    test('zero rounds to zero', () {
      expect(Quantity.zero.roundUpTo(Quantity.whole(12)), Quantity.zero);
    });

    test('zero increment throws', () {
      expect(
        () => Quantity.whole(1).roundUpTo(Quantity.zero),
        throwsArgumentError,
      );
    });

    test('rounding above the cap throws QuantityOverflowError', () {
      // 1e15 is not divisible by 7; the next multiple exceeds the cap.
      expect(
        () => Quantity.fromMicros(
          Quantity.maxMicros,
        ).roundUpTo(Quantity.fromMicros(7)),
        throwsA(isA<QuantityOverflowError>()),
      );
    });
  });
}
