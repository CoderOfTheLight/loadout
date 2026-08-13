/// How a stored unit is shown, now that units have left the product
/// surface.
///
/// An item is a counted thing: a name, how many you have, and optionally
/// how many people one serves. Something sold by weight goes in the NAME
/// ("Mince (500 g packs)") and is counted as whole packs — the app never
/// does weight arithmetic. So a quantity reads as a bare number: "12", not
/// "12 each".
///
/// Rows created before schema v2 can still carry a real measurement unit,
/// and their stored numbers genuinely mean kilograms or litres. Hiding that
/// suffix would present a weight as a count, so those rows keep theirs.
library;

import '../core/units.dart';

/// Suffix for a quantity in running text: `''` for counted things,
/// `' kg'` for a legacy measured row.
String unitSuffix(ItemUnit unit) =>
    unit == ItemUnit.each ? '' : ' ${unit.dbValue}';

/// `suffixText` for a quantity input: null for counted things (the field
/// asks "how many"), the real unit for a legacy measured row.
String? unitFieldLabel(ItemUnit unit) =>
    unit == ItemUnit.each ? null : unit.dbValue;
