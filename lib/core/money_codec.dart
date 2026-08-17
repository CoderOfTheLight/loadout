import 'money.dart';

/// Exact dollars-and-cents string codec for [Money] (v7 price design): the
/// string is split and parsed with integer arithmetic only — `double` never
/// appears. An optional leading `$`, optional comma-thousands in the whole
/// part, and at most [maxFractionDigits] fraction digits after `.`.
///
/// Unlike QuantityCodec, a comma here is a THOUSANDS separator, never a
/// decimal one: `"1,234.56"` parses, `"1,5"` is rejected (a group after a
/// comma must be exactly three digits). Negative amounts never parse.
final class MoneyCodec {
  const MoneyCodec._();

  static const int maxFractionDigits = 2;

  /// Optional `$`, then either comma-grouped digits (first group 1-3, every
  /// later group exactly 3) or a plain digit run, then optionally `.` and
  /// 1-2 fraction digits. `"12"`, `"12.5"`, `"$12.50"`, `"1,234.56"`,
  /// `".5"` match; `"-1"`, `"12.505"`, `"1,5"`, `"12."`, `"$"` do not.
  static final RegExp _pattern = RegExp(
    r'^\$?(?:([0-9]{1,3}(?:,[0-9]{3})+)|([0-9]*))(?:\.([0-9]{1,2}))?$',
  );

  /// Parses a dollar amount to exact cents: `"12"` → 1200, `"12.5"` → 1250,
  /// `"$12.50"` → 1250, `"1,234.56"` → 123456. Throws [FormatException] on
  /// malformed input — negatives, more than two fraction digits, misplaced
  /// commas, garbage — and on amounts whose whole part exceeds 16 digits
  /// (guarding int64 long before the real product cap, which is the
  /// validator's and the CHECK's to enforce).
  static Money parse(String input) {
    final text = input.trim();
    final match = _pattern.firstMatch(text);
    if (match == null) {
      throw FormatException('not a dollar amount', input);
    }
    final wholeDigits = (match.group(1) ?? match.group(2) ?? '').replaceAll(
      ',',
      '',
    );
    final fractionDigits = match.group(3) ?? '';
    if (wholeDigits.isEmpty && fractionDigits.isEmpty) {
      throw FormatException('not a dollar amount', input);
    }
    final significant = wholeDigits.replaceFirst(RegExp('^0+'), '');
    if (significant.length > 16) {
      // Guard int.parse and the ×100 before they could exceed int64.
      throw FormatException('amount too large', input);
    }
    final whole = significant.isEmpty ? 0 : int.parse(significant);
    final fraction = fractionDigits.isEmpty
        ? 0
        : int.parse(fractionDigits.padRight(maxFractionDigits, '0'));
    return Money.fromCents(whole * Money.centsPerDollar + fraction);
  }

  /// [parse] that answers malformed input with null instead of throwing —
  /// the form-field-friendly variant.
  static Money? tryParse(String input) {
    try {
      return parse(input);
    } on FormatException {
      return null;
    }
  }

  /// Formats cents back to a display string: whole dollars drop the cents
  /// (`1200` → `"$12"`), anything else always shows two (`1250` → `"$12.50"`,
  /// `5` → `"$0.05"`), and amounts of $1,000 and up group the whole part
  /// with commas (`123456789` → `"$1,234,567.89"`). Integer arithmetic only;
  /// `parse(format(m)) == m` for every amount.
  static String format(Money value) {
    final whole = value.cents ~/ Money.centsPerDollar;
    final fraction = value.cents % Money.centsPerDollar;
    final grouped = _groupThousands('$whole');
    if (fraction == 0) {
      return '\$$grouped';
    }
    return '\$$grouped.${fraction.toString().padLeft(maxFractionDigits, '0')}';
  }

  static String _groupThousands(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      if (i > 0 && remaining % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
