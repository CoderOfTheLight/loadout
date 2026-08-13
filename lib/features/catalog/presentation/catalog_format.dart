/// Display helpers private to the catalog screens (design §9 Items rows):
/// exact micros-to-text formatting (never `double`), movement labels, and
/// day/time captions for the movement history preview.
library;

import 'package:flutter/material.dart';

import '../../../app/unit_display.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../../inventory/domain/movement.dart';

/// U+2212, the minus used throughout the design copy ("−2").
const String minusSign = '−';

/// Formats signed micros exactly: `-2_000_000` → `"−2"`, `1_500_000` →
/// `"1.5"`. Negatives are never clamped (design §9 ItemListScreen).
String formatMicros(int micros) => micros < 0
    ? '$minusSign${QuantityCodec.format(Quantity.fromMicros(-micros))}'
    : QuantityCodec.format(Quantity.fromMicros(micros));

/// Like [formatMicros] but with an explicit `+` on positive values, for
/// ledger rows: `5_000_000` → `"+5"`.
String formatSignedMicros(int micros) =>
    micros < 0 ? formatMicros(micros) : '+${formatMicros(micros)}';

/// An item's quantity as the owner reads it: "12", or "2.5 kg" for a
/// legacy measured row (see [unitSuffix]).
String formatCount(int micros, ItemUnit unit) =>
    '${formatMicros(micros)}${unitSuffix(unit)}';

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
