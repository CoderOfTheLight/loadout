import 'errors.dart';
import 'quantity.dart';

/// Exact decimal-and-fraction string codec for [Quantity] (design §9.1): the
/// string is split and parsed with integer arithmetic only — `double` never
/// appears. `.` and `,` are both accepted as the decimal separator; at most
/// [maxFractionDigits] fraction digits. Simple fractions (`"1/2"`) and mixed
/// numbers (`"1 1/2"`) are accepted too — see [parse].
final class QuantityCodec {
  const QuantityCodec._();

  static const int maxFractionDigits = 6;

  /// Digits, optionally one `.` or `,` followed by 1+ fraction digits.
  /// `"1.5"`, `"1,5"`, `".5"`, `"12"` match; `"1."`, `"-1"`, `"1e5"` do not.
  static final RegExp _pattern = RegExp(r'^([0-9]*)(?:[.,]([0-9]+))?$');

  /// Simple or mixed vulgar fraction: `"1/2"`, `"3/4"`, `"1 1/2"` — an
  /// optional whole part (space-separated), then numerator `/` denominator,
  /// all plain digit runs. Signs, decimals inside a fraction, and a missing
  /// part never match; `"1 5"` (space, no slash) stays rejected.
  static final RegExp _fractionPattern = RegExp(
    r'^(?:([0-9]+)[ ]+)?([0-9]+)/([0-9]+)$',
  );

  static const int _maxWhole = Quantity.maxMicros ~/ Quantity.scale;

  /// Parses a decimal or fraction string to exact micros: `"1.5"` →
  /// 1_500_000, `"1/2"` → 500_000, `"1 1/2"` → 1_500_000.
  /// Throws [FormatException] on malformed input (including a zero
  /// denominator) and [QuantityOverflowError] above `Quantity.maxMicros`.
  ///
  /// Fractions use exact integer math — `numerator * 1e6 ~/ denominator` —
  /// so a non-terminating fraction TRUNCATES at the sixth decimal place:
  /// `1/3` → 333_333 micros and `2/3` → 666_666 micros (not …667). The
  /// error is under one millionth of a unit, always toward zero, and
  /// documented here on purpose: exact integer arithmetic, never rounding
  /// half-up, is the codec's contract.
  static Quantity parse(String input) {
    final text = input.trim();
    if (_fractionPattern.firstMatch(text) case final fraction?) {
      return _parseFraction(text, fraction);
    }
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

  /// Exact fraction arithmetic over [BigInt] so no digit-length guard is
  /// needed before the multiply: `whole × 1e6 + numerator × 1e6 ~/
  /// denominator`, truncating (see [parse] for the documented 1/3 → 333333
  /// contract), then one cap check.
  static Quantity _parseFraction(String text, RegExpMatch match) {
    final denominator = BigInt.parse(match.group(3)!);
    if (denominator == BigInt.zero) {
      throw FormatException('fraction denominator must not be zero', text);
    }
    final whole = switch (match.group(1)) {
      final digits? => BigInt.parse(digits),
      null => BigInt.zero,
    };
    final numerator = BigInt.parse(match.group(2)!);
    final scale = BigInt.from(Quantity.scale);
    final micros = whole * scale + (numerator * scale) ~/ denominator;
    if (micros > BigInt.from(Quantity.maxMicros)) {
      throw QuantityOverflowError('"$text" exceeds maxMicros');
    }
    return Quantity.fromMicros(micros.toInt());
  }

  /// Formats micros back to a minimal decimal string with `.` as separator
  /// and no trailing fraction zeros: 1_500_000 → `"1.5"`, 12_000_000 → `"12"`.
  /// Integer arithmetic only; `parse(format(q)) == q` for every quantity.
  ///
  /// This is the ROUND-TRIP form: exact to the last micro, so a form field
  /// pre-filled with it and saved unchanged stores the same number. It is
  /// NOT for read-only display of a COMPUTED quantity — a median times an
  /// attendance times a reserve lands on values like 14.272728, and six
  /// decimals of engine noise on a screen that counts trays is not a number
  /// anyone can act on. Use [formatDisplay] there.
  static String format(Quantity value) => _decimal(value.micros);

  /// Display-only rounding (never storage): the same minimal decimal shape
  /// as [format], but rounded half-up to at most [maxFractionDigits] and
  /// with trailing fraction zeros dropped — `14.272728` → `"14.3"`,
  /// `16` → `"16"`, `0.5` → `"0.5"`, `41.8` → `"41.8"`.
  ///
  /// One decimal is the default because Loadout's quantities are COUNTED
  /// goods (trays, bags, platters): the tenth is the last digit that still
  /// means something at a serving table, and everything after it is an
  /// artifact of how the number was derived. Integer arithmetic only —
  /// `double` never appears, so this is exact rounding, not float rounding.
  ///
  /// Callers that show a RATE rather than a count (a per-person figure like
  /// `0.01 per person`, which a tenth would flatten to zero) pass a larger
  /// [maxFractionDigits]; nothing else should.
  static String formatDisplay(Quantity value, {int maxFractionDigits = 1}) =>
      formatDisplayMicros(value.micros, maxFractionDigits: maxFractionDigits);

  /// [formatDisplay] over raw nonnegative micros, for the display helpers
  /// that carry the sign themselves.
  static String formatDisplayMicros(int micros, {int maxFractionDigits = 1}) {
    const limit = QuantityCodec.maxFractionDigits;
    if (maxFractionDigits < 0 || maxFractionDigits > limit) {
      throw ArgumentError.value(
        maxFractionDigits,
        'maxFractionDigits',
        'must be between 0 and $limit',
      );
    }
    // 10^(6 - maxFractionDigits) — the micros step the value snaps to.
    var step = 1;
    for (var i = maxFractionDigits; i < limit; i++) {
      step *= 10;
    }
    // Half-up on exact integers: no double ever enters the arithmetic.
    return _decimal(((micros + step ~/ 2) ~/ step) * step);
  }

  /// Minimal decimal shape for exact micros: whole part, then the fraction
  /// digits with trailing zeros trimmed, or no point at all.
  static String _decimal(int micros) {
    final whole = micros ~/ Quantity.scale;
    final fraction = micros % Quantity.scale;
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
