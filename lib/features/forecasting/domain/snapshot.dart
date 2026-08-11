import '../../../core/ids.dart';
import '../../../core/time.dart';
import 'forecast_engine.dart';
import 'snapshot_inputs.dart';

/// The only forecast method shipping in v1 (design §6.6).
const String forecastMethodDirectMedian = 'direct_median';
const int forecastMethodVersion = 1;

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
    this.expectedUseMicros,
    this.plannedMicros,
    this.loadMicros,
    this.acquireMicros,
    required this.evidenceGrade,
    this.warnings = const [],
    this.evidence = const [],
  });

  final ItemId itemId;
  final int packSizeMicros;

  /// SIGNED derived on-hand at generation time.
  final int onHandMicros;
  final int confirmedInboundMicros;
  final int? expectedUseMicros;
  final int? plannedMicros;
  final int? loadMicros;
  final int? acquireMicros;
  final EvidenceGrade evidenceGrade;

  /// The frozen engine's strings, verbatim.
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
    this.expectedUseMicros,
    this.plannedMicros,
    this.loadMicros,
    this.acquireMicros,
    required this.evidenceGrade,
    this.warnings = const [],
    this.evidence = const [],
    this.override,
  });

  final ItemId itemId;
  final int packSizeMicros;
  final int onHandMicros;
  final int confirmedInboundMicros;
  final int? expectedUseMicros;
  final int? plannedMicros;
  final int? loadMicros;
  final int? acquireMicros;
  final EvidenceGrade evidenceGrade;
  final List<String> warnings;
  final List<EvidenceView> evidence;

  /// Latest override row, or null when none was ever recorded.
  final OverrideView? override;

  /// Display load: the live override wins; a NULL-load override reverts to
  /// the engine value (design §4 forecast_overrides).
  int? get effectiveLoadMicros => override?.overrideLoadMicros ?? loadMicros;

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
    this.override,
    this.actualDepletionMicros,
    this.varianceMicros,
    this.stockout = false,
    this.approximate = false,
  });

  final ItemId itemId;
  final int? expectedUseMicros;
  final int? loadMicros;
  final OverrideView? override;

  /// Null when the closeout skipped this item.
  final int? actualDepletionMicros;

  /// `actual − expectedUse`; null when either side is missing.
  final int? varianceMicros;
  final bool stockout;
  final bool approximate;
}
