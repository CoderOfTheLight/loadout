/// The one effective-basis rule (v3): item override, else folder, else
/// per_person — the pre-folders behaviour. Everyone calls
/// [effectiveDemandBasis]; nothing re-derives it, so this file pins the
/// whole rule.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';

void main() {
  test('unfiled, no override → per_person, exactly as before folders', () {
    expect(effectiveDemandBasis(), DemandBasis.perPerson);
  });

  test('the folder answers for its items', () {
    expect(
      effectiveDemandBasis(folderBasis: DemandBasis.perEvent),
      DemandBasis.perEvent,
    );
    expect(
      effectiveDemandBasis(folderBasis: DemandBasis.perPerson),
      DemandBasis.perPerson,
    );
  });

  test('a per-item override beats the folder, both ways', () {
    expect(
      effectiveDemandBasis(
        itemOverride: DemandBasis.perEvent,
        folderBasis: DemandBasis.perPerson,
      ),
      DemandBasis.perEvent,
    );
    expect(
      effectiveDemandBasis(
        itemOverride: DemandBasis.perPerson,
        folderBasis: DemandBasis.perEvent,
      ),
      DemandBasis.perPerson,
    );
  });

  test('an override on an unfiled item still counts', () {
    expect(
      effectiveDemandBasis(itemOverride: DemandBasis.perEvent),
      DemandBasis.perEvent,
    );
  });

  test('db string round-trip is total and rejects strangers', () {
    for (final basis in DemandBasis.values) {
      expect(DemandBasis.fromDb(basis.dbValue), basis);
    }
    expect(DemandBasis.fromDbNullable(null), isNull);
    expect(() => DemandBasis.fromDb('per_stall'), throwsArgumentError);
  });
}
