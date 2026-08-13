/// Sell-out days are a LOWER BOUND on demand, not demand.
///
/// When a closeout records "sold 40 and ran out", 40 is the most we could
/// observe, not the most she could have sold. Feeding that number into the
/// median exactly like a day that ended with stock left over biases every
/// forecast downward, and the bias feeds itself: run out, record 40, forecast
/// 40, bring 44, run out again. For a stall, running out is the expensive
/// failure, so this is the one place a small arithmetic choice costs real
/// money.
///
/// This lives OUTSIDE `domain/forecast_engine.dart` on purpose: the engine is
/// FROZEN and stays the only thing that turns observations into a forecast.
/// What happens here is a transform on the OBSERVATIONS the engine is handed,
/// stated once and applied identically by generation and by replay.
///
/// The rule, in full:
///
/// * Rate of an observation is the engine's own: `depletion × 1e6 ÷ exposure`,
///   truncated.
/// * Let `U` be the rates of the days that did NOT sell out and `C` the
///   sell-out days.
/// * `U` non-empty → every sell-out day's rate becomes
///   `max(itsOwnRate, median(U))`, using the engine's own median (middle
///   value; mean of the two middles, floored, for an even count). A sell-out
///   can only ever RAISE the estimate.
/// * `U` empty (every day sold out) → the whole history is a lower bound.
///   Every rate becomes the largest observed rate, and the caller warns that
///   real demand is unknown and probably higher.
/// * Days that did not sell out are never touched.
///
/// The engine takes depletions, not rates, so a lifted rate is realised as
/// the smallest depletion the engine will read back as at least that rate:
/// `ceil(rate × exposure ÷ 1e6)`. That makes the adjustment monotone —
/// every adjusted depletion is >= the one it replaced, so every adjusted
/// rate is >= the original, so the median is >= the original median, so the
/// adjusted forecast is never below the unadjusted one. `test/domain/
/// stockout_adjustment_test.dart` pins that as a property over a seeded RNG.
///
/// All arithmetic is exact integer micros (ADR 0001): no doubles anywhere.
library;

import '../../../core/quantity.dart';
import '../domain/forecast_engine.dart';

/// What the adjustment did to one item's history.
enum StockoutAdjustmentKind {
  /// No sell-out days (or nothing usable): the engine sees the raw history.
  none,

  /// Some days sold out; their rates were raised to the median rate of the
  /// days that did not.
  liftedToTypical,

  /// Every day sold out: the whole history is a lower bound, so the busiest
  /// day is used for all of them.
  everyDaySoldOut,
}

/// The observations to hand the frozen engine, plus what was done and why.
final class StockoutAdjustment {
  const StockoutAdjustment({
    required this.observations,
    required this.kind,
    required this.selloutCount,
    required this.observationCount,
    this.floorRateMicros,
    this.warning,
  });

  /// Engine-ready observations. Identical to the input when [kind] is
  /// [StockoutAdjustmentKind.none].
  ///
  /// These are NOT evidence. The stored `forecast_evidence` rows keep the
  /// real confirmed numbers; nothing here is ever written where a confirmed
  /// outcome belongs.
  final List<ConfirmedObservation> observations;

  final StockoutAdjustmentKind kind;

  /// How many sell-out days were in the usable history.
  final int selloutCount;

  /// How many usable observations there were (exposure > 0 — the engine's
  /// own filter).
  final int observationCount;

  /// The rate every sell-out day was raised to meet, or null when nothing
  /// was adjusted. Micros of depletion per unit of exposure, × 1e6.
  final int? floorRateMicros;

  /// Plain-language line warning, or null when there is nothing to say.
  /// Stored on the snapshot line beside the engine's own warnings.
  final String? warning;

  bool get adjusted => kind != StockoutAdjustmentKind.none;
}

