/// THE shared unit-label suggestion chips (v5 ruling: units are display
/// labels). One const, imported by every form that offers a unit label —
/// the item form and the recipe ingredient rows — never forked, so the two
/// surfaces can never drift apart.
///
/// A unit label is optional free text (≤24 characters, `unitLabelMaxLength`)
/// that decorates an amount: "0.5 cup", "2 lbs". The app NEVER converts
/// between units and never does arithmetic on them — forecasting works on
/// the bare amounts, unchanged. The chips are a convenience keyboard for
/// the common labels the ruling names (teaspoon/tsp, tablespoon/tbsp, cup,
/// oz, lb/lbs, package, bag, box, case, bottle, can, roll, each), in their
/// short everyday forms; anything else is typed freely.
library;

/// Validator bound for a unit label (mirrors the domain check: 1–24 chars
/// when present).
const int unitLabelMaxLength = 24;

/// Suggestion chips, in display order.
const List<String> unitLabelSuggestions = [
  'tsp',
  'tbsp',
  'cup',
  'oz',
  'lbs',
  'package',
  'bag',
  'box',
  'case',
  'bottle',
  'can',
  'roll',
  'each',
];
