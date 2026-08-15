import '../../../core/ids.dart';
import '../../../core/time.dart';
import '../../catalog/domain/demand_basis.dart';
import 'forecast_engine.dart';
import 'snapshot_inputs.dart';

/// The only forecast method shipping in v1 (design §6.6).
const String forecastMethodDirectMedian = 'direct_median';

/// v2: sell-out days are treated as a lower bound on demand before the frozen
/// engine sees them (`application/stockout_adjustment.dart`).
///
/// v3: items whose demand basis is per_event are forecast as the median of
/// past events' actual usage — every confirmed observation is mapped to
/// exposure 1 before the frozen engine sees it
/// (`application/per_event_basis.dart`), so attendance is ignored. The
/// engine is unchanged both times, but the same confirmed history now
/// legitimately produces different numbers for those items, so the version
/// has to say so. The canonical input encoding carries the same tag, which
/// is what keeps "same hash ⇒ byte-identical outputs" true across the
/// change — every stored v2 snapshot honestly reads as out of date rather
/// than silently swapping numbers.
const int forecastMethodVersion = 3;

/// The first method version that treats a sell-out day as a lower bound on
/// demand. A snapshot stored below this was computed WITHOUT that correction,
/// and its numbers are frozen history: nothing on screen may describe them as
/// having allowed for the days that ran out, because they did not.
const int selloutAwareMethodVersion = 2;

/// The first method version that can forecast "about the same every event"
/// items from the median of their per-event usage. Below this, every stored
/// line was per-person arithmetic.
const int perEventAwareMethodVersion = 3;

/// Db string mapping for the frozen engine's [EvidenceGrade].
String evidenceGradeToDb(EvidenceGrade grade) => switch (grade) {
  EvidenceGrade.insufficientData => 'insufficient_data',
  EvidenceGrade.singleEvent => 'single_event',
  EvidenceGrade.observedRange => 'observed_range',
};

EvidenceGrade evidenceGradeFromDb(String value) => switch (value) {
  'insufficient_data' => EvidenceGrade.insufficientData,
  'single_event' => EvidenceGrade.singleEvent,
  'observed_range' => EvidenceGrade.observedRange,
  _ => throw ArgumentError.value(value, 'value', 'not an evidence grade'),
};

/// What a snapshot line's numbers actually rest on — the single field a
/// screen should switch on.
///
/// [EvidenceGrade] is the frozen engine's vocabulary and only ever describes
/// CONFIRMED outcomes; the baseline states are strictly weaker states the
/// engine cannot express: no confirmed outcomes at all, numbers derived from
/// a planning assumption — [servesBaseline] from the per-person cold start
/// ("1 serves N" or the flipped "N per person" ratio), [perEventBaseline]
/// from "how many do you usually bring". Both are stored as
/// `insufficient_data` plus the `baseline_*` columns, so the §4.3 label
/// query and every history/accuracy read stay exactly as blind to them as
/// they are to any other prediction.
enum ForecastBasis {
  insufficientData,
  servesBaseline,
  perEventBaseline,
  singleEvent,
  observedRange,
}

/// Fully-computed snapshot awaiting persistence (design §6.4
/// SaveForecastSnapshot): header, lines, evidence, inputsHash. The applier
/// recomputes the hash from [inputs] and rejects on mismatch.
final class ForecastSnapshotDraft {
  const ForecastSnapshotDraft({
    required this.eventId,
    required this.policy,
    required this.upcomingExposure,
    required this.historyWindow,
    required this.inputsHash,
    required this.assumptionsJson,
    required this.lines,
  });

  final EventId eventId;
  final PlanningPolicy policy;
  final int upcomingExposure;
  final int historyWindow;

  /// SHA-256 lowercase hex over the canonical input encoding (§6.6).
  final String inputsHash;
  final String assumptionsJson;
  final List<ForecastSnapshotLineDraft> lines;

  /// The embedded inputs, rebuilt for hash re-verification.
  SnapshotInputs get inputs => SnapshotInputs(
    policy: policy,
    upcomingExposure: upcomingExposure,
    historyWindow: historyWindow,
    lines: [
      for (final line in lines)
        SnapshotLineInput(
          itemId: line.itemId as String,
          packSizeMicros: line.packSizeMicros,
          onHandMicros: line.onHandMicros,
          confirmedInboundMicros: line.confirmedInboundMicros,
          demandBasis: line.demandBasis,
          servesPerUnitMicros: line.servesPerUnitMicros,
          perPersonNumerator: line.perPersonNumerator,
          perPersonDenominator: line.perPersonDenominator,
          perEventBaselineMicros: line.perEventBaselineMicros,
          evidence: line.evidence,
        ),
    ],
  );
}

