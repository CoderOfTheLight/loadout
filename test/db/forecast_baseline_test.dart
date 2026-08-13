/// §11.1/§6.6, schema v2: the no-history "1 serves N" baseline.
///
/// The point of these tests is the boundary, not the arithmetic (that is
/// `test/domain/baseline_estimator_test.dart`): a baseline is a PLAN. It may
/// be shown, stored and overridden; it may never be read back as a confirmed
/// outcome, and the §4.3 label query must stay structurally blind to it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/data/db/daos/forecast_dao.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/forecasting/application/forecast_service.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/forecasting/domain/snapshot.dart';
import 'package:loadout/features/forecasting/domain/snapshot_inputs.dart';
import 'package:loadout/features/settings/application/settings_service.dart';

import 'fixtures.dart';
import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;
  late DriftForecastService service;

  setUp(() {
    h = WritePathHarness();
    service = DriftForecastService(
      h.db,
      h.applier,
      DriftSettingsService(h.db, clock: h.clock),
      idGenerator: h.ids,
      clock: h.clock,
    );
  });

  tearDown(() => h.close());

  Future<ForecastSnapshotView> generate(String eventId) async =>
      (await service.generateSnapshot(
        eventId,
      )).fold((v) => v, (e) => fail('${e.code}: ${e.message}'));

  group('a first-ever event', () {
    test(
      'with "1 serves 4" gets a labelled estimate instead of nothing',
      () async {
        final itemId = await h.createItem(
          name: 'Pizza',
          servesPerUnitMicros: 4000000,
        );
        final eventId = await h.createEvent(
          name: 'School fete',
          plannedExposure: 100,
          plannedItemIds: [itemId],
        );

        final line = (await generate(eventId)).lines.single;

        // The engine's own outputs stay empty: it has seen nothing.
        expect(line.expectedUseMicros, isNull);
        expect(line.loadMicros, isNull);
        expect(line.acquireMicros, isNull);
        expect(line.evidenceGrade, EvidenceGrade.insufficientData);
        expect(line.evidence, isEmpty);

        // The baseline sits alongside it, clearly its own thing.
        expect(line.basis, ForecastBasis.servesBaseline);
        expect(line.isBaseline, isTrue);
        expect(line.baselineServesPerUnitMicros, 4000000);
        expect(line.baselineExpectedUseMicros, 25000000);
        expect(line.baselinePlannedMicros, 27500000); // balanced: +10%
        expect(line.baselineLoadMicros, 28000000);
        expect(line.baselineAcquireMicros, 28000000);
        expect(line.suggestedLoadMicros, 28000000);
        expect(line.effectiveLoadMicros, 28000000);

        // And it says out loud what it is.
        expect(
          line.warnings,
          contains('No comparable confirmed outcomes. Create a baseline plan.'),
        );
        final estimate = line.warnings.last;
        expect(estimate, contains('1 serves 4'));
        expect(estimate, contains('not from confirmed outcomes'));
      },
    );

    test('without "1 serves N" still forecasts nothing, and says so', () async {
      final itemId = await h.createItem(name: 'Napkins');
      final eventId = await h.createEvent(
        name: 'School fete',
        plannedExposure: 100,
        plannedItemIds: [itemId],
      );

      final line = (await generate(eventId)).lines.single;
      expect(line.basis, ForecastBasis.insufficientData);
      expect(line.isBaseline, isFalse);
      expect(line.baselineLoadMicros, isNull);
      expect(line.suggestedLoadMicros, isNull);
      expect(line.warnings, hasLength(1));
    });

    test('an opening count is deducted from what to buy', () async {
      final itemId = await h.createItem(
        name: 'Pizza',
        servesPerUnitMicros: 4000000,
        openingMicros: 10000000,
      );
      final eventId = await h.createEvent(
        name: 'School fete',
        plannedExposure: 100,
        plannedItemIds: [itemId],
      );
      final line = (await generate(eventId)).lines.single;
      expect(line.onHandMicros, 10000000);
      expect(line.baselineLoadMicros, 28000000);
      expect(line.baselineAcquireMicros, 18000000);
    });
  });

  group('a baseline is never history', () {
    test('the §4.3 label query returns nothing after one is stored', () async {
      final itemId = await h.createItem(
        name: 'Pizza',
        servesPerUnitMicros: 4000000,
      );
      final eventId = await h.createEvent(
        name: 'School fete',
        plannedExposure: 100,
        plannedItemIds: [itemId],
      );
      final view = await generate(eventId);
      expect(view.lines.single.isBaseline, isTrue);

      // The row really is on disk...
      final stored = await h.db
          .customSelect(
            'SELECT COUNT(*) AS c FROM forecast_lines '
            'WHERE baseline_load_micros IS NOT NULL',
          )
          .getSingle();
      expect(stored.read<int>('c'), 1);

      // ...and the only label source cannot see it.
      expect(
        await h.db.forecastDao.labelHistory(itemId, historyWindow: 12),
        isEmpty,
        reason: 'confirmed closeouts are the only history',
      );
    });

    test('the label query SQL cannot even name the new v2 columns', () {
      // Structural, not behavioural: nothing downstream can accidentally
      // teach it about baselines or serves-per-unit.
      const sql = ForecastDao.labelQuerySql;
      for (final forbidden in ['baseline', 'serves_per_unit', 'items']) {
        expect(
          sql.contains(forbidden),
          isFalse,
          reason: 'the label query must not read $forbidden',
        );
      }
    });

    test(
      'one confirmed closeout replaces the baseline with a real forecast',
      () async {
        final itemId = await h.createItem(
          name: 'Pizza',
          servesPerUnitMicros: 4000000,
        );
        // Event 1: no history → baseline.
        final first = await h.createEvent(
          name: 'Fete',
          scheduledDate: '2026-07-01',
          plannedExposure: 100,
          plannedItemIds: [itemId],
        );
        expect((await generate(first)).lines.single.isBaseline, isTrue);

        // Close it out: 20 pizzas actually went, not the 25 we guessed.
        await h.ok(ActivateEvent(EventId(first)));
        await h.ok(
          RecordCloseout(
            eventId: EventId(first),
            confirmedExposure: 100,
            lines: [
              CloseoutLineDraft(
                itemId: ItemId(itemId),
                depletion: Quantity.whole(20),
              ),
            ],
          ),
        );

        // Event 2: the engine now owns the number and the baseline is gone.
        final second = await h.createEvent(
          name: 'Fete 2',
          scheduledDate: '2026-08-01',
          plannedExposure: 100,
          plannedItemIds: [itemId],
        );
        final line = (await generate(second)).lines.single;
        expect(line.basis, ForecastBasis.singleEvent);
        expect(line.isBaseline, isFalse);
        expect(line.baselineLoadMicros, isNull);
        expect(
          line.expectedUseMicros,
          20000000,
          reason: 'the confirmed outcome, not the "1 serves 4" guess',
        );
        expect(line.evidence.single.depletionMicros, 20000000);
      },
    );

    test('the accuracy review labels a baseline as a baseline', () async {
      final itemId = await h.createItem(
        name: 'Pizza',
        servesPerUnitMicros: 4000000,
      );
      final eventId = await h.createEvent(
        name: 'Fete',
        plannedExposure: 100,
        plannedItemIds: [itemId],
      );
      await generate(eventId);
      await h.ok(ActivateEvent(EventId(eventId)));
      await h.ok(
        RecordCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 100,
          lines: [
            CloseoutLineDraft(
              itemId: ItemId(itemId),
              depletion: Quantity.whole(20),
            ),
          ],
        ),
      );

      final review = await service.accuracyReview(eventId);
      final line = review.lines.single;
      expect(line.basis, ForecastBasis.servesBaseline);
      expect(line.expectedUseMicros, 25000000);
      expect(line.actualDepletionMicros, 20000000);
      expect(line.varianceMicros, -5000000, reason: 'we over-estimated by 5');
    });
  });

  group('inputs hash', () {
    test('changing "1 serves N" makes the stored snapshot stale', () async {
      final itemId = await h.createItem(
        name: 'Pizza',
        servesPerUnitMicros: 4000000,
      );
      final eventId = await h.createEvent(
        name: 'Fete',
        plannedExposure: 100,
        plannedItemIds: [itemId],
      );
      await generate(eventId);
      expect(await service.isStale(eventId), isFalse);

      await h.ok(
        UpdateItem(itemId: ItemId(itemId), servesPerUnit: Quantity.whole(8)),
      );
      expect(await service.isStale(eventId), isTrue);

      final line = (await generate(eventId)).lines.single;
      expect(line.baselineExpectedUseMicros, 13000000, reason: 'ceil(100/8)');
    });

    test('an item without serves-per-unit hashes exactly as it did in v1', () {
      // The v2 field is appended only when present, so every schema-v1
      // snapshot keeps the hash it was stored with and does not read as
      // stale after the upgrade.
      const withoutField = SnapshotInputs(
        policy: PlanningPolicy.balanced,
        upcomingExposure: 100,
        historyWindow: 12,
        lines: [
          SnapshotLineInput(
            itemId: 'I1',
            packSizeMicros: 1000000,
            onHandMicros: 0,
            evidence: [],
          ),
        ],
      );
      expect(
        canonicalInputs(withoutField),
        'direct_median|1|balanced|100|12\nI1|1000000|0|0',
      );
      const withField = SnapshotInputs(
        policy: PlanningPolicy.balanced,
        upcomingExposure: 100,
        historyWindow: 12,
        lines: [
          SnapshotLineInput(
            itemId: 'I1',
            packSizeMicros: 1000000,
            onHandMicros: 0,
            servesPerUnitMicros: 4000000,
            evidence: [],
          ),
        ],
      );
      expect(
        canonicalInputs(withField),
        'direct_median|1|balanced|100|12\nI1|1000000|0|0|s=4000000',
      );
      expect(
        computeInputsHash(withField) == computeInputsHash(withoutField),
        isFalse,
      );
    });
  });

  group('the validator refuses dishonest baselines', () {
    Future<DomainError> reject(ForecastSnapshotLineDraft line) async {
      final itemId = await h.createItem(name: 'Pizza');
      final eventId = await h.createEvent(
        name: 'Fete',
        plannedExposure: 100,
        plannedItemIds: [itemId],
      );
      final rebound = ForecastSnapshotLineDraft(
        itemId: ItemId(itemId),
        packSizeMicros: line.packSizeMicros,
        onHandMicros: line.onHandMicros,
        expectedUseMicros: line.expectedUseMicros,
        plannedMicros: line.plannedMicros,
        loadMicros: line.loadMicros,
        acquireMicros: line.acquireMicros,
        baselineServesPerUnitMicros: line.baselineServesPerUnitMicros,
        baselineExpectedUseMicros: line.baselineExpectedUseMicros,
        baselinePlannedMicros: line.baselinePlannedMicros,
        baselineLoadMicros: line.baselineLoadMicros,
        baselineAcquireMicros: line.baselineAcquireMicros,
        evidenceGrade: line.evidenceGrade,
        evidence: line.evidence,
      );
      final inputs = SnapshotInputs(
        policy: PlanningPolicy.balanced,
        upcomingExposure: 100,
        historyWindow: 12,
        lines: [
          SnapshotLineInput(
            itemId: itemId,
            packSizeMicros: rebound.packSizeMicros,
            onHandMicros: rebound.onHandMicros,
            evidence: rebound.evidence,
          ),
        ],
      );
      return h.err(
        SaveForecastSnapshot(
          ForecastSnapshotDraft(
            eventId: EventId(eventId),
            policy: PlanningPolicy.balanced,
            upcomingExposure: 100,
            historyWindow: 12,
            inputsHash: computeInputsHash(inputs),
            assumptionsJson: '{}',
            lines: [rebound],
          ),
        ),
      );
    }

    test('a half-written baseline', () async {
      final error = await reject(
        ForecastSnapshotLineDraft(
          itemId: ItemId(tid('I1')),
          packSizeMicros: 1000000,
          onHandMicros: 0,
          baselineServesPerUnitMicros: 4000000,
          baselineLoadMicros: 28000000,
          evidenceGrade: EvidenceGrade.insufficientData,
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('every baseline field or none'));
    });

    test('a baseline on a line the engine DID forecast', () async {
      final error = await reject(
        ForecastSnapshotLineDraft(
          itemId: ItemId(tid('I1')),
          packSizeMicros: 1000000,
          onHandMicros: 0,
          expectedUseMicros: 5000000,
          plannedMicros: 5500000,
          loadMicros: 6000000,
          acquireMicros: 6000000,
          baselineServesPerUnitMicros: 4000000,
          baselineExpectedUseMicros: 25000000,
          baselinePlannedMicros: 27500000,
          baselineLoadMicros: 28000000,
          baselineAcquireMicros: 28000000,
          evidenceGrade: EvidenceGrade.singleEvent,
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('no confirmed evidence'));
    });

    test('an out-of-range serves-per-unit', () async {
      final error = await reject(
        ForecastSnapshotLineDraft(
          itemId: ItemId(tid('I1')),
          packSizeMicros: 1000000,
          onHandMicros: 0,
          baselineServesPerUnitMicros: 0,
          baselineExpectedUseMicros: 25000000,
          baselinePlannedMicros: 27500000,
          baselineLoadMicros: 28000000,
          baselineAcquireMicros: 28000000,
          evidenceGrade: EvidenceGrade.insufficientData,
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('out of range'));
    });
  });
}
