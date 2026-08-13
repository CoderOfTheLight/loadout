import 'dart:convert';
import 'dart:math' show max;

import '../../../core/errors.dart';
import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../data/db/app_database.dart' as db;
import '../../approval/domain/approval_service.dart';
import '../../approval/domain/commands.dart';
import '../../approval/domain/proposal.dart';
import '../../settings/application/settings_service.dart';
import '../domain/forecast_engine.dart';
import '../domain/snapshot.dart';
import '../domain/snapshot_inputs.dart';
import '../../../data/db/table_watch.dart';
import 'baseline_estimator.dart';

/// Screen-facing forecasting surface (design §6.5). Snapshots are appended,
/// never rewritten; the frozen engine is the only arithmetic source.
abstract interface class ForecastService {
  /// Runs the frozen engine over every planned item, persists snapshot +
  /// lines + evidence via SaveForecastSnapshot. Appends; never rewrites.
  Future<Result<ForecastSnapshotView>> generateSnapshot(String eventId);

  Stream<ForecastSnapshotView?> watchLatestSnapshot(String eventId);

  /// True when the latest snapshot's inputs_hash differs from a hash of the
  /// inputs as they are now (drives the staleness banner).
  Future<bool> isStale(String eventId);

  Future<Result<void>> setOverride({
    required String snapshotId,
    required String itemId,
    required Quantity load,
    required String reason,
  });

  /// NULL-load override row: reverts display to the engine value.
  Future<Result<void>> clearOverride({
    required String snapshotId,
    required String itemId,
    required String reason,
  });

  /// Closed-event read model (design §6.6): actuals derived by join, never
  /// stored.
  Future<AccuracyReview> accuracyReview(String eventId);
}

final class DriftForecastService implements ForecastService {
  DriftForecastService(
    db.AppDatabase database,
    ApprovalService approval,
    DriftSettingsService settings, {
    this._engine = const DeterministicForecastEngine(),
    IdGenerator idGenerator = const UlidIdGenerator(),
    this._clock = const SystemClock(),
  }) : _db = database,
       _approval = approval,
       _settings = settings,
       _ids = idGenerator;

  final db.AppDatabase _db;
  final ApprovalService _approval;
  final DriftSettingsService _settings;
  final ForecastEngine _engine;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<ForecastSnapshotView>> generateSnapshot(String eventId) async {
    final build = await _buildDraft(eventId);
    return build.fold((draft) async {
      final result = await _submit(SaveForecastSnapshot(draft));
      return result.fold(
        (receipt) async => Ok(await _loadView(receipt.createdRecordIds.first)),
        (error) async => Err<ForecastSnapshotView>(error),
      );
    }, (error) async => Err<ForecastSnapshotView>(error));
  }

  @override
  Stream<ForecastSnapshotView?> watchLatestSnapshot(String eventId) => _db
      .watchTables('forecast.latestSnapshot', {
        _db.forecastSnapshots,
        _db.forecastLines,
        _db.forecastEvidence,
        _db.forecastOverrides,
      })
      .asyncMap((_) async {
        final latest = await _db.forecastDao.latestSnapshotForEvent(eventId);
        return latest == null ? null : await _loadView(latest.id);
      });

  @override
  Future<bool> isStale(String eventId) async {
    final latest = await _db.forecastDao.latestSnapshotForEvent(eventId);
    if (latest == null) return false;
    final build = await _buildInputs(eventId);
    return build.fold(
      (inputs) => computeInputsHash(inputs) != latest.inputsHash,
      // Inputs can no longer be rebuilt (event closed/cancelled or exposure
      // cleared): a closed event's snapshot is frozen history, not stale.
      (error) => false,
    );
  }

