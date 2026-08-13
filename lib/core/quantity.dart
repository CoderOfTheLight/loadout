import 'errors.dart';

/// Exact nonnegative fixed-point quantity. One unit is one million micros.
final class Quantity implements Comparable<Quantity> {
  const Quantity._(this.micros);

  factory Quantity.fromMicros(int micros) {
    if (micros < 0) {
      throw ArgumentError.value(micros, 'micros', 'must be nonnegative');
    }
    if (micros > maxMicros) {
      throw QuantityOverflowError('$micros micros exceeds maxMicros');
    }
    return Quantity._(micros);
  }

  factory Quantity.whole(int value) => Quantity.fromMicros(value * scale);

  static const int scale = 1000000;

  /// Hard magnitude cap for every stored quantity (design §3): 1e15 micros —
  /// generous, and small enough that the frozen engine's `multiplyRatio` with
  /// reserve numerators cannot wrap int64.
  static const int maxMicros = 1000000000000000;

  static const zero = Quantity._(0);

  /// Exactly one whole unit. The pack size every item gets now that packs
  /// are off the product surface: rounding up to 1 means "round to whole
  /// things", which is what counted goods want.
  static const one = Quantity._(scale);
  final int micros;

  /// Checked add: throws [QuantityOverflowError] above [maxMicros].
  Quantity plus(Quantity other) => Quantity.fromMicros(micros + other.micros);

  Quantity multiplyRatio(int numerator, int denominator) {
    if (numerator < 0 || denominator <= 0) {
      throw ArgumentError('invalid ratio');
    }
    return Quantity.fromMicros(
      (micros * numerator + denominator - 1) ~/ denominator,
    );
  }

  Quantity roundUpTo(Quantity increment) {
    if (increment.micros == 0) {
      throw ArgumentError('increment must be positive');
    }
    return Quantity.fromMicros(
      ((micros + increment.micros - 1) ~/ increment.micros) * increment.micros,
    );
  }

  Quantity subtractFloor(Quantity other) =>
      micros <= other.micros ? zero : Quantity._(micros - other.micros);

  @override
  int compareTo(Quantity other) => micros.compareTo(other.micros);
  @override
  bool operator ==(Object other) => other is Quantity && other.micros == micros;
  @override
  int get hashCode => micros.hashCode;
}
