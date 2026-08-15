/// The no-history baseline: what to bring to a first-ever event.
///
/// The frozen engine forecasts from CONFIRMED outcomes only, so an item that
/// has never been closed out gets `insufficient_data` and no number at all —
/// which is exactly right as evidence, and useless as a plan. When the owner
/// answered a cold-start question we can say something honest instead:
/// - "1 serves N" → "120 people coming, 1 serves 4, so bring 33";
/// - the flipped "N per person" exact ratio → "200 people × 3 per person is
///   exactly 600" (`lib/core/unit_ratio.dart`, BigInt-safe ceil — never the
///   lossy micros reciprocal);
/// - per-event "how many do you usually bring?" → that number, plus the
///   usual reserve.
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
import '../../../core/unit_ratio.dart';
import '../domain/forecast_engine.dart';

/// One computed baseline. Every quantity field is micros. Exactly ONE
/// source is recorded: [servesPerUnitMicros] (micros of people served by
/// one unit), the [perPersonNumerator]/[perPersonDenominator] pair, or
/// [perEventMicros] — whichever cold-start answer produced the numbers.
final class BaselineEstimate {
  const BaselineEstimate({
    this.servesPerUnitMicros,
    this.perPersonNumerator,
    this.perPersonDenominator,
    this.perEventMicros,
    required this.expectedUseMicros,
    required this.plannedMicros,
    required this.loadMicros,
    required this.acquireMicros,
    required this.warning,
  });

  /// Set by [estimateFromServesPerUnit]; null otherwise.
  final int? servesPerUnitMicros;

  /// Set (together) by [estimateFromPerPersonRatio]; null otherwise.
  final int? perPersonNumerator;
  final int? perPersonDenominator;

  /// Set by [estimateFromPerEventBaseline]; null otherwise.
  final int? perEventMicros;

  /// Units needed before any reserve: `ceil(attendance ÷ serves)`,
  /// `ceil(attendance × N per person)`, or the usual per-event amount.
  final int expectedUseMicros;

  /// [expectedUseMicros] plus the policy's reserve percent.
  final int plannedMicros;

  /// [plannedMicros] rounded up to the pack size (1 unit = whole things).
  final int loadMicros;

  /// [loadMicros] minus what is already on hand and confirmed inbound,
  /// floored at zero.
  final int acquireMicros;

  /// Plain-language reason, stored on the snapshot line. Says outright that
  /// this is an estimate from a planning answer, not a confirmed outcome.
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

  return _shape(
    expected: () => Quantity.whole(wholeUnits),
    policy: policy,
    packSizeMicros: packSizeMicros,
    usableOnHandMicros: usableOnHandMicros,
    confirmedInboundMicros: confirmedInboundMicros,
    servesPerUnitMicros: servesPerUnitMicros,
    warning: baselineWarning(servesPerUnitMicros),
  );
}

/// Computes the baseline from the flipped "N per person" ratio, or null when
/// it cannot be stated honestly. The ratio is applied EXACTLY
/// (`UnitRatio.applyCeil`, BigInt inside): 200 people × 3/person is exactly
/// 600, never the 601 a micros reciprocal would produce. The result is then
/// rounded up to whole units, matching the serves path (counted goods).
///
/// Callers must only use this for items with ZERO confirmed observations,
/// and an item never carries both a ratio and a serves-per-unit
/// (validator-enforced).
BaselineEstimate? estimateFromPerPersonRatio({
  required int expectedAttendance,
  required int? numerator,
  required int? denominator,
  required PlanningPolicy policy,
  required int packSizeMicros,
  required int usableOnHandMicros,
  int confirmedInboundMicros = 0,
}) {
  if (numerator == null || denominator == null) return null;
  if (numerator <= 0 || denominator <= 0) return null;
  if (expectedAttendance <= 0) return null;
  if (packSizeMicros <= 0) return null;

  final ratio = UnitRatio(numerator, denominator);
  return _shape(
    // Units = attendance × N/D, exact ceil, then up to whole units.
    expected: () => ratio
        .applyCeil(Quantity.whole(expectedAttendance))
        .roundUpTo(Quantity.one),
    policy: policy,
    packSizeMicros: packSizeMicros,
    usableOnHandMicros: usableOnHandMicros,
    confirmedInboundMicros: confirmedInboundMicros,
    perPersonNumerator: numerator,
    perPersonDenominator: denominator,
    warning: perPersonRatioWarning(numerator, denominator),
  );
}

