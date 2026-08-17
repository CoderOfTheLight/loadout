import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/money_codec.dart';

void main() {
  group('parse', () {
    test('exact dollar splitting to cents', () {
      expect(MoneyCodec.parse('12').cents, 1200);
      expect(MoneyCodec.parse('12.5').cents, 1250);
      expect(MoneyCodec.parse('12.50').cents, 1250);
      expect(MoneyCodec.parse('\$12.50').cents, 1250);
      expect(MoneyCodec.parse('1,234.56').cents, 123456);
      expect(MoneyCodec.parse('\$1,234.56').cents, 123456);
      expect(MoneyCodec.parse('0.01').cents, 1);
      expect(MoneyCodec.parse('.5').cents, 50);
      expect(MoneyCodec.parse('0').cents, 0);
      expect(MoneyCodec.parse('007').cents, 700);
      expect(MoneyCodec.parse('  2.25  ').cents, 225);
      expect(MoneyCodec.parse('1,000,000').cents, 100000000);
      expect(MoneyCodec.parse('\$1,000,000').cents, 100000000);
      expect(MoneyCodec.parse('0.1').cents, 10);
    });

    test('rejects malformed input with FormatException', () {
      const bad = [
        '',
        ' ',
        '\$',
        '-1',
        '\$-1',
        '-\$1',
        '+1',
        '12.505', // three fraction digits
        '1.2.3',
        '1..2',
        'abc',
        '1e5',
        '12.',
        ',',
        '.',
        '1,5', // comma is a THOUSANDS separator here, never a decimal one
        '12,34', // group after a comma must be exactly three digits
        '1234,567', // first group must be 1-3 digits when commas appear
        '1,23,45',
        '1 5',
        '12.50 each',
        '\$ 12', // no whitespace inside the amount
        'NaN',
        'Infinity',
      ];
      for (final input in bad) {
        expect(
          () => MoneyCodec.parse(input),
          throwsFormatException,
          reason: 'input: "$input"',
        );
      }
    });

    test('amounts whose whole part exceeds 16 digits throw before int64 '
        'could wrap', () {
      expect(
        () => MoneyCodec.parse('99999999999999999'),
        throwsFormatException,
      );
      // 16 digits is still parsed exactly.
      expect(MoneyCodec.parse('9999999999999999').cents, 999999999999999900);
    });

    test('tryParse answers malformed input with null, never throws', () {
      expect(MoneyCodec.tryParse('12.50'), Money.fromCents(1250));
      expect(MoneyCodec.tryParse(''), isNull);
      expect(MoneyCodec.tryParse('-1'), isNull);
      expect(MoneyCodec.tryParse('garbage'), isNull);
      expect(MoneyCodec.tryParse('12.505'), isNull);
      expect(MoneyCodec.tryParse('99999999999999999'), isNull);
    });
  });

  group('format', () {
    test('whole dollars drop the cents, everything else shows two', () {
      expect(MoneyCodec.format(Money.fromCents(1200)), '\$12');
      expect(MoneyCodec.format(Money.fromCents(1250)), '\$12.50');
      expect(MoneyCodec.format(Money.fromCents(1255)), '\$12.55');
      expect(MoneyCodec.format(Money.fromCents(5)), '\$0.05');
      expect(MoneyCodec.format(Money.fromCents(50)), '\$0.50');
      expect(MoneyCodec.format(Money.zero), '\$0');
      expect(MoneyCodec.format(Money.fromCents(1)), '\$0.01');
    });

    test('thousands separators from \$1,000 up', () {
      expect(MoneyCodec.format(Money.fromCents(99999)), '\$999.99');
      expect(MoneyCodec.format(Money.fromCents(100000)), '\$1,000');
      expect(MoneyCodec.format(Money.fromCents(123456)), '\$1,234.56');
      expect(MoneyCodec.format(Money.fromCents(100000000)), '\$1,000,000');
      expect(MoneyCodec.format(Money.fromCents(123456789)), '\$1,234,567.89');
    });
  });

  group('round trips', () {
    test('pinned values round-trip exactly', () {
      const values = [0, 1, 99, 100, 101, 1250, 99999, 100000, 100000000];
      for (final cents in values) {
        final m = Money.fromCents(cents);
        expect(
          MoneyCodec.parse(MoneyCodec.format(m)),
          m,
          reason: 'cents: $cents',
        );
      }
    });

    test('seeded random cents round-trip exactly', () {
      final rng = Random(20260816);
      for (var i = 0; i < 2000; i++) {
        final m = Money.fromCents(rng.nextInt(1 << 30));
        expect(MoneyCodec.parse(MoneyCodec.format(m)), m);
      }
    });
  });
}
