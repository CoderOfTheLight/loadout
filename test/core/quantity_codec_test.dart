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