/// Computes the per-event baseline from "how many do you usually bring?",
/// or null when the owner never answered. Attendance plays no part — that
/// is the whole point of the per-event basis.
///
/// Callers must only use this for per-event items with ZERO confirmed
/// observations — where there is history, the frozen engine is
/// authoritative.
BaselineEstimate? estimateFromPerEventBaseline({
  required int? perEventBaselineMicros,
  required PlanningPolicy policy,
  required int packSizeMicros,
  required int usableOnHandMicros,
  int confirmedInboundMicros = 0,
}) {
  if (perEventBaselineMicros == null || perEventBaselineMicros <= 0) {
    return null;
  }
  if (packSizeMicros <= 0) return null;

  return _shape(
    expected: () => Quantity.fromMicros(perEventBaselineMicros),
    policy: policy,
    packSizeMicros: packSizeMicros,
    usableOnHandMicros: usableOnHandMicros,
    confirmedInboundMicros: confirmedInboundMicros,
    perEventMicros: perEventBaselineMicros,
    warning: perEventBaselineWarning(perEventBaselineMicros),
  );
}

/// The engine's shape, step for step: reserve percent, pack rounding,
/// acquire subtraction. Shared by all three cold-start sources so the
/// numbers read alike on screen. [expected] is a closure so its own
/// overflow (ratio × attendance beyond the envelope) is caught here too.
BaselineEstimate? _shape({
  required Quantity Function() expected,
  required PlanningPolicy policy,
  required int packSizeMicros,
  required int usableOnHandMicros,
  required int confirmedInboundMicros,
  int? servesPerUnitMicros,
  int? perPersonNumerator,
  int? perPersonDenominator,
  int? perEventMicros,
  required String warning,
}) {
  try {
    final expectedQuantity = expected();
    final planned = expectedQuantity.multiplyRatio(
      100 + policy.reservePercent,
      100,
    );
    final load = planned.roundUpTo(Quantity.fromMicros(packSizeMicros));
    final available = Quantity.fromMicros(
      (usableOnHandMicros < 0 ? 0 : usableOnHandMicros) +
          confirmedInboundMicros,
    );
    return BaselineEstimate(
      servesPerUnitMicros: servesPerUnitMicros,
      perPersonNumerator: perPersonNumerator,
      perPersonDenominator: perPersonDenominator,
      perEventMicros: perEventMicros,
      expectedUseMicros: expectedQuantity.micros,
      plannedMicros: planned.micros,
      loadMicros: load.micros,
      acquireMicros: load.subtractFloor(available).micros,
      warning: warning,
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

/// The stored warning for a flipped-ratio baseline.
String perPersonRatioWarning(int numerator, int denominator) =>
    'Estimate only: worked out from '
    '"${formatPerPersonRatio(numerator, denominator)}", not from confirmed '
    'outcomes. Close out this event and the next forecast uses what actually '
    'happened.';

/// The stored warning for a per-event baseline.
String perEventBaselineWarning(int perEventMicros) =>
    'Estimate only: your usual '
    '${formatServesPerUnit(perEventMicros)} per event, not a confirmed '
    'outcome. Close out this event and the next forecast uses what actually '
    'happened.';

/// Formats the flipped ratio the way the owner says it: `3/1` → "3 per
/// person", `1/2` → "1 per 2 people", `3/4` → "3 per 4 people".
String formatPerPersonRatio(int numerator, int denominator) => denominator == 1
    ? '$numerator per person'
    : '$numerator per $denominator people';

/// Formats micros of people as a plain number: `4000000` → `4`,
/// `2500000` → `2.5`. Trailing zeros are trimmed; never floating point.
String formatServesPerUnit(int micros) {
  final whole = micros ~/ Quantity.scale;
  final fraction = micros % Quantity.scale;
  if (fraction == 0) return '$whole';
  final digits = fraction
      .toString()
      .padLeft(6, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return '$whole.$digits';
}
