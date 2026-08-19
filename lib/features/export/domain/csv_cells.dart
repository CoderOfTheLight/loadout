/// How a stored value becomes a spreadsheet cell — pure Dart, integer
/// arithmetic only, `double` never appears.
///
/// The app stores money in integer CENTS and quantities in MICROS. Neither
/// belongs in a file a treasurer opens, so nothing here ever emits a raw
/// micro or a raw cent: money leaves as a plain decimal with exactly two
/// places and NO currency symbol (`12.50`), quantities as a minimal decimal
/// (`3`, `1.5`). Both are numbers Excel will sum; a `$` would make them text.
///
/// Null in, null out, everywhere: an unknown value is an EMPTY cell, never a
/// zero. A zero means "none", and "none" and "never said" are different
/// answers.
library;

/// Micros in one whole unit — the app's fixed-point scale.
const int _microsPerUnit = 1000000;

/// Cents in one dollar.
const int _centsPerDollar = 100;

/// Money as a plain two-place decimal: 1250 -> `12.50`, -1250 -> `-12.50`,
/// 5 -> `0.05`. No symbol, no thousands separators — Excel wants a number.
String? csvMoney(int? cents) {
  if (cents == null) return null;
  final negative = cents < 0;
  final magnitude = cents.abs();
  final whole = magnitude ~/ _centsPerDollar;
  final fraction = magnitude % _centsPerDollar;
  final sign = negative ? '-' : '';
  return '$sign$whole.${fraction.toString().padLeft(2, '0')}';
}

/// A quantity as a minimal decimal: 3_000_000 -> `3`, 1_500_000 -> `1.5`,
/// -500_000 -> `-0.5`. Trailing fraction zeros are dropped; the value is
/// exact to the micro, never rounded.
String? csvQuantity(int? micros) {
  if (micros == null) return null;
  final negative = micros < 0;
  final magnitude = micros.abs();
  final whole = magnitude ~/ _microsPerUnit;
  final fraction = magnitude % _microsPerUnit;
  final sign = negative ? '-' : '';
  if (fraction == 0) return '$sign$whole';
  var digits = fraction.toString().padLeft(6, '0');
  while (digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
  }
  return '$sign$whole.$digits';
}

/// A plain integer cell (attendance, revision number, counts).
String? csvInteger(int? value) => value?.toString();

/// A yes/no answer in the words a spreadsheet reader expects.
String csvYesNo(bool value) => value ? 'Yes' : 'No';

/// `YYYY-MM-DD` for a local calendar date — the one date shape Excel parses
/// the same way in every locale.
String csvDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// `unitPriceCents × quantityMicros`, in cents, truncated toward zero.
///
/// Over [BigInt] so the intermediate product cannot wrap int64 (the same
/// guard `Money.timesQuantityMicros` uses), and sign-tolerant so a negative
/// on-hand — which the ledger genuinely allows — still costs out.
int lineCents({required int unitPriceCents, required int quantityMicros}) {
  final product = BigInt.from(unitPriceCents) * BigInt.from(quantityMicros);
  return (product ~/ BigInt.from(_microsPerUnit)).toInt();
}
