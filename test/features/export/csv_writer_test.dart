/// The CSV writer's contract: RFC 4180 quoting, the three Excel-specific
/// decisions (BOM, CRLF, formula guard), and the cell formatters that keep
/// money and quantities numbers rather than text.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/export/domain/csv_cells.dart';
import 'package:loadout/features/export/domain/csv_writer.dart';
import 'package:loadout/features/export/domain/spreadsheet_export.dart';

/// The BOM, spelled out so the expectations below read unambiguously.
const String bom = '\u{FEFF}';

void main() {
  group('document shape', () {
    test('starts with a UTF-8 BOM and ends every row with CRLF', () {
      expect(
        encodeCsv([
          ['Item', 'Price each'],
          ['Cups', '2.00'],
        ]),
        '${bom}Item,Price each\r\nCups,2.00\r\n',
      );
    });

    test('the BOM survives UTF-8 encoding as EF BB BF', () {
      final bytes = encodeCsv([
        ['Crème fraîche'],
      ]).codeUnits;
      expect(bytes.first, 0xFEFF); // one code unit, three UTF-8 bytes
      expect(csvByteOrderMark, bom);
    });

    test('an empty document is still a BOM', () {
      expect(encodeCsv(const []), bom);
    });
  });

  group('quoting', () {
    test('plain fields are never quoted', () {
      expect(encodeCsvField('Tortillas'), 'Tortillas');
      expect(encodeCsvField('12.50'), '12.50');
    });

    test('a comma forces quotes', () {
      expect(encodeCsvField('Buns, seeded'), '"Buns, seeded"');
    });

    test('a quote is doubled inside quotes', () {
      expect(encodeCsvField('6" plates'), '"6"" plates"');
      expect(encodeCsvField('"'), '""""');
    });

    test('CR and LF force quotes and stay in the field', () {
      expect(encodeCsvField('two\nlines'), '"two\nlines"');
      expect(encodeCsvField('two\r\nlines'), '"two\r\nlines"');
      expect(encodeCsvField('trailing\r'), '"trailing\r"');
    });

    test('a multi-line cell keeps the row count honest', () {
      expect(
        encodeCsv([
          ['Note'],
          ['first\r\nsecond'],
        ]),
        '${bom}Note\r\n"first\r\nsecond"\r\n',
      );
    });
  });

  group('empty versus zero', () {
    test('null and empty are both an empty cell', () {
      expect(encodeCsvField(null), '');
      expect(encodeCsvField(''), '');
      expect(
        encodeCsv([
          ['a', null, ''],
        ]),
        '${bom}a,,\r\n',
      );
    });

    test('zero is a number, not an empty cell', () {
      expect(csvMoney(0), '0.00');
      expect(csvQuantity(0), '0');
      expect(csvInteger(0), '0');
      expect(csvMoney(null), isNull);
      expect(csvQuantity(null), isNull);
      expect(csvInteger(null), isNull);
    });
  });

  group('formula injection', () {
    test('the four leaders are prefixed with an apostrophe', () {
      expect(encodeCsvField('=1+1'), "'=1+1");
      expect(encodeCsvField('+41 tray'), "'+41 tray");
      expect(encodeCsvField('@import'), "'@import");
      expect(encodeCsvField('-- leftovers'), "'-- leftovers");
    });

    test('a guarded field is still quoted when it needs to be', () {
      expect(encodeCsvField('=SUM(A1,B1)'), '"\'=SUM(A1,B1)"');
    });

    test('plain numbers keep their sign and stay numbers', () {
      expect(encodeCsvField('-12.50'), '-12.50');
      expect(encodeCsvField('-0.5'), '-0.5');
      expect(encodeCsvField('12'), '12');
      expect(looksLikePlainNumber('-12.50'), isTrue);
      expect(looksLikePlainNumber('-1+1'), isFalse);
      expect(looksLikePlainNumber('-'), isFalse);
    });

    test('an expression that merely starts like a number is still text', () {
      expect(encodeCsvField('-1+1'), "'-1+1");
      expect(
        encodeCsvField(r'-2+3+cmd|"/c calc"!A0'),
        '"\'-2+3+cmd|""/c '
        'calc""!A0"',
      );
    });

    test('a leader anywhere but the front is left alone', () {
      expect(encodeCsvField('Cups = 12'), 'Cups = 12');
      expect(encodeCsvField('A-B'), 'A-B');
    });
  });

  group('money', () {
    test('always two places, no symbol, no grouping', () {
      expect(csvMoney(1250), '12.50');
      expect(csvMoney(5), '0.05');
      expect(csvMoney(123456789), '1234567.89');
      expect(csvMoney(-1250), '-12.50');
    });
  });

  group('quantities', () {
    test('minimal decimal, exact to the micro, never micros', () {
      expect(csvQuantity(3000000), '3');
      expect(csvQuantity(1500000), '1.5');
      expect(csvQuantity(333333), '0.333333');
      expect(csvQuantity(-500000), '-0.5');
      expect(csvQuantity(-2000000), '-2');
    });
  });

  group('line cost', () {
    test('cents times micros truncates toward zero, either sign', () {
      expect(lineCents(unitPriceCents: 250, quantityMicros: 3000000), 750);
      expect(lineCents(unitPriceCents: 3, quantityMicros: 1500000), 4);
      expect(lineCents(unitPriceCents: 3, quantityMicros: -1500000), -4);
      expect(lineCents(unitPriceCents: 100, quantityMicros: 0), 0);
    });

    test('a huge line cannot wrap int64', () {
      expect(
        lineCents(unitPriceCents: 100000000, quantityMicros: 1000000000000),
        100000000000000,
      );
    });
  });

  group('dates and file names', () {
    test('dates are YYYY-MM-DD', () {
      expect(csvDate(DateTime(2026, 8, 9)), '2026-08-09');
      expect(csvDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('file names carry what the file is and when', () {
      expect(
        exportFileName(SpreadsheetExport.items, datePart: '2026-08-19'),
        'loadout-items-2026-08-19.csv',
      );
      expect(
        exportFileName(
          SpreadsheetExport.eventCount,
          datePart: '2026-07-04',
          subject: 'Summer Fête!',
        ),
        'loadout-count-summer-f-te-2026-07-04.csv',
      );
    });

    test('a name with nothing safe in it falls back to the plain stem', () {
      expect(
        exportFileName(
          SpreadsheetExport.eventCount,
          datePart: '2026-07-04',
          subject: '???',
        ),
        'loadout-count-2026-07-04.csv',
      );
      expect(fileNameSlug('  Bank Holiday  '), 'bank-holiday');
      expect(fileNameSlug('a' * 60).length, lessThanOrEqualTo(40));
    });
  });
}
