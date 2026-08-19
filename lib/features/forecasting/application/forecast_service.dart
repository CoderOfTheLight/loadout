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
import '../../catalog/domain/demand_basis.dart';
import '../../settings/application/settings_service.dart';
import '../domain/forecast_engine.dart';
import '../domain/snapshot.dart';
import '../domain/snapshot_inputs.dart';
import '../../../data/db/table_watch.dart';
import 'baseline_estimator.dart';
import 'per_event_basis.dart';
import 'stockout_adjustment.dart';

/// Screen-facing forecasting surface (design §6.5). Snapshots are appended,
/// never rewritten; the frozen engine is the only arithmetic source.
abstract interface class ForecastService {
  /// Runs the frozen engine over every planned item, persists snapshot +
  /// lines + evidence via SaveForecastSnapshot. Appends; never rewrites.
  Future<Result<ForecastSnapshotView>> generateSnapshot(String eventId);

  Stream<ForecastSnapshotView?> watchLatestSnapshot(String eventId);

  /// The latest persisted snapshot for [eventId], or null — exactly what
  /// [watchLatestSnapshot] emits, read ONCE.
  ///
  /// Exists so a service assembling a view from several queries (event cost)
  /// can reuse this one without calling `.first` on a watch stream: that
  /// opens a second subscription per emission and can hang inside an
  /// `asyncMap`.
  Future<ForecastSnapshotView?> latestSnapshot(String eventId);

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
      .asyncMap((_) => latestSnapshot(eventId));

