import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/units.dart';

void main() {
  test('the unit list is closed and matches the SQL CHECK values', () {
    expect(ItemUnit.values.map((u) => u.dbValue), [
      'each',
      'g',
      'kg',
      'ml',
      'L',
    ]);
  });

  test('every unit carries a human label', () {
    expect(ItemUnit.each.label, 'each');
    expect(ItemUnit.g.label, 'grams');
    expect(ItemUnit.kg.label, 'kilograms');
    expect(ItemUnit.ml.label, 'millilitres');
    expect(ItemUnit.litre.label, 'litres');
  });

  test('fromDb round-trips every unit', () {
    for (final unit in ItemUnit.values) {
      expect(ItemUnit.fromDb(unit.dbValue), unit);
    }
  });

  test('fromDb rejects unknown values', () {
    expect(() => ItemUnit.fromDb('lb'), throwsArgumentError);
    expect(() => ItemUnit.fromDb('EACH'), throwsArgumentError);
    expect(() => ItemUnit.fromDb('l'), throwsArgumentError);
    expect(() => ItemUnit.fromDb(''), throwsArgumentError);
  });
}
