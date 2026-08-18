import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/quantity_codec.dart';

void main() {
  group('parse', () {
    test('exact decimal splitting to micros', () {
      expect(QuantityCodec.parse('1.5').micros, 1500000);
      expect(QuantityCodec.parse('1,5').micros, 1500000);
      expect(QuantityCodec.parse('12').micros, 12000000);
      expect(QuantityCodec.parse('0.000001').micros, 1);
      expect(QuantityCodec.parse('.5').micros, 500000);
      expect(QuantityCodec.parse('0').micros, 0);
      expect(QuantityCodec.parse('007').micros, 7000000);
      expect(QuantityCodec.parse('1.500000').micros, 1500000);
      expect(QuantityCodec.parse('  2.25  ').micros, 2250000);
      expect(QuantityCodec.parse('0.1').micros, 100000);
      expect(QuantityCodec.parse('123456789.654321').micros, 123456789654321);
    });

    test('rejects malformed input with FormatException', () {
      const bad = [
        '',
        ' ',
        '-1',
        '+1',
        '1.2.3',
        '1..2',
        'abc',
        '1e5',
        '1.',
        ',',
        '.',
        '1.1234567', // 7 fraction digits
        '1 5',
        '1.5 kg',
        'NaN',
        'Infinity',
      ];
      for (final input in bad) {
        expect(
          () => QuantityCodec.parse(input),
          throwsFormatException,
          reason: 'input: "$input"',
        );
      }
    });

    test('simple and mixed fractions parse with exact integer math', () {
      expect(QuantityCodec.parse('1/2').micros, 500000);
      expect(QuantityCodec.parse('3/4').micros, 750000);
      expect(QuantityCodec.parse('1 1/2').micros, 1500000);
      expect(QuantityCodec.parse('2 3/4').micros, 2750000);
      expect(QuantityCodec.parse('  1 1/2  ').micros, 1500000);
      expect(QuantityCodec.parse('1  1/2').micros, 1500000);
      expect(QuantityCodec.parse('5/4').micros, 1250000, reason: 'improper');
      expect(QuantityCodec.parse('0/7').micros, 0);
      expect(QuantityCodec.parse('10/5').micros, 2000000);
      expect(QuantityCodec.parse('1/1000000').micros, 1);
    });

    test('PINNED: non-terminating fractions TRUNCATE at the sixth place — '
        '1/3 → 333333 and 2/3 → 666666, never rounded up', () {
      // numerator × 1e6 ~/ denominator, documented in QuantityCodec.parse.
      expect(QuantityCodec.parse('1/3').micros, 333333);
      expect(QuantityCodec.parse('2/3').micros, 666666);
      expect(QuantityCodec.parse('1 1/3').micros, 1333333);
      expect(QuantityCodec.parse('1/7').micros, 142857);
      expect(QuantityCodec.parse('1/1000001').micros, 0);
    });

    test('malformed fractions throw FormatException', () {
      const bad = [
        '1/0', // zero denominator
        '0/0',
        '1 1/0',
        '-1/2', // negatives never parse
        '1/-2',
        '1/', // missing part
        '/2',
        '1 /2', // space inside the fraction
        '1/ 2',
        '1 1 1/2', // two whole parts
        '1.5/2', // decimals inside a fraction
        '1/2.5',
        '1 5', // space but no slash: still rejected
        '1/2/3',
      ];
      for (final input in bad) {
        expect(
          () => QuantityCodec.parse(input),
          throwsFormatException,
          reason: 'input: "$input"',
        );
      }
    });

    test('fractions above the cap throw QuantityOverflowError', () {
      expect(
        () => QuantityCodec.parse('1000000001/1'),
        throwsA(isA<QuantityOverflowError>()),
      );
      expect(
        () => QuantityCodec.parse('1000000000 1/2'),
        throwsA(isA<QuantityOverflowError>()),
      );
      expect(
        () => QuantityCodec.parse('2000000001/2'),
        throwsA(isA<QuantityOverflowError>()),
        reason: 'the QUOTIENT is over the cap',
      );
      // Exactly at the cap is fine — including via a huge numerator whose
      // intermediate product only BigInt keeps exact.
      expect(QuantityCodec.parse('1000000000/1').micros, Quantity.maxMicros);
      expect(QuantityCodec.parse('2000000000/2').micros, Quantity.maxMicros);
    });

    test('property: n/d equals n×1e6 ~/ d for seeded random fractions, '
        'both directions of the mixed form', () {
      final rng = Random(20260815);
      for (var i = 0; i < 2000; i++) {
        final numerator = rng.nextInt(1000000);
        final denominator = 1 + rng.nextInt(999999);
        final whole = rng.nextInt(1000);
        final expected = numerator * 1000000 ~/ denominator;
        expect(
          QuantityCodec.parse('$numerator/$denominator').micros,
          expected,
          reason: '$numerator/$denominator',
        );
        expect(
          QuantityCodec.parse('$whole $numerator/$denominator').micros,
          whole * 1000000 + expected,
          reason: '$whole $numerator/$denominator',
        );
      }
    });

    test('property: format(parse(fraction)) reparses to the same micros — '
        'display stays trimmed decimals, never fractions', () {
      final rng = Random(20260816);
      for (var i = 0; i < 500; i++) {
        final numerator = 1 + rng.nextInt(99);
        final denominator = 1 + rng.nextInt(99);
        final parsed = QuantityCodec.parse('$numerator/$denominator');
        final formatted = QuantityCodec.format(parsed);
        expect(formatted, isNot(contains('/')));
        expect(QuantityCodec.parse(formatted), parsed);
      }
    });

    test('cap boundary: 1e9 whole units is exactly maxMicros', () {
      expect(QuantityCodec.parse('1000000000').micros, Quantity.maxMicros);
      expect(QuantityCodec.parse('1000000000.0').micros, Quantity.maxMicros);
    });

    test('anything above the cap throws QuantityOverflowError', () {
      const over = [
        '1000000001',
        '1000000000.000001',
        '99999999999999999999', // 20 digits: guarded before int.parse
        '9223372036854775807',
      ];
      for (final input in over) {
        expect(
          () => QuantityCodec.parse(input),
          throwsA(isA<QuantityOverflowError>()),
          reason: 'input: "$input"',
        );
      }
    });
  });

  group('format', () {
    test('minimal decimal string, no trailing zeros', () {
      expect(QuantityCodec.format(Quantity.fromMicros(1500000)), '1.5');
      expect(QuantityCodec.format(Quantity.fromMicros(12000000)), '12');
      expect(QuantityCodec.format(Quantity.fromMicros(1)), '0.000001');
      expect(QuantityCodec.format(Quantity.zero), '0');
      expect(QuantityCodec.format(Quantity.fromMicros(1230000)), '1.23');
      expect(QuantityCodec.format(Quantity.fromMicros(100000)), '0.1');
      expect(
        QuantityCodec.format(Quantity.fromMicros(Quantity.maxMicros)),
        '1000000000',
      );
    });
  });

  group('formatDisplay', () {
    // Regression (design review): the forecast cards printed the engine's
    // raw micros — "Expected 14.272728", "Planned 15.700001" — because the
    // display path reused the exact round-trip [QuantityCodec.format].
    // These are counted goods; one decimal is the last digit that means
    // anything, and the rest is arithmetic residue.
    test('caps a computed quantity at one decimal, half-up', () {
      Quantity q(int micros) => Quantity.fromMicros(micros);
      expect(QuantityCodec.formatDisplay(q(14272728)), '14.3');
      expect(QuantityCodec.formatDisplay(q(15700001)), '15.7');
      expect(QuantityCodec.formatDisplay(q(5227273)), '5.2');
      expect(QuantityCodec.formatDisplay(q(41800000)), '41.8');
      expect(QuantityCodec.formatDisplay(q(16000000)), '16');
      expect(QuantityCodec.formatDisplay(q(500000)), '0.5');
      expect(QuantityCodec.formatDisplay(Quantity.zero), '0');
      // Half-up, on exact integers — never float rounding.
      expect(QuantityCodec.formatDisplay(q(1050000)), '1.1');
      expect(QuantityCodec.formatDisplay(q(1049999)), '1');
      expect(QuantityCodec.formatDisplay(q(950000)), '1');
      // A number too small to survive the cap rounds to zero, honestly.
      expect(QuantityCodec.formatDisplay(q(1)), '0');
    });

    test('never leaves more than the requested fraction digits', () {
      final rng = Random(20260817);
      for (var i = 0; i < 2000; i++) {
        final micros = rng.nextInt(1 << 32);
        for (final digits in [0, 1, 2, 3]) {
          final text = QuantityCodec.formatDisplay(
            Quantity.fromMicros(micros),
            maxFractionDigits: digits,
          );
          final point = text.indexOf('.');
          if (point < 0) continue;
          expect(
            text.length - point - 1,
            lessThanOrEqualTo(digits),
            reason: '$micros micros at $digits digits rendered "$text"',
          );
          expect(text.endsWith('0'), isFalse, reason: 'trailing zero in $text');
        }
      }
    });

    test('a rate keeps the digits a count does not need', () {
      // 0.01 per person is a real rate; the tenth-place cap would say "0".
      expect(
        QuantityCodec.formatDisplay(
          Quantity.fromMicros(10000),
          maxFractionDigits: 2,
        ),
        '0.01',
      );
      expect(QuantityCodec.formatDisplay(Quantity.fromMicros(10000)), '0');
    });

    test('six digits is the identity — display never adds precision', () {
      for (final micros in [0, 1, 999999, 1000001, 1500000, 123456789]) {
        final q = Quantity.fromMicros(micros);
        expect(
          QuantityCodec.formatDisplay(q, maxFractionDigits: 6),
          QuantityCodec.format(q),
        );
      }
      expect(
        () => QuantityCodec.formatDisplay(Quantity.zero, maxFractionDigits: 7),
        throwsArgumentError,
      );
    });
  });

  group('round trips', () {
    test('pinned values round-trip exactly', () {
      const values = [0, 1, 9, 999999, 1000000, 1000001, 1500000, 123456789];
      for (final micros in values) {
        final q = Quantity.fromMicros(micros);
        expect(QuantityCodec.parse(QuantityCodec.format(q)), q);
      }
      final cap = Quantity.fromMicros(Quantity.maxMicros);
      expect(QuantityCodec.parse(QuantityCodec.format(cap)), cap);
    });

    test('seeded random micros round-trip exactly', () {
      final rng = Random(20260811);
      for (var i = 0; i < 2000; i++) {
        final micros =
            (rng.nextInt(1 << 30) << 20) ^ rng.nextInt(1 << 20); // < 2^50
        final q = Quantity.fromMicros(micros % (Quantity.maxMicros + 1));
        expect(QuantityCodec.parse(QuantityCodec.format(q)), q);
      }
    });
  });
}
