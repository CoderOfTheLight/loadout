/// The no-history baseline: what to bring to a first-ever event.
///
/// The frozen engine forecasts from CONFIRMED outcomes only, so an item that
/// has never been closed out gets `insufficient_data` and no number at all —
/// which is exactly right as evidence, and useless as a plan. When the owner
/// told us how many people one unit serves, we can say something honest
/// instead: "you have 120 people coming and 1 serves 4, so bring 33".
///
/// This lives OUTSIDE `domain/forecast_engine.dart` on purpose. The engine is
/// frozen and it is the only thing allowed to turn confirmed history into a
/// forecast. A baseline is not a forecast: it never reads history, never
/// becomes history, and is stored in its own columns with its own warning.
/// It reuses the engine's *shape* — same reserve percent, same pack
/// rounding, same acquire subtraction — so the two read alike on screen.
///
/// All arithmetic is exact integer micros (ADR 0001): no doubles anywhere.
library;

import '../../../core/errors.dart';
import '../../../core/quantity.dart';
import '../domain/forecast_engine.dart';

/// One computed baseline. Every field is micros; [servesPerUnitMicros] is
/// micros of people served by one unit.
final class BaselineEstimate {
  const BaselineEstimate({
    required this.servesPerUnitMicros,
    required this.expectedUseMicros,
    required this.plannedMicros,
    required this.loadMicros,
    required this.acquireMicros,
    required this.warning,
  });

  final int servesPerUnitMicros;

  /// Whole units needed to serve everyone: `ceil(attendance ÷ serves)`.
  final int expectedUseMicros;

  /// [expectedUseMicros] plus the policy's reserve percent.
  final int plannedMicros;

  /// [plannedMicros] rounded up to the pack size (1 unit = whole things).
  final int loadMicros;

  /// [loadMicros] minus what is already on hand and confirmed inbound,
  /// floored at zero.
  final int acquireMicros;

  /// Plain-language reason, stored on the snapshot line. Says outright that
  /// this is an estimate from "1 serves N" and not a confirmed outcome.
  final String warning;
}

/// Computes the baseline for one item, or null when it cannot be stated
/// honestly: no serves-per-unit, a nonsensical attendance, or numbers so
/// large they leave the exact-integer envelope.
///
/// Callers must only use this for items with ZERO confirmed observations —
/// where there is history, the frozen engine is authoritative.
BaselineEstimate? estimateFromServesPerUnit({
  required int expectedAttendance,
  required int? servesPerUnitMicros,
  required PlanningPolicy policy,
  required int packSizeMicros,
  required int usableOnHandMicros,
  int confirmedInboundMicros = 0,
}) {
  if (servesPerUnitMicros == null || servesPerUnitMicros <= 0) return null;
  if (expectedAttendance <= 0) return null;
  if (packSizeMicros <= 0) return null;

  // Units needed = ceil(attendance ÷ servesPerUnit). In micros of people:
  // attendance ÷ (serves/1e6) = attendance × 1e6 ÷ serves. Attendance is
  // capped at 1e6 by the schema, so the numerator is at most 1e12 — no
  // int64 wrap, and no floating point.
  final numerator = expectedAttendance * Quantity.scale;
  final wholeUnits =
      (numerator + servesPerUnitMicros - 1) ~/ servesPerUnitMicros;
  if (wholeUnits <= 0) return null;
  if (wholeUnits > Quantity.maxMicros ~/ Quantity.scale) return null;

  try {
    // From here the shape is the engine's, step for step.
    final expected = Quantity.whole(wholeUnits);
    final planned = expected.multiplyRatio(100 + policy.reservePercent, 100);
    final load = planned.roundUpTo(Quantity.fromMicros(packSizeMicros));
    final available = Quantity.fromMicros(
      (usableOnHandMicros < 0 ? 0 : usableOnHandMicros) +
          confirmedInboundMicros,
    );
    return BaselineEstimate(
      servesPerUnitMicros: servesPerUnitMicros,
      expectedUseMicros: expected.micros,
      plannedMicros: planned.micros,
      loadMicros: load.micros,
      acquireMicros: load.subtractFloor(available).micros,
      warning: baselineWarning(servesPerUnitMicros),
    );
  } on QuantityOverflowError {
    // Beyond the exact-integer envelope. A blank line is honest; a wrapped
    // number is not.
    return null;
  }
}

/// The stored warning string. Deliberately unambiguous about what this
/// number is not.
String baselineWarning(int servesPerUnitMicros) =>
    'Estimate only: worked out from "1 serves '
    '${formatServesPerUnit(servesPerUnitMicros)}", not from confirmed '
    'outcomes. Close out this event and the next forecast uses what actually '
    'happened.';

/// Formats micros of people as a plain number: `4000000` → `4`,
/// `2500000` → `2.5`. Trailing zeros are trimmed; never floating point.
String formatServesPerUnit(int micros) {
  final whole = micros ~/ Quantity.scale;
  final fraction = micros % Quantity.scale;
  if (fraction == 0) return '$whole';
  final digits = fraction.toString().padLeft(6, '0').replaceAll(
    RegExp(r'0+$'),
    '',
  );
  return '$whole.$digits';
}
