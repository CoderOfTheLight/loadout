/// Display helpers private to the catalog screens (design §9 Items rows):
/// exact micros-to-text formatting (never `double`), movement labels, and
/// day/time captions for the movement history preview.
library;

import 'package:flutter/material.dart';

import '../../../app/unit_display.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/time.dart';
import '../../../core/unit_ratio.dart';
import '../../../core/units.dart';
import '../../inventory/domain/movement.dart';
import '../domain/demand_basis.dart';

/// U+2212, the minus used throughout the design copy ("−2").
const String minusSign = '−';

/// Formats signed micros for READING: `-2_000_000` → `"−2"`, `1_500_000` →
/// `"1.5"`, `14_272_728` → `"14.3"`. Negatives are never clamped (design §9
/// ItemListScreen).
///
/// Rounded through [QuantityCodec.formatDisplay], not [QuantityCodec.format]:
/// screens read counted goods, and micros precision on a row that says
/// "6 trays" is engine noise. Form fields keep the exact round-trip form.
String formatMicros(int micros) => micros < 0
    ? '$minusSign${QuantityCodec.formatDisplayMicros(-micros)}'
    : QuantityCodec.formatDisplayMicros(micros);

/// Like [formatMicros] but with an explicit `+` on positive values, for
/// ledger rows: `5_000_000` → `"+5"`.
String formatSignedMicros(int micros) =>
    micros < 0 ? formatMicros(micros) : '+${formatMicros(micros)}';

/// An item's quantity as the owner reads it: "12", or "2.5 kg" for a
/// legacy measured row (see [unitSuffix]).
String formatCount(int micros, ItemUnit unit) =>
    '${formatMicros(micros)}${unitSuffix(unit)}';

/// The amount with its display label after it — "12 packages", "0.5 cup",
/// bare "12" when the item has no label. A legacy measured row's REAL unit
/// always wins over the label: its stored numbers genuinely mean kilograms
/// or litres, and a display label must never present a weight as something
/// else. Labels are display-only — never converted, never computed with.
String formatAmount(int micros, ItemUnit unit, String? unitLabel) {
  if (unit != ItemUnit.each) {
    return formatCount(micros, unit);
  }
  final amount = formatMicros(micros);
  return unitLabel == null ? amount : '$amount $unitLabel';
}

/// The two plain answers to the one question every item answers — "Does how
/// much you bring depend on how many people come?" Worded to fit the
/// kitchen and the sales table alike; never "sold", never "eaten".
String demandBasisLabel(DemandBasis basis) => switch (basis) {
  DemandBasis.perPerson => 'More people, more of it',
  DemandBasis.perEvent => 'About the same every event',
};

/// The flipped cold-start phrasing as the owner says it: "3 per person"
/// (or "3 per 4 people" for a stored ratio this form's whole-number field
/// cannot express).
String perPersonRatioPhrase(UnitRatio ratio) => ratio.denominator == 1
    ? '${ratio.numerator} per person'
    : '${ratio.numerator} per ${ratio.denominator} people';

/// Movement-kind display label (§5 kinds; forms call `adjust` a count).
String movementKindLabel(MovementKind kind) => switch (kind) {
  MovementKind.receive => 'Purchase',
  MovementKind.consume => 'Event use',
  MovementKind.waste => 'Waste',
  MovementKind.adjust => 'Count adjustment',
  MovementKind.reversal => 'Correction',
};

/// Movement-kind icon — meaning is never color-only (§9).
IconData movementKindIcon(MovementKind kind) => switch (kind) {
  MovementKind.receive => Icons.local_shipping_outlined,
  MovementKind.consume => Icons.storefront_outlined,
  MovementKind.waste => Icons.delete_outline,
  MovementKind.adjust => Icons.fact_check_outlined,
  MovementKind.reversal => Icons.undo,
};

DateTime _local(Instant instant) => DateTime.fromMicrosecondsSinceEpoch(
  instant.epochMicrosUtc,
  isUtc: true,
).toLocal();

String _pad(int value) => value.toString().padLeft(2, '0');

/// Local calendar day, `YYYY-MM-DD` (§3 business-date shape).
String formatDay(Instant instant) {
  final t = _local(instant);
  return '${t.year.toString().padLeft(4, '0')}-${_pad(t.month)}-${_pad(t.day)}';
}

/// Local wall-clock time, `HH:mm`.
String formatTime(Instant instant) {
  final t = _local(instant);
  return '${_pad(t.hour)}:${_pad(t.minute)}';
}