/// Applies the sell-out rule to [observations]. Pure, total, and exact:
/// never throws, never overflows, never lowers anything.
StockoutAdjustment adjustForSellouts(List<ConfirmedObservation> observations) {
  // The engine ignores non-positive exposures; so do we, and they pass
  // through untouched.
  final usable = [
    for (final o in observations)
      if (o.exposure > 0) o,
  ];
  final selloutCount = usable.where((o) => o.stockout).length;
  if (selloutCount == 0) {
    return StockoutAdjustment(
      observations: List.unmodifiable(observations),
      kind: StockoutAdjustmentKind.none,
      selloutCount: 0,
      observationCount: usable.length,
    );
  }

  final steadyRates = [
    for (final o in usable)
      if (!o.stockout) rateOf(o),
  ]..sort();
  final everyDaySoldOut = steadyRates.isEmpty;
  final floorRate = everyDaySoldOut
      ? usable.map(rateOf).reduce((a, b) => a > b ? a : b)
      : medianOfSortedRates(steadyRates);

  final adjusted = [
    for (final o in observations)
      if (o.exposure > 0 && o.stockout) _lift(o, floorRate) else o,
  ];
  final kind = everyDaySoldOut
      ? StockoutAdjustmentKind.everyDaySoldOut
      : StockoutAdjustmentKind.liftedToTypical;
  return StockoutAdjustment(
    observations: List.unmodifiable(adjusted),
    kind: kind,
    selloutCount: selloutCount,
    observationCount: usable.length,
    floorRateMicros: floorRate,
    warning: selloutWarning(kind, selloutCount: selloutCount),
  );
}

/// The engine's rate for one observation: `depletion × 1e6 ÷ exposure`,
/// truncated. Depletion is capped at 1e12 micros and exposure at 1e6 by the
/// schema, so the product cannot wrap int64.
int rateOf(ConfirmedObservation o) =>
    (o.depletion.micros * Quantity.scale) ~/ o.exposure;

/// The engine's median over an already-sorted rate list: the middle value,
/// or the floored mean of the two middles for an even count.
int medianOfSortedRates(List<int> sorted) => sorted.length.isOdd
    ? sorted[sorted.length ~/ 2]
    : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) ~/ 2;

/// The stored line warning. Deliberately says what happened and what it
/// means, in the owner's words — no "censored", no "quantile".
String? selloutWarning(
  StockoutAdjustmentKind kind, {
  required int selloutCount,
}) => switch (kind) {
  StockoutAdjustmentKind.none => null,
  StockoutAdjustmentKind.liftedToTypical =>
    'You ran out on $selloutCount of these days, so demand was probably '
        'higher than recorded — this allows for that.',
  StockoutAdjustmentKind.everyDaySoldOut =>
    'You ran out every time, so nobody ever found out how much you could '
        'have sold. This uses your busiest day; real demand is unknown and '
        'probably higher.',
};

/// The machine-readable rule tag recorded in a snapshot's assumptions.
const String selloutRuleTag = 'sellouts_raise_never_lower';

/// The rule in one sentence, recorded in a snapshot's assumptions so a
/// stored forecast can still explain itself years later.
const String selloutRuleNote =
    'A day that sold out records a lower bound on demand, so its rate is '
    'raised to the median rate of the days that did not sell out, and never '
    'lowered. When every day sold out, the busiest day is used for all of '
    'them.';

/// Raises one sell-out observation to [floorRate], or returns it unchanged
/// when it already sold at least that fast.
ConfirmedObservation _lift(ConfirmedObservation o, int floorRate) {
  final lifted = _depletionForRate(floorRate, o.exposure);
  if (lifted == null || lifted <= o.depletion.micros) return o;
  return ConfirmedObservation(
    exposure: o.exposure,
    depletion: Quantity.fromMicros(lifted),
    stockout: o.stockout,
    approximate: o.approximate,
  );
}

/// The smallest depletion the engine reads back as a rate of at least
/// [rate] at [exposure] — `ceil(rate × exposure ÷ 1e6)`.
///
/// Returns null when that depletion would leave the exact-integer envelope.
/// Reaching that needs a raw rate above 1e15, which the caller's engine
/// envelope check already reports as un-forecastable, so the line never gets
/// a number either way — but leaving the observation alone is the safe
/// failure, since it can only ever forecast LOWER, never wrongly higher.
int? _depletionForRate(int rate, int exposure) {
  if (rate <= 0 || exposure <= 0) return null;
  // Split the rate so neither product can wrap: whole × exposure is bounded
  // by the envelope check below, and fraction × exposure is under 1e12 for
  // any exposure the schema allows.
  final whole = rate ~/ Quantity.scale;
  final fraction = rate % Quantity.scale;
  if (exposure > Quantity.maxMicros ~/ Quantity.scale) return null;
  if (whole > Quantity.maxMicros ~/ exposure) return null;
  final total =
      whole * exposure +
      (fraction * exposure + Quantity.scale - 1) ~/ Quantity.scale;
  return total > Quantity.maxMicros ? null : total;
}
