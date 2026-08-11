import 'errors.dart';
import 'quantity.dart';

/// Exact positive integer ratio, gcd-normalized on construction (design §6.1).
/// Ratios are always integer pairs; no floating point exists on this path.
final class UnitRatio {
  factory UnitRatio(int numerator, int denominator) {
    if (numerator <= 0 || denominator <= 0) {
      throw ArgumentError(
        'UnitRatio requires positive numerator and denominator '
        '(got $numerator/$denominator)',
      );
    }
    final g = _gcd(numerator, denominator);
    return UnitRatio._(numerator ~/ g, denominator ~/ g);
  }

  const UnitRatio._(this.numerator, this.denominator);

  final int numerator;
  final int denominator;

  /// `ceil(value * numerator / denominator)`, computed via BigInt so the
  /// intermediate product can never wrap int64. Throws
  /// [QuantityOverflowError] when the exact result exceeds
  /// [Quantity.maxMicros]. Matches `Quantity.multiplyRatio` wherever that
  /// legacy path stays in int64 range.
  Quantity applyCeil(Quantity value) {
    final product = BigInt.from(value.micros) * BigInt.from(numerator);
    final divisor = BigInt.from(denominator);
    final result = (product + divisor - BigInt.one) ~/ divisor;
    if (result > BigInt.from(Quantity.maxMicros)) {
      throw QuantityOverflowError(
        'applyCeil(${value.micros} × $numerator/$denominator) '
        'exceeds maxMicros',
      );
    }
    return Quantity.fromMicros(result.toInt());
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    return a;
  }

  @override
  bool operator ==(Object other) =>
      other is UnitRatio &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => 'UnitRatio($numerator/$denominator)';
}
