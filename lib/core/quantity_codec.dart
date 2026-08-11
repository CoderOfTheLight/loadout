import 'errors.dart';
import 'quantity.dart';

/// Exact decimal-string codec for [Quantity] (design §9.1): the string is
/// split and parsed with integer arithmetic only — `double` never appears.
/// `.` and `,` are both accepted as the decimal separator; at most
/// [maxFractionDigits] fraction digits.
final class QuantityCodec {
  const QuantityCodec._();

  static const int maxFractionDigits = 6;

  /// Digits, optionally one `.` or `,` followed by 1+ fraction digits.
  /// `"1.5"`, `"1,5"`, `".5"`, `"12"` match; `"1."`, `"-1"`, `"1e5"` do not.
  static final RegExp _pattern = RegExp(r'^([0-9]*)(?:[.,]([0-9]+))?$');

  static const int _maxWhole = Quantity.maxMicros ~/ Quantity.scale;

  /// Parses a decimal string to exact micros: `"1.5"` → 1_500_000.
  /// Throws [FormatException] on malformed input and [QuantityOverflowError]
  /// above `Quantity.maxMicros`.
  static Quantity parse(String input) {
    final text = input.trim();
    final match = _pattern.firstMatch(text);
    if (match == null) {
      throw FormatException('not a decimal quantity', input);
    }
    final wholeDigits = match.group(1)!;
    final fractionDigits = match.group(2) ?? '';
    if (wholeDigits.isEmpty && fractionDigits.isEmpty) {
      throw FormatException('not a decimal quantity', input);
    }
    if (fractionDigits.length > maxFractionDigits) {
      throw FormatException(
        'more than $maxFractionDigits fraction digits',
        input,
      );
    }
    final significant = wholeDigits.replaceFirst(RegExp('^0+'), '');
    if (significant.length > 16) {
      // Guard int.parse before it could exceed int64.
      throw QuantityOverflowError('"$text" exceeds maxMicros');
    }
    final whole = significant.isEmpty ? 0 : int.parse(significant);
    if (whole > _maxWhole) {
      // Guard the multiplication by scale before it could wrap.
      throw QuantityOverflowError('"$text" exceeds maxMicros');
    }
    final fraction = fractionDigits.isEmpty
        ? 0
        : int.parse(fractionDigits.padRight(maxFractionDigits, '0'));
    return Quantity.fromMicros(whole * Quantity.scale + fraction);
  }

  /// Formats micros back to a minimal decimal string with `.` as separator
  /// and no trailing fraction zeros: 1_500_000 → `"1.5"`, 12_000_000 → `"12"`.
  /// Integer arithmetic only; `parse(format(q)) == q` for every quantity.
  static String format(Quantity value) {
    final whole = value.micros ~/ Quantity.scale;
    final fraction = value.micros % Quantity.scale;
    if (fraction == 0) {
      return '$whole';
    }
    var digits = fraction.toString().padLeft(maxFractionDigits, '0');
    while (digits.endsWith('0')) {
      digits = digits.substring(0, digits.length - 1);
    }
    return '$whole.$digits';
  }
}