  @override
  Future<Result<void>> setOverride({
    required String snapshotId,
    required String itemId,
    required Quantity load,
    required String reason,
  }) async {
    final result = await _submit(
      OverrideForecastLine(
        snapshotId: ForecastSnapshotId(snapshotId),
        itemId: ItemId(itemId),
        overrideLoad: load,
        reason: reason,
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> clearOverride({
    required String snapshotId,
    required String itemId,
    required String reason,
  }) async {
    final result = await _submit(
      OverrideForecastLine(
        snapshotId: ForecastSnapshotId(snapshotId),
        itemId: ItemId(itemId),
        overrideLoad: null,
        reason: reason,
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<AccuracyReview> accuracyReview(String eventId) async {
    final latestSnapshot = await _db.forecastDao.latestSnapshotForEvent(
      eventId,
    );
    final closeoutHeader = await _db.closeoutDao.latestHeaderForEvent(eventId);
    final snapshotView = latestSnapshot == null
        ? null
        : await _loadView(latestSnapshot.id);
    final closeoutLines = closeoutHeader == null
        ? const <db.CloseoutLine>[]
        : await _db.closeoutDao.linesFor(closeoutHeader.id);
    final actualByItem = {for (final line in closeoutLines) line.itemId: line};
    final snapshotByItem = {
      for (final line in snapshotView?.lines ?? const <ForecastLineView>[])
        line.itemId as String: line,
    };
    final itemIds = <String>{
      ...snapshotByItem.keys,
      ...actualByItem.keys,
    }.toList()..sort();
    return AccuracyReview(
      eventId: EventId(eventId),
      snapshotId: snapshotView?.id,
      closeoutId: closeoutHeader == null ? null : CloseoutId(closeoutHeader.id),
      upcomingExposure: snapshotView?.upcomingExposure,
      confirmedExposure: closeoutHeader?.confirmedExposure,
      lines: [
        for (final itemId in itemIds)
          _accuracyLine(itemId, snapshotByItem[itemId], actualByItem[itemId]),
      ],
    );
  }

  AccuracyLine _accuracyLine(
    String itemId,
    ForecastLineView? forecast,
    db.CloseoutLine? actual,
  ) {
    final expected = forecast?.plannedExpectedUseMicros;
    final actualDepletion = actual?.depletionMicros;
    return AccuracyLine(
      itemId: ItemId(itemId),
      expectedUseMicros: expected,
      loadMicros: forecast?.suggestedLoadMicros,
      basis: forecast?.basis ?? ForecastBasis.insufficientData,
      override: forecast?.override,
      actualDepletionMicros: actualDepletion,
      varianceMicros: expected == null || actualDepletion == null
          ? null
          : actualDepletion - expected,
      stockout: actual?.stockout ?? false,
      approximate: actual?.approximate ?? false,
    );
  }

  // -------------------------------------------------------------- builders

  Future<Result<ForecastSnapshotDraft>> _buildDraft(String eventId) async {
    final inputsResult = await _buildInputs(eventId);
    return inputsResult.fold((inputs) async {
      final exposureLabel = await _settings.exposureLabel();
      final lines = <ForecastSnapshotLineDraft>[];
      for (final input in inputs.lines) {
        if (_exceedsEngineEnvelope(input, inputs.upcomingExposure)) {
          // Outside the envelope the frozen engine's rate × exposure product
          // wraps int64 and it would return a plausible-looking but wrong
          // number. Report no forecast instead: a blank line with the reason
          // is honest, a wrong load quantity is not.
          lines.add(
            ForecastSnapshotLineDraft(
              itemId: ItemId(input.itemId),
              packSizeMicros: input.packSizeMicros,
              onHandMicros: input.onHandMicros,
              confirmedInboundMicros: input.confirmedInboundMicros,
              servesPerUnitMicros: input.servesPerUnitMicros,
              expectedUseMicros: null,
              plannedMicros: null,
              loadMicros: null,
              acquireMicros: null,
              evidenceGrade: EvidenceGrade.insufficientData,
              warnings: const [
                'Confirmed history for this item is too large to scale to '
                    'this event. Check the recorded outcomes and attendance.',
              ],
              evidence: input.evidence,
            ),
          );
          continue;
        }
        final engineLine = _engine.forecastDirect(
          upcomingExposure: inputs.upcomingExposure,
          observations: [
            for (final e in input.evidence)
              ConfirmedObservation(
                exposure: e.exposure,
                depletion: Quantity.fromMicros(e.depletionMicros),
                stockout: e.stockout,
                approximate: e.approximate,
              ),
          ],
          policy: inputs.policy,
          packSize: Quantity.fromMicros(input.packSizeMicros),
          usableOnHand: Quantity.fromMicros(max(0, input.onHandMicros)),
        );
        // No confirmed outcomes yet? The engine correctly refuses to
        // forecast. If the item says "1 serves N" we can still hand the
        // owner a starting number — clearly labelled, in its own columns,
        // and never mistakable for history.
        final baseline = engineLine.evidenceGrade == EvidenceGrade.insufficientData
            ? estimateFromServesPerUnit(
                expectedAttendance: inputs.upcomingExposure,
                servesPerUnitMicros: input.servesPerUnitMicros,
                policy: inputs.policy,
                packSizeMicros: input.packSizeMicros,
                usableOnHandMicros: max(0, input.onHandMicros),
                confirmedInboundMicros: input.confirmedInboundMicros,
              )
            : null;
        lines.add(
          ForecastSnapshotLineDraft(
            itemId: ItemId(input.itemId),
            packSizeMicros: input.packSizeMicros,
            onHandMicros: input.onHandMicros,
            confirmedInboundMicros: input.confirmedInboundMicros,
            servesPerUnitMicros: input.servesPerUnitMicros,
            expectedUseMicros: engineLine.expectedUse?.micros,
            plannedMicros: engineLine.plannedQuantity?.micros,
            loadMicros: engineLine.roundedLoadQuantity?.micros,
            acquireMicros: engineLine.acquireQuantity?.micros,
            baselineServesPerUnitMicros: baseline?.servesPerUnitMicros,
            baselineExpectedUseMicros: baseline?.expectedUseMicros,
            baselinePlannedMicros: baseline?.plannedMicros,
            baselineLoadMicros: baseline?.loadMicros,
            baselineAcquireMicros: baseline?.acquireMicros,
            evidenceGrade: engineLine.evidenceGrade,
            warnings: baseline == null
                ? engineLine.warnings
                : [...engineLine.warnings, baseline.warning],
            evidence: input.evidence,
          ),
        );
      }
      final assumptions = <String, Object?>{
        'reserve_percent': inputs.policy.reservePercent,
        'history_window': inputs.historyWindow,
        'rate_normalization': 'per_exposure_median',
        'exposure_label': exposureLabel,
      };
      return Ok(
        ForecastSnapshotDraft(
          eventId: EventId(eventId),
          policy: inputs.policy,
          upcomingExposure: inputs.upcomingExposure,
          historyWindow: inputs.historyWindow,
          inputsHash: computeInputsHash(inputs),
          assumptionsJson: jsonEncode(assumptions),
          lines: lines,
        ),
      );
    }, (error) async => Err<ForecastSnapshotDraft>(error));
  }

  /// Rebuilds [SnapshotInputs] from live state — used both to generate and
  /// to check staleness. Policy falls back to the workspace default
  /// (`events` carries no per-event policy column in v1).
  Future<Result<SnapshotInputs>> _buildInputs(String eventId) async {
    final event = await _db.eventDao.byId(eventId);
    if (event == null) return const Err(NotFoundError('event not found'));
    if (event.status != 'planned' && event.status != 'active') {
      return const Err(
        ValidationError(
          'forecasts are generated only for planned or active events',
        ),
      );
    }
    final exposure = event.plannedExposure;
    if (exposure == null) {
      return const Err(
        ValidationError('set the planned exposure before forecasting'),
      );
    }
    final policy = await _settings.defaultPolicy();
    final historyWindow = await _settings.historyWindow();
    final planned = await _db.eventDao.plannedItems(eventId);
    final lines = <SnapshotLineInput>[];
    for (final plannedItem in planned) {
      final item = await _db.itemDao.byId(plannedItem.itemId);
      if (item == null) continue;
      final history = await _db.forecastDao.labelHistory(
        item.id,
        historyWindow: historyWindow,
      );
      final onHand = await _db.ledgerDao.onHandMicros(item.id);
      lines.add(
        SnapshotLineInput(
          itemId: item.id,
          packSizeMicros: item.packSizeMicros,
          onHandMicros: onHand,
          servesPerUnitMicros: item.servesPerUnitMicros,
          evidence: [
            for (final row in history)
              EvidenceInput(
                closeoutId: row.closeoutId,
                sourceEventId: row.eventId,
                exposure: row.confirmedExposure,
                depletionMicros: row.depletionMicros,
                stockout: row.stockout,
                approximate: row.approximate,
              ),
          ],
        ),
      );
    }
    return Ok(
      SnapshotInputs(
        policy: policy,
        upcomingExposure: exposure,
        historyWindow: historyWindow,
        lines: lines,
      ),
    );
  }

  // ---------------------------------------------------------------- views

  Future<ForecastSnapshotView> _loadView(String snapshotId) async {
    final header = (await _db.forecastDao.snapshotById(snapshotId))!;
    final lines = await _db.forecastDao.linesForSnapshot(snapshotId);
    final evidence = await _db.forecastDao.evidenceForSnapshot(snapshotId);
    final overrides = await _db.forecastDao.overridesForSnapshot(snapshotId);
    final evidenceByItem = <String, List<EvidenceView>>{};
    for (final row in evidence) {
      evidenceByItem
          .putIfAbsent(row.itemId, () => [])
          .add(
            EvidenceView(
              position: row.position,
              closeoutId: CloseoutId(row.closeoutId),
              sourceEventId: EventId(row.sourceEventId),
              exposure: row.exposure,
              depletionMicros: row.depletionMicros,
              stockout: row.stockout,
              approximate: row.approximate,
            ),
          );
    }
    // Rows come back oldest-first; the latest (MAX(id)) wins for display.
    final overrideByItem = <String, OverrideView>{};
    for (final row in overrides) {
      overrideByItem[row.itemId] = OverrideView(
        id: row.id,
        overrideLoadMicros: row.overrideLoadMicros,
        reason: row.reason,
        createdAt: Instant(row.createdAtMicros),
      );
    }
    return ForecastSnapshotView(
      id: ForecastSnapshotId(header.id),
      eventId: EventId(header.eventId),
      method: header.method,
      methodVersion: header.methodVersion,
      policy: PlanningPolicy.values.byName(header.policy),
      upcomingExposure: header.upcomingExposure,
      historyWindow: header.historyWindow,
      inputsHash: header.inputsHash,
      assumptionsJson: header.assumptionsJson,
      createdAt: Instant(header.createdAtMicros),
      lines: [
        for (final line in lines)
          ForecastLineView(
            itemId: ItemId(line.itemId),
            packSizeMicros: line.packSizeMicros,
            onHandMicros: line.onHandMicros,
            confirmedInboundMicros: line.confirmedInboundMicros,
            expectedUseMicros: line.expectedUseMicros,
            plannedMicros: line.plannedMicros,
            loadMicros: line.loadMicros,
            acquireMicros: line.acquireMicros,
            baselineServesPerUnitMicros: line.baselineServesPerUnitMicros,
            baselineExpectedUseMicros: line.baselineExpectedUseMicros,
            baselinePlannedMicros: line.baselinePlannedMicros,
            baselineLoadMicros: line.baselineLoadMicros,
            baselineAcquireMicros: line.baselineAcquireMicros,
            evidenceGrade: evidenceGradeFromDb(line.evidenceGrade),
            warnings: [
              for (final warning in jsonDecode(line.warningsJson) as List)
                warning as String,
            ],
            evidence: evidenceByItem[line.itemId] ?? const [],
            override: overrideByItem[line.itemId],
          ),
      ],
    );
  }

  /// Whether scaling this item's history to [upcomingExposure] would leave
  /// the range the frozen engine can compute in.
  ///
  /// The engine normalises each observation to `depletion × 1e6 ÷ exposure`
  /// and multiplies the median by the upcoming exposure. Both the schema and
  /// the validator accept a depletion of 1e12 micros against an exposure of
  /// 1 — a plausible typo — and that product overflows int64 silently. The
  /// median is bounded by the largest observed rate, so bounding that is
  /// enough and needs no copy of the engine's median.
  static bool _exceedsEngineEnvelope(
    SnapshotLineInput input,
    int upcomingExposure,
  ) {
    if (upcomingExposure <= 0) return false; // the engine rejects this itself
    final limit = Quantity.maxMicros ~/ upcomingExposure;
    for (final e in input.evidence) {
      if (e.exposure <= 0) continue; // filtered by the engine
      final rate = (e.depletionMicros * Quantity.scale) ~/ e.exposure;
      if (rate > limit) return true;
    }
    return false;
  }

  Future<Result<CommandReceipt>> _submit(WorkspaceCommand command) =>
      _approval.submit(
        Proposal(
          commandId: CommandId(_ids.newId()),
          origin: ProposalOrigin.form,
          command: command,
          createdAt: _clock.now(),
        ),
      );
}