/// Frozen inputs + engine outputs for one item.
final class ForecastSnapshotLineDraft {
  const ForecastSnapshotLineDraft({
    required this.itemId,
    required this.packSizeMicros,
    required this.onHandMicros,
    this.confirmedInboundMicros = 0,
    this.demandBasis = DemandBasis.perPerson,
    this.servesPerUnitMicros,
    this.perPersonNumerator,
    this.perPersonDenominator,
    this.perEventBaselineMicros,
    this.expectedUseMicros,
    this.plannedMicros,
    this.loadMicros,
    this.acquireMicros,
    this.baselineServesPerUnitMicros,
    this.baselinePerPersonNumerator,
    this.baselinePerPersonDenominator,
    this.baselinePerEventMicros,
    this.baselineExpectedUseMicros,
    this.baselinePlannedMicros,
    this.baselineLoadMicros,
    this.baselineAcquireMicros,
    required this.evidenceGrade,
    this.warnings = const [],
    this.evidence = const [],
  });

  final ItemId itemId;
  final int packSizeMicros;

  /// SIGNED derived on-hand at generation time.
  final int onHandMicros;
  final int confirmedInboundMicros;

  /// The EFFECTIVE demand basis this line was computed under (item override
  /// else folder else per_person), resolved once by the builder via
  /// `effectiveDemandBasis`. Hashed (it changes the outputs) and stored, so
  /// the line can always say which question its numbers answered.
  final DemandBasis demandBasis;

  /// The item's "1 serves N" at generation time — a hashed input, because it
  /// changes the baseline outputs. Not persisted on the line itself; the
  /// value that produced a baseline is in [baselineServesPerUnitMicros].
  /// Material only on per-person lines; the builder passes null otherwise.
  final int? servesPerUnitMicros;

  /// The item's flipped "N per person" ratio at generation time — hashed
  /// like [servesPerUnitMicros]; the pair that produced a baseline is in
  /// [baselinePerPersonNumerator]/[baselinePerPersonDenominator].
  final int? perPersonNumerator;
  final int? perPersonDenominator;

  /// The item's "how many do you usually bring" at generation time — hashed;
  /// material only on per-event lines. The value that produced a baseline is
  /// in [baselinePerEventMicros].
  final int? perEventBaselineMicros;
  final int? expectedUseMicros;
  final int? plannedMicros;
  final int? loadMicros;
  final int? acquireMicros;

  /// The no-history baseline plan. The four output fields are set together
  /// or all null, only ever on a line with no confirmed evidence, and
  /// accompanied by EXACTLY ONE source: serves-per-unit, the per-person
  /// ratio pair, or the per-event usual amount.
  final int? baselineServesPerUnitMicros;
  final int? baselinePerPersonNumerator;
  final int? baselinePerPersonDenominator;
  final int? baselinePerEventMicros;
  final int? baselineExpectedUseMicros;
  final int? baselinePlannedMicros;
  final int? baselineLoadMicros;
  final int? baselineAcquireMicros;
  final EvidenceGrade evidenceGrade;

  /// The frozen engine's strings verbatim, plus the baseline's own
  /// plain-language warning when one was computed.
  final List<String> warnings;

  /// Value-copies in label-query order.
  final List<EvidenceInput> evidence;
}

// ---------------------------------------------------------------- views

/// Persisted snapshot read model (design §6.5/§6.6): header + lines +
/// evidence + live overrides, from one persisted record.
final class ForecastSnapshotView {
  const ForecastSnapshotView({
    required this.id,
    required this.eventId,
    required this.method,
    required this.methodVersion,
    required this.policy,
    required this.upcomingExposure,
    required this.historyWindow,
    required this.inputsHash,
    required this.assumptionsJson,
    required this.createdAt,
    required this.lines,
  });

  final ForecastSnapshotId id;
  final EventId eventId;
  final String method;
  final int methodVersion;
  final PlanningPolicy policy;
  final int upcomingExposure;
  final int historyWindow;
  final String inputsHash;
  final String assumptionsJson;
  final Instant createdAt;
  final List<ForecastLineView> lines;
}

/// One snapshot line plus its evidence and live override (latest
/// `forecast_overrides` row, MAX(id) wins for display).
final class ForecastLineView {
  const ForecastLineView({
    required this.itemId,
    required this.packSizeMicros,
    required this.onHandMicros,
    required this.confirmedInboundMicros,
    this.demandBasis = DemandBasis.perPerson,
    this.expectedUseMicros,
    this.plannedMicros,
    this.loadMicros,
    this.acquireMicros,
    this.baselineServesPerUnitMicros,
    this.baselinePerPersonNumerator,
    this.baselinePerPersonDenominator,
    this.baselinePerEventMicros,
    this.baselineExpectedUseMicros,
    this.baselinePlannedMicros,
    this.baselineLoadMicros,
    this.baselineAcquireMicros,
    required this.evidenceGrade,
    this.warnings = const [],
    this.evidence = const [],
    this.override,
  });

  final ItemId itemId;
  final int packSizeMicros;
  final int onHandMicros;
  final int confirmedInboundMicros;

