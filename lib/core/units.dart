/// The closed unit list (design §3, §12.5): one unit per item, no custom
/// units, no conversions. [dbValue] is the exact string stored in `items.unit`
/// and enforced there by SQL CHECK; SQL stays authoritative independently of
/// this enum.
enum ItemUnit {
  each('each', 'each'),
  g('g', 'grams'),
  kg('kg', 'kilograms'),
  ml('ml', 'millilitres'),
  litre('L', 'litres');

  const ItemUnit(this.dbValue, this.label);

  /// Stored/CHECK-enforced database value.
  final String dbValue;

  /// Human-readable display label.
  final String label;

  static ItemUnit fromDb(String value) => values.firstWhere(
    (unit) => unit.dbValue == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'not a known unit'),
  );
}
