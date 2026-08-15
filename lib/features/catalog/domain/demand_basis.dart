/// The one question every item answers: "Does how much you bring depend on
/// how many people come?"
///
/// The folder answers it by default; an item may override; unfiled items
/// with no override scale with the crowd — exactly how every item behaved
/// before folders existed, so upgrade day changes no number.
library;

enum DemandBasis {
  /// "More people, more of it." Food, disposables, merch. The existing
  /// engine path, unchanged: median per-person rate × attendance.
  perPerson('per_person'),

  /// "About the same every event." Soap, scrubbers, signs, the cash box.
  /// The median of what past events actually used; attendance ignored.
  perEvent('per_event');

  const DemandBasis(this.dbValue);

  /// The stored string ('per_person' | 'per_event'), CHECK-enforced in SQL.
  final String dbValue;

  static DemandBasis fromDb(String value) => switch (value) {
    'per_person' => DemandBasis.perPerson,
    'per_event' => DemandBasis.perEvent,
    _ => throw ArgumentError.value(value, 'value', 'not a demand basis'),
  };

  static DemandBasis? fromDbNullable(String? value) =>
      value == null ? null : fromDb(value);
}

/// THE effective-basis resolution — the only place the rule lives. Screens,
/// services, and the forecast builder all call this; none re-derives it.
///
/// Item override wins, else the folder's answer, else [DemandBasis.perPerson]
/// — the pre-folders behaviour, so untouched data forecasts untouched.
DemandBasis effectiveDemandBasis({
  DemandBasis? itemOverride,
  DemandBasis? folderBasis,
}) => itemOverride ?? folderBasis ?? DemandBasis.perPerson;
