/// RFC 4180 CSV, written Excel-first — pure Dart, no Flutter, no I/O.
///
/// The reader this exists for opens files in Excel and nothing else, so the
/// three decisions that usually go wrong are made here, once:
///
///  * **UTF-8 BOM.** Excel on Windows reads a BOM-less file as the local
///    ANSI code page, which turns "Crème fraîche" into mojibake. Every
///    document produced by [encodeCsv] starts with [csvByteOrderMark]; the
///    caller writes the string as UTF-8 and the bytes land as EF BB BF.
///  * **CRLF line endings** ([csvLineTerminator]) — what RFC 4180 specifies
///    and what Excel's own exporter writes.
///  * **Formula injection.** A cell whose first character is `=`, `+`, `-`
///    or `@` is a formula to a spreadsheet. An item legitimately named
///    "-- leftovers" must be text, so such a cell is prefixed with an
///    apostrophe. Plain numbers are the documented exception: `-12.50` is a
///    negative amount, not an attack, and prefixing it would make Excel
///    treat the column as text. [looksLikePlainNumber] draws that line —
///    only a bare optionally-negative decimal escapes the guard, so
///    `-1+cmd|'/c calc'!A0` is still neutralised.
///
/// Quoting is plain RFC 4180: a field containing a comma, a double quote,
/// CR or LF is wrapped in double quotes with internal quotes doubled;
/// nothing else is quoted.
library;

/// The UTF-8 BOM, as a Dart character. Encoded to UTF-8 it is EF BB BF.
const String csvByteOrderMark = '\u{FEFF}';

/// RFC 4180's line terminator, and Excel's.
const String csvLineTerminator = '\r\n';

/// Characters that make a spreadsheet treat a cell as a formula.
const Set<String> csvFormulaLeaders = {'=', '+', '-', '@'};

/// A bare decimal number, optionally negative: the one shape allowed to
/// begin with `-` without being escaped as text.
final RegExp _plainNumber = RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$');

/// True when [value] is a bare decimal number (`12`, `12.50`, `-0.5`).
bool looksLikePlainNumber(String value) => _plainNumber.hasMatch(value);

/// One complete CSV document: BOM, then every row terminated by CRLF —
/// including the last, so appending is never ambiguous.
///
/// A null cell is an EMPTY cell. That is the honesty rule of this feature:
/// unknown is blank, never a zero standing in for "no price".
String encodeCsv(List<List<String?>> rows) {
  final buffer = StringBuffer(csvByteOrderMark);
  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(encodeCsvField(row[i]));
    }
    buffer.write(csvLineTerminator);
  }
  return buffer.toString();
}

/// One field: injection guard first, then RFC 4180 quoting.
String encodeCsvField(String? value) {
  if (value == null || value.isEmpty) return '';
  final guarded = _guardFormula(value);
  final needsQuotes =
      guarded.contains(',') ||
      guarded.contains('"') ||
      guarded.contains('\r') ||
      guarded.contains('\n');
  if (!needsQuotes) return guarded;
  return '"${guarded.replaceAll('"', '""')}"';
}

/// Prefixes an apostrophe when the cell would otherwise read as a formula.
/// Numbers pass through untouched — see the library comment.
String _guardFormula(String value) {
  if (!csvFormulaLeaders.contains(value[0])) return value;
  if (looksLikePlainNumber(value)) return value;
  return "'$value";
}
