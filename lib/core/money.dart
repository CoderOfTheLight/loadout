/// Exact money amount in integer CENTS — `double` never appears (v7 price
/// design). Mirrors [Quantity]'s construction discipline: a checked factory,
/// a private const constructor, and integer arithmetic only.
///
/// Money itself carries NO upper bound on purpose: the 1-cent-to-$1,000,000
/// cap applies to a stored UNIT PRICE (`unitPriceCapCents` in the schema,
/// `maxUnitPriceCents` in the validator), while a legitimate event TOTAL may
/// exceed it. Negative amounts do not exist anywhere in the product, so the
/// factory rejects them as programmer error.
final class Money implements Comparable<Money> {
  const Money._(this.cents);

  factory Money.fromCents(int cents) {
    if (cents < 0) {
      throw ArgumentError.value(cents, 'cents', 'must be nonnegative');
    }
    return Money._(cents);
  }

  static const zero = Money._(0);

  /// Cents in one whole dollar.
  static const int centsPerDollar = 100;

  final int cents;

  /// Checked add (the sum of nonnegative amounts stays in range far below
  /// int64 at every realistic scale; the factory re-asserts nonnegativity).
  Money plus(Money other) => Money.fromCents(cents + other.cents);

  /// Price of [count] whole units at this per-unit price.
  Money times(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must be nonnegative');
    }
    return Money.fromCents(cents * count);
  }

  /// Price of [quantityMicros] millionths of a unit at this per-unit price:
  /// `cents × micros ~/ 1e6` over [BigInt] so the intermediate product can
  /// never wrap int64 (1e8 cents × 1e15 micros needs 77 bits).
  ///
  /// A non-terminating result TRUNCATES at the cent — 1.5 units at $0.03 is
  /// 4 cents, not 5. The error is under one cent, always toward zero, and
  /// documented here on purpose: exact integer arithmetic, never rounding
  /// half-up, is this type's contract (the same one QuantityCodec pins for
  /// 1/3 → 333333).
  Money timesQuantityMicros(int quantityMicros) {
    if (quantityMicros < 0) {
      throw ArgumentError.value(
        quantityMicros,
        'quantityMicros',
        'must be nonnegative',
      );
    }
    final product =
        (BigInt.from(cents) * BigInt.from(quantityMicros)) ~/
        BigInt.from(1000000);
    return Money.fromCents(product.toInt());
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);
  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;
  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money($cents cents)';
}