  /// The demand basis this line was computed under. Rows stored before v3
  /// carry NULL and load as [DemandBasis.perPerson] — which is what they
  /// were.
  final DemandBasis demandBasis;
  final int? expectedUseMicros;
  final int? plannedMicros;
  final int? loadMicros;
  final int? acquireMicros;

  /// The stored no-history baseline, or all null. See [basis].
  final int? baselineServesPerUnitMicros;
  final int? baselinePerPersonNumerator;
  final int? baselinePerPersonDenominator;
  final int? baselinePerEventMicros;
  final int? baselineExpectedUseMicros;
  final int? baselinePlannedMicros;
  final int? baselineLoadMicros;
  final int? baselineAcquireMicros;
  final EvidenceGrade evidenceGrade;
  final List<String> warnings;
  final List<EvidenceView> evidence;

  /// Latest override row, or null when none was ever recorded.
  final OverrideView? override;

  /// True when this line's numbers are a cold-start estimate ("1 serves N",
  /// "N per person", or "you usually bring N") rather than anything
  /// confirmed.
  bool get isBaseline => baselineLoadMicros != null;

  /// What the numbers rest on — switch on this, not on [evidenceGrade].
  ForecastBasis get basis => switch (evidenceGrade) {
    EvidenceGrade.insufficientData =>
      !isBaseline
          ? ForecastBasis.insufficientData
          : demandBasis == DemandBasis.perEvent
          ? ForecastBasis.perEventBaseline
          : ForecastBasis.servesBaseline,
    EvidenceGrade.singleEvent => ForecastBasis.singleEvent,
    EvidenceGrade.observedRange => ForecastBasis.observedRange,
  };

  /// Expected use to show: the engine's, else the baseline's estimate.
  int? get plannedExpectedUseMicros =>
      expectedUseMicros ?? baselineExpectedUseMicros;

  /// Planned quantity to show: the engine's, else the baseline's estimate.
  int? get suggestedPlannedMicros => plannedMicros ?? baselinePlannedMicros;

  /// Load to show before overrides: the engine's, else the baseline's.
  int? get suggestedLoadMicros => loadMicros ?? baselineLoadMicros;

  /// Quantity to acquire: the engine's, else the baseline's.
  int? get suggestedAcquireMicros => acquireMicros ?? baselineAcquireMicros;

  /// Display load: the live override wins; a NULL-load override reverts to
  /// the suggested value (design §4 forecast_overrides).
  int? get effectiveLoadMicros =>
      override?.overrideLoadMicros ?? suggestedLoadMicros;

  /// True when a non-null override is currently in force.
  bool get isOverridden => override?.overrideLoadMicros != null;
}

/// One stored evidence value-copy.
final class EvidenceView {
  const EvidenceView({
    required this.position,
    required this.closeoutId,
    required this.sourceEventId,
    required this.exposure,
    required this.depletionMicros,
    required this.stockout,
    required this.approximate,
  });

  final int position;
  final CloseoutId closeoutId;
  final EventId sourceEventId;
  final int exposure;
  final int depletionMicros;
  final bool stockout;
  final bool approximate;
}

/// Latest override row for one (snapshot, item).
final class OverrideView {
  const OverrideView({
    required this.id,
    this.overrideLoadMicros,
    required this.reason,
    required this.createdAt,
  });

  final String id;

  /// NULL means "revert to the engine value".
  final int? overrideLoadMicros;
  final String reason;
  final Instant createdAt;
}

// ---------------------------------------------------------------- accuracy

/// Closed-event accuracy read model (design §6.6): the latest snapshot's
/// lines joined to the latest closeout revision's lines on (event, item).
/// Actuals are derived by this join, never stored.
final class AccuracyReview {
  const AccuracyReview({
    required this.eventId,
    this.snapshotId,
    this.closeoutId,
    this.upcomingExposure,
    this.confirmedExposure,
    this.lines = const [],
  });

  final EventId eventId;
  final ForecastSnapshotId? snapshotId;
  final CloseoutId? closeoutId;
  final int? upcomingExposure;
  final int? confirmedExposure;
  final List<AccuracyLine> lines;
}

/// Per-item forecast-vs-actual comparison.
final class AccuracyLine {
  const AccuracyLine({
    required this.itemId,
    this.expectedUseMicros,
    this.loadMicros,
    this.basis = ForecastBasis.insufficientData,
    this.override,
    this.actualDepletionMicros,
    this.varianceMicros,
    this.stockout = false,
    this.approximate = false,
  });

  final ItemId itemId;

  /// What was expected: the engine's number, or the "1 serves N" baseline
  /// when that is all there was. [basis] says which — never present a
  /// baseline variance as if it came from confirmed history.
  final int? expectedUseMicros;
  final int? loadMicros;
  final ForecastBasis basis;
  final OverrideView? override;

  /// Null when the closeout skipped this item.
  final int? actualDepletionMicros;

  /// `actual − expectedUse`; null when either side is missing.
  final int? varianceMicros;
  final bool stockout;
  final bool approximate;
}
