/// "About the same every event": the per-event demand basis.
///
/// Soap does not scale with the crowd. Two containers used at each of three
/// 200-person events means "bring about two", not "0.01 per person" — the
/// per-person reading turns a 2,000-person event into a demand for 17
/// containers of soap, which is how the whole folders-and-basis feature was
/// motivated. The honest forecast is the MEDIAN OF WHAT PAST EVENTS ACTUALLY
/// USED, attendance ignored.
///
/// This lives OUTSIDE `domain/forecast_engine.dart` on purpose: the engine
/// is FROZEN and stays the only thing that turns observations into a
/// forecast. What happens here is a transform on the OBSERVATIONS the engine
/// is handed — the same seam `stockout_adjustment.dart` established — stated
/// once and applied identically by generation and by replay:
///
/// * Every confirmed observation is mapped to `exposure: 1`, its depletion
///   untouched.
/// * The engine is then called with `upcomingExposure:`
///   [perEventEngineExposure] (= 1).
/// * The engine's rate for each observation becomes
///   `depletion × 1e6 ÷ 1 = depletion × 1e6`, so its median-of-rates IS the
///   median of per-event depletions, and `medianRate × 1 ÷ 1e6` hands the
///   median depletion straight back. Median-of-depletions falls out of the
///   frozen median-of-rates path; not one line of engine arithmetic changes.
///
/// Ordering with the sell-out rule: map to exposure 1 FIRST, then
/// `adjustForSellouts`. On exposure-1 observations the sell-out lift raises
/// a ran-out day's DEPLETION to the median depletion of the days that did
/// not run out — exactly the per-event reading of "demand was probably
/// higher than recorded". Lifting before the mapping would raise it to an
/// attendance-relative rate, which is the arithmetic this basis exists to
/// escape.
///
/// Int64 headroom at exposure 1 (pinned in
/// `test/domain/per_event_basis_test.dart`): depletion is schema-capped at
/// 1e12 micros, so a rate is at most 1e12 × 1e6 = 1e18 < 2^63−1 ≈ 9.22e18,
/// and the engine's even-count median sums two rates: ≤ 2e18, still safe.
/// The engine then multiplies the median by an upcoming exposure of 1, so no
/// later product grows. This is why the per-person engine-envelope check is
/// not needed on this path: the schema caps ARE the envelope.
///
/// The stored `forecast_evidence` rows keep the real confirmed exposures and
/// depletions — the mapping exists only in memory, on the way into the
/// engine, and is re-derived from the stored basis on replay.
///
/// All arithmetic is exact integer micros (ADR 0001): no doubles anywhere.
library;

import '../domain/forecast_engine.dart';

/// The exposure handed to the frozen engine for a per-event line — both for
/// every observation and as the upcoming exposure, so attendance cancels
/// out of the arithmetic entirely.
const int perEventEngineExposure = 1;

/// Maps confirmed observations to `exposure: 1` for the per-event basis.
/// Pure and total. Observations with a non-positive exposure are passed
/// through untouched — the engine ignores them, exactly as it would have.
List<ConfirmedObservation> perEventObservations(
  List<ConfirmedObservation> observations,
) => List.unmodifiable([
  for (final o in observations)
    if (o.exposure > 0)
      ConfirmedObservation(
        exposure: perEventEngineExposure,
        depletion: o.depletion,
        stockout: o.stockout,
        approximate: o.approximate,
      )
    else
      o,
]);

/// The supplies-jump rule (owner-approved): a per-event estimate deliberately
/// ignores attendance, so when the upcoming event is far outside the range
/// the estimate was learned from — more than TWICE the largest exposure among
/// its confirmed evidence — the line says so out loud. A warning, never
/// arithmetic: no scaling math is invented, the median stays the estimate.
///
/// Uses the REAL stored exposures (the evidence rows), not the mapped
/// exposure-1 observations the engine sees.
bool perEventSuppliesJump({
  required int upcomingExposure,
  required Iterable<int> observedExposures,
}) {
  var largest = 0;
  for (final exposure in observedExposures) {
    if (exposure > largest) largest = exposure;
  }
  return largest > 0 && upcomingExposure > 2 * largest;
}

/// The stored line warning for a supplies jump, persisted on the snapshot
/// line beside the engine's own warnings like every other application-layer
/// note.
const String perEventSuppliesJumpWarning =
    'This estimate comes from much smaller events — bring more than usual '
    'and count what you use.';

/// The machine-readable rule tag recorded in a snapshot's assumptions.
const String perEventRuleTag = 'per_event_median_exposure_1';

/// The rule in one sentence, recorded in a snapshot's assumptions so a
/// stored forecast can still explain itself years later.
const String perEventRuleNote =
    'Items marked "about the same every event" are forecast as the middle '
    'of what past events actually used: every confirmed outcome counts as '
    'one event and attendance is ignored.';