  @override
  Future<ForecastSnapshotView?> latestSnapshot(String eventId) async {
    final latest = await _db.forecastDao.latestSnapshotForEvent(eventId);
    return latest == null ? null : await _loadView(latest.id);
  }

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
      var selloutAdjustedLines = 0;
      var everyDaySoldOutLines = 0;
      var perEventLines = 0;
      for (final input in inputs.lines) {
        final isPerEvent = input.demandBasis == DemandBasis.perEvent;
        if (isPerEvent) perEventLines++;
        final rawObservations = [
          for (final e in input.evidence)
            ConfirmedObservation(
              exposure: e.exposure,
              depletion: Quantity.fromMicros(e.depletionMicros),
              stockout: e.stockout,
              approximate: e.approximate,
            ),
        ];
        // "About the same every event": map every observation to exposure 1
        // BEFORE anything else, so the frozen engine's median-of-rates is
        // the median of per-event depletions and the sell-out lift below
        // raises a ran-out day to the median per-event usage — see
        // `per_event_basis.dart`. The stored evidence keeps the real
        // exposures; this mapping exists only on the way into the engine.
        final engineExposure = isPerEvent
            ? perEventEngineExposure
            : inputs.upcomingExposure;
        // A sell-out records a LOWER BOUND on demand. Fix that here, on the
        // way into the frozen engine, so a sell-out can only ever raise the
        // estimate — see `stockout_adjustment.dart` for the rule. The stored
        // evidence below is untouched: it keeps the real confirmed numbers.
        final adjustment = adjustForSellouts(
          isPerEvent ? perEventObservations(rawObservations) : rawObservations,
        );
        // Outside the envelope the frozen engine's rate × exposure product
        // wraps int64 and it would return a plausible-looking but wrong
        // number. Report no forecast instead: a blank line with the reason
        // is honest, a wrong load quantity is not. A per-event line cannot
        // leave the envelope — at exposure 1 the schema caps bound every
        // product (see `per_event_basis.dart`), and this check's per-person
        // limit would wrongly refuse large legitimate per-event depletions.
        if (!isPerEvent &&
            _exceedsEngineEnvelope(
              adjustment.observations,
              inputs.upcomingExposure,
            )) {
          lines.add(
            ForecastSnapshotLineDraft(
              itemId: ItemId(input.itemId),
              packSizeMicros: input.packSizeMicros,
              onHandMicros: input.onHandMicros,
              confirmedInboundMicros: input.confirmedInboundMicros,
              demandBasis: input.demandBasis,
              servesPerUnitMicros: input.servesPerUnitMicros,
              perPersonNumerator: input.perPersonNumerator,
              perPersonDenominator: input.perPersonDenominator,
              perEventBaselineMicros: input.perEventBaselineMicros,
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
          upcomingExposure: engineExposure,
          observations: adjustment.observations,
          policy: inputs.policy,
          packSize: Quantity.fromMicros(input.packSizeMicros),
          usableOnHand: Quantity.fromMicros(max(0, input.onHandMicros)),
        );
        // A per-event estimate ignores attendance on purpose — so when this
        // event dwarfs everything the estimate was learned from, say so on
        // the line (warning only, no invented scaling). Checked against the
        // REAL stored exposures, not the mapped exposure-1 observations.
        final suppliesJump =
            isPerEvent &&
            perEventSuppliesJump(
              upcomingExposure: inputs.upcomingExposure,
              observedExposures: [for (final e in input.evidence) e.exposure],
            );
        if (adjustment.adjusted) {
          selloutAdjustedLines++;
          if (adjustment.kind == StockoutAdjustmentKind.everyDaySoldOut) {
            everyDaySoldOutLines++;
          }
        }
        // No confirmed outcomes yet? The engine correctly refuses to
        // forecast. If the item answered its cold-start question — "1
        // serves N", "N per person", or the per-event "how many do you
        // usually bring" — we can still hand the owner a starting number:
        // clearly labelled, in its own columns, never mistakable for
        // history.
        // `evidence.isEmpty` is belt-and-braces next to the grade check: SQL
        // caps every stored exposure at >= 1, so the engine only ever grades
        // an empty history as insufficient — but a baseline beside real
        // evidence would be rejected by the validator, and generation must
        // not be able to build a snapshot its own write path refuses.
        final baseline =
            engineLine.evidenceGrade == EvidenceGrade.insufficientData &&
                input.evidence.isEmpty
            ? (isPerEvent
                  ? estimateFromPerEventBaseline(
                      perEventBaselineMicros: input.perEventBaselineMicros,
                      policy: inputs.policy,
                      packSizeMicros: input.packSizeMicros,
                      usableOnHandMicros: max(0, input.onHandMicros),
                      confirmedInboundMicros: input.confirmedInboundMicros,
                    )
                  : estimateFromServesPerUnit(
                          expectedAttendance: inputs.upcomingExposure,
                          servesPerUnitMicros: input.servesPerUnitMicros,
                          policy: inputs.policy,
                          packSizeMicros: input.packSizeMicros,
                          usableOnHandMicros: max(0, input.onHandMicros),
                          confirmedInboundMicros: input.confirmedInboundMicros,
                        ) ??
                        estimateFromPerPersonRatio(
                          expectedAttendance: inputs.upcomingExposure,
                          numerator: input.perPersonNumerator,
                          denominator: input.perPersonDenominator,
                          policy: inputs.policy,
                          packSizeMicros: input.packSizeMicros,
                          usableOnHandMicros: max(0, input.onHandMicros),
                          confirmedInboundMicros: input.confirmedInboundMicros,
                        ))
            : null;
        lines.add(
          ForecastSnapshotLineDraft(
            itemId: ItemId(input.itemId),
            packSizeMicros: input.packSizeMicros,
            onHandMicros: input.onHandMicros,
            confirmedInboundMicros: input.confirmedInboundMicros,
            demandBasis: input.demandBasis,
            servesPerUnitMicros: input.servesPerUnitMicros,
            perPersonNumerator: input.perPersonNumerator,
            perPersonDenominator: input.perPersonDenominator,
            perEventBaselineMicros: input.perEventBaselineMicros,
            expectedUseMicros: engineLine.expectedUse?.micros,
            plannedMicros: engineLine.plannedQuantity?.micros,
            loadMicros: engineLine.roundedLoadQuantity?.micros,
            acquireMicros: engineLine.acquireQuantity?.micros,
            baselineServesPerUnitMicros: baseline?.servesPerUnitMicros,
            baselinePerPersonNumerator: baseline?.perPersonNumerator,
            baselinePerPersonDenominator: baseline?.perPersonDenominator,
            baselinePerEventMicros: baseline?.perEventMicros,
            baselineExpectedUseMicros: baseline?.expectedUseMicros,
            baselinePlannedMicros: baseline?.plannedMicros,
            baselineLoadMicros: baseline?.loadMicros,
            baselineAcquireMicros: baseline?.acquireMicros,
            evidenceGrade: engineLine.evidenceGrade,
            // The engine's strings verbatim first — including its own
            // lower-bound note — then, in plain language, what was done
            // about it. A baseline and a sell-out adjustment are mutually
            // exclusive: one needs no evidence, the other needs some.
            warnings: [
              ...engineLine.warnings,
              if (adjustment.warning != null) adjustment.warning!,
              if (suppliesJump) perEventSuppliesJumpWarning,
              if (baseline != null) baseline.warning,
            ],
            evidence: input.evidence,
          ),
        );
      }
      final assumptions = <String, Object?>{
        'reserve_percent': inputs.policy.reservePercent,
        'history_window': inputs.historyWindow,
        'rate_normalization': 'per_exposure_median',
        'exposure_label': exposureLabel,
        // How sell-out days were treated, recorded so a stored forecast can
        // still explain its own numbers (§6.6 release contract).
        'stockout_rule': selloutRuleTag,
        'stockout_rule_note': selloutRuleNote,
        'stockout_adjusted_lines': selloutAdjustedLines,
        'stockout_all_sellout_lines': everyDaySoldOutLines,
        // How "about the same every event" items were treated (method v3);
        // each line also stores its own demand_basis.
        'per_event_rule': perEventRuleTag,
        'per_event_rule_note': perEventRuleNote,
        'per_event_lines': perEventLines,
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
    // Folder demand bases, for the one effective-basis resolution below.
    // Archived folders never hold items (archiving unfiles them in the same
    // transaction), so live folders are the whole population.
    final folderBases = {
      for (final folder in await _db.folderDao.live())
        folder.id: DemandBasis.fromDb(folder.demandBasis),
    };
    final lines = <SnapshotLineInput>[];
    for (final plannedItem in planned) {
      final item = await _db.itemDao.byId(plannedItem.itemId);
      if (item == null) continue;
      final history = await _db.forecastDao.labelHistory(
        item.id,
        historyWindow: historyWindow,
      );
      final onHand = await _db.ledgerDao.onHandMicros(item.id);
      // THE effective-basis rule, called — never re-derived (§ contract).
      final basis = effectiveDemandBasis(
        itemOverride: DemandBasis.fromDbNullable(item.demandBasis),
        folderBasis: item.folderId == null ? null : folderBases[item.folderId],
      );
      final isPerEvent = basis == DemandBasis.perEvent;
      lines.add(
        SnapshotLineInput(
          itemId: item.id,
          packSizeMicros: item.packSizeMicros,
          onHandMicros: onHand,
          demandBasis: basis,
          // Only the inputs MATERIAL under this basis are carried (and
          // hashed): a per-event line ignores serves/ratio, a per-person
          // line ignores the usual-amount — so editing the irrelevant one
          // never reads as "inputs changed".
          servesPerUnitMicros: isPerEvent ? null : item.servesPerUnitMicros,
          perPersonNumerator: isPerEvent ? null : item.perPersonNumerator,
          perPersonDenominator: isPerEvent ? null : item.perPersonDenominator,
          perEventBaselineMicros: isPerEvent
              ? item.perEventBaselineMicros
              : null,
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
            // Rows stored before v3 carry NULL: they were per-person.
            demandBasis:
                DemandBasis.fromDbNullable(line.demandBasis) ??
                DemandBasis.perPerson,
            expectedUseMicros: line.expectedUseMicros,
            plannedMicros: line.plannedMicros,
            loadMicros: line.loadMicros,
            acquireMicros: line.acquireMicros,
            baselineServesPerUnitMicros: line.baselineServesPerUnitMicros,
            baselinePerPersonNumerator: line.baselinePerPersonNumerator,
            baselinePerPersonDenominator: line.baselinePerPersonDenominator,
            baselinePerEventMicros: line.baselinePerEventMicros,
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

  /// Whether scaling these observations to [upcomingExposure] would leave
  /// the range the frozen engine can compute in.
  ///
  /// The engine normalises each observation to `depletion × 1e6 ÷ exposure`
  /// and multiplies the median by the upcoming exposure. Both the schema and
  /// the validator accept a depletion of 1e12 micros against an exposure of
  /// 1 — a plausible typo — and that product overflows int64 silently. The
  /// median is bounded by the largest observed rate, so bounding that is
  /// enough and needs no copy of the engine's median.
  ///
  /// Runs on the observations the engine will actually see, i.e. AFTER the
  /// sell-out adjustment, so a raised rate can never slip past the bound.
  static bool _exceedsEngineEnvelope(
    List<ConfirmedObservation> observations,
    int upcomingExposure,
  ) {
    if (upcomingExposure <= 0) return false; // the engine rejects this itself
    final limit = Quantity.maxMicros ~/ upcomingExposure;
    for (final o in observations) {
      if (o.exposure <= 0) continue; // filtered by the engine
      if (rateOf(o) > limit) return true;
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
