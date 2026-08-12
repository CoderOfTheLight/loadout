/// §11.1 family F (forecast persistence, §6.6): snapshot generation through
/// the FROZEN engine, tamper-checked inputs_hash, planned|active-only
/// saves, append-only regeneration, staleness, override rules (reason >= 3,
/// lines never mutated, NULL-load revert), and the derived accuracy review.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/forecasting/application/forecast_service.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/forecasting/domain/snapshot.dart';
import 'package:loadout/features/forecasting/domain/snapshot_inputs.dart';
import 'package:loadout/features/settings/application/settings_service.dart';

import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;
  late DriftForecastService service;
  late String itemId;

  setUp(() async {
    h = WritePathHarness();
    service = DriftForecastService(
      h.db,
      h.applier,
      DriftSettingsService(h.db, clock: h.clock),
      idGenerator: h.ids,
      clock: h.clock,
    );
    itemId = await h.createItem(name: 'Tortillas', packMicros: 12000000);
  });

  tearDown(() => h.close());

  /// Creates, activates, and closes out one historical event.
  Future<void> closedEvent({
    required String name,
    required String date,
    required int exposure,
    required int depletionMicros,
    bool stockout = false,
  }) async {
    final eventId = await h.createEvent(
      name: name,
      scheduledDate: date,
      plannedExposure: exposure,
      plannedItemIds: [itemId],
    );
    await h.ok(ActivateEvent(EventId(eventId)));
    await h.ok(
      RecordCloseout(
        eventId: EventId(eventId),
        confirmedExposure: exposure,
        lines: [
          CloseoutLineDraft(
            itemId: ItemId(itemId),
            depletion: Quantity.fromMicros(depletionMicros),
            stockout: stockout,
          ),
        ],
      ),
    );
  }

  Future<String> upcomingEvent({int exposure = 150}) => h.createEvent(
    name: 'Upcoming market',
    scheduledDate: '2026-09-01',
    plannedExposure: exposure,
    plannedItemIds: [itemId],
  );

  group('generateSnapshot (frozen engine, §6.6)', () {
    test(
      'history too large to scale reports no forecast, not a wrapped one',
      () async {
        // A plausible typo: a whole event's depletion recorded against an
        // attendance of 1. Scaling that rate to the upcoming event overflows
        // the engine's int64 product.
        await closedEvent(
          name: 'Typo night',
          date: '2026-07-01',
          exposure: 1,
          depletionMicros: 10000000000, // 10 000 g
        );
        final eventId = await upcomingEvent(exposure: 2000);

        final view = (await service.generateSnapshot(
          eventId,
        )).fold((v) => v, (e) => fail('${e.code}: ${e.message}'));

        final line = view.lines.single;
        expect(line.expectedUseMicros, isNull);
        expect(line.loadMicros, isNull);
        expect(line.acquireMicros, isNull);
        expect(line.evidenceGrade, EvidenceGrade.insufficientData);
        expect(line.warnings.single, contains('too large to scale'));
      },
    );

    test('persists header, lines, and evidence value-copies that match the '
        'engine and label query exactly', () async {
      await closedEvent(
        name: 'July 1',
        date: '2026-07-01',
        exposure: 100,
        depletionMicros: 30000000,
        stockout: true,
      );
      await closedEvent(
        name: 'July 8',
        date: '2026-07-08',
        exposure: 90,
        depletionMicros: 22000000,
      );
      // The two closeouts consumed 52; land derived on-hand at exactly 10.
      await h.receive(itemId, 62000000);
      final eventId = await upcomingEvent();

      final result = await service.generateSnapshot(eventId);
      final view = result.fold(
        (v) => v,
        (e) => fail('${e.code}: ${e.message}'),
      );

      expect(view.method, 'direct_median');
      expect(view.methodVersion, 1);
      expect(view.policy, PlanningPolicy.balanced);
      expect(view.upcomingExposure, 150);
      expect(view.historyWindow, 12);
      expect(view.assumptionsJson, contains('"reserve_percent":10'));
      expect(view.assumptionsJson, contains('"exposure_label":"attendance"'));

      final line = view.lines.single;
      expect(line.itemId as String, itemId);
      expect(line.onHandMicros, 10000000);
      expect(line.confirmedInboundMicros, 0);

      // Evidence in label-query order: newest scheduled_date first.
      expect(line.evidence, hasLength(2));
      expect(line.evidence[0].exposure, 90);
      expect(line.evidence[0].depletionMicros, 22000000);
      expect(line.evidence[1].exposure, 100);
      expect(line.evidence[1].stockout, isTrue);

      // The frozen engine is the only arithmetic source: replaying the
      // stored inputs must reproduce the stored outputs byte-for-byte.
      final engineLine = const DeterministicForecastEngine().forecastDirect(
        upcomingExposure: 150,
        observations: [
          for (final e in line.evidence)
            ConfirmedObservation(
              exposure: e.exposure,
              depletion: Quantity.fromMicros(e.depletionMicros),
              stockout: e.stockout,
              approximate: e.approximate,
            ),
        ],
        policy: PlanningPolicy.balanced,
        packSize: Quantity.fromMicros(12000000),
        usableOnHand: Quantity.fromMicros(10000000),
      );
      expect(line.expectedUseMicros, engineLine.expectedUse!.micros);
      expect(line.plannedMicros, engineLine.plannedQuantity!.micros);
      expect(line.loadMicros, engineLine.roundedLoadQuantity!.micros);
      expect(line.acquireMicros, engineLine.acquireQuantity!.micros);
      expect(line.evidenceGrade, engineLine.evidenceGrade);
      expect(line.warnings, engineLine.warnings);

      // Stored hash matches the canonical recomputation.
      expect(
        view.inputsHash,
        computeInputsHash(
          SnapshotInputs(
            policy: PlanningPolicy.balanced,
            upcomingExposure: 150,
            historyWindow: 12,
            lines: [
              SnapshotLineInput(
                itemId: itemId,
                packSizeMicros: 12000000,
                onHandMicros: 10000000,
                evidence: [
                  for (final e in line.evidence)
                    EvidenceInput(
                      closeoutId: e.closeoutId as String,
                      sourceEventId: e.sourceEventId as String,
                      exposure: e.exposure,
                      depletionMicros: e.depletionMicros,
                      stockout: e.stockout,
                      approximate: e.approximate,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    });

    test(
      'regenerating appends a second snapshot; nothing is rewritten',
      () async {
        final eventId = await upcomingEvent();
        await service.generateSnapshot(eventId);
        await h.receive(itemId, 5000000);
        await service.generateSnapshot(eventId);
        expect(await h.count('forecast_snapshots'), 2);
        final latest = await h.db.forecastDao.latestSnapshotForEvent(eventId);
        final lines = await h.db.forecastDao.linesForSnapshot(latest!.id);
        expect(lines.single.onHandMicros, 5000000);
      },
    );

    test('requires a planned exposure', () async {
      final eventId = await h.createEvent(
        name: 'No exposure yet',
        plannedItemIds: [itemId],
      );
      final result = await service.generateSnapshot(eventId);
      result.fold(
        (_) => fail('must not generate without exposure'),
        (error) => expect(error, isA<ValidationError>()),
      );
    });
  });

  group('SaveForecastSnapshot validation', () {
    test('tampered inputs_hash rejected, nothing written', () async {
      final eventId = await upcomingEvent();
      final error = await h.err(
        SaveForecastSnapshot(
          ForecastSnapshotDraft(
            eventId: EventId(eventId),
            policy: PlanningPolicy.balanced,
            upcomingExposure: 150,
            historyWindow: 12,
            inputsHash: 'a' * 64, // valid shape, wrong value
            assumptionsJson: '{}',
            lines: [
              ForecastSnapshotLineDraft(
                itemId: ItemId(itemId),
                packSizeMicros: 12000000,
                onHandMicros: 0,
                evidenceGrade: EvidenceGrade.insufficientData,
              ),
            ],
          ),
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('hash'));
      expect(await h.count('forecast_snapshots'), 0);
    });

    test('snapshots allowed for planned|active events only', () async {
      await closedEvent(
        name: 'Done',
        date: '2026-07-01',
        exposure: 100,
        depletionMicros: 1000000,
      );
      final closed = (await h.db.eventDao.watchAll().first).singleWhere(
        (e) => e.status == 'closed',
      );
      final result = await service.generateSnapshot(closed.id);
      result.fold(
        (_) => fail('must not snapshot a closed event'),
        (error) => expect(error, isA<ValidationError>()),
      );

      // Active events are fine.
      final activeId = await upcomingEvent();
      await h.ok(ActivateEvent(EventId(activeId)));
      final active = await service.generateSnapshot(activeId);
      active.fold((_) {}, (e) => fail('active event must be snapshotable'));
    });
  });

  group('overrides (append-only, §4)', () {
    late String eventId;
    late String snapshotId;

    setUp(() async {
      eventId = await upcomingEvent();
      final result = await service.generateSnapshot(eventId);
      snapshotId = result.fold((v) => v.id as String, (e) => fail(e.message));
    });

    test('reason must be >= 3 chars; lines are never mutated', () async {
      final tooShort = await service.setOverride(
        snapshotId: snapshotId,
        itemId: itemId,
        load: Quantity.whole(48),
        reason: 'no',
      );
      tooShort.fold(
        (_) => fail('2-char reason must be rejected'),
        (error) => expect(error, isA<ValidationError>()),
      );

      final linesBefore = await h.db.forecastDao.linesForSnapshot(snapshotId);
      final ok = await service.setOverride(
        snapshotId: snapshotId,
        itemId: itemId,
        load: Quantity.whole(48),
        reason: 'baseline',
      );
      ok.fold((_) {}, (e) => fail(e.message));
      expect(
        await h.db.forecastDao.linesForSnapshot(snapshotId),
        linesBefore,
        reason: 'overrides never mutate snapshot lines',
      );
      expect(await h.count('forecast_overrides'), 1);
    });

    test('latest override wins; NULL-load override reverts display', () async {
      await service.setOverride(
        snapshotId: snapshotId,
        itemId: itemId,
        load: Quantity.whole(48),
        reason: 'baseline',
      );
      var view = (await service.watchLatestSnapshot(eventId).first)!;
      expect(view.lines.single.isOverridden, isTrue);
      expect(view.lines.single.effectiveLoadMicros, 48000000);

      final cleared = await service.clearOverride(
        snapshotId: snapshotId,
        itemId: itemId,
        reason: 'back to engine',
      );
      cleared.fold((_) {}, (e) => fail(e.message));
      view = (await service.watchLatestSnapshot(eventId).first)!;
      final line = view.lines.single;
      expect(line.isOverridden, isFalse);
      expect(
        line.effectiveLoadMicros,
        line.loadMicros,
        reason: 'NULL-load override reverts to the engine value',
      );
      // Append-only: both override rows still exist.
      expect(await h.count('forecast_overrides'), 2);
    });

    test('override requires an existing snapshot line', () async {
      final other = await h.createItem(name: 'Napkins');
      final result = await service.setOverride(
        snapshotId: snapshotId,
        itemId: other,
        load: Quantity.whole(1),
        reason: 'baseline',
      );
      result.fold(
        (_) => fail('line does not exist'),
        (error) => expect(error, isA<NotFoundError>()),
      );
    });
  });

  group('staleness (§6.6)', () {
    test('fresh snapshot is not stale; input changes flip it; regenerating '
        'clears it', () async {
      final eventId = await upcomingEvent();
      await service.generateSnapshot(eventId);
      expect(await service.isStale(eventId), isFalse);

      await h.receive(itemId, 5000000); // on-hand changed
      expect(await service.isStale(eventId), isTrue);

      await service.generateSnapshot(eventId);
      expect(await service.isStale(eventId), isFalse);

      // Exposure change is material too.
      await h.ok(UpdateEvent(eventId: EventId(eventId), plannedExposure: 151));
      expect(await service.isStale(eventId), isTrue);
    });

    test('no snapshot yet → not stale (Generate, not Refresh)', () async {
      final eventId = await upcomingEvent();
      expect(await service.isStale(eventId), isFalse);
    });
  });

  group('accuracy review (actuals derived, never stored)', () {
    test('joins the latest snapshot to the latest closeout revision', () async {
      await closedEvent(
        name: 'History',
        date: '2026-07-01',
        exposure: 100,
        depletionMicros: 30000000,
      );
      final eventId = await upcomingEvent(exposure: 100);
      final generated = await service.generateSnapshot(eventId);
      final expectedUse = generated.fold(
        (v) => v.lines.single.expectedUseMicros!,
        (e) => fail(e.message),
      );
      await h.ok(ActivateEvent(EventId(eventId)));
      await h.ok(
        RecordCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 95,
          lines: [
            CloseoutLineDraft(
              itemId: ItemId(itemId),
              depletion: Quantity.fromMicros(27000000),
              stockout: true,
            ),
          ],
        ),
      );
      final review = await service.accuracyReview(eventId);
      expect(review.confirmedExposure, 95);
      expect(review.upcomingExposure, 100);
      final line = review.lines.single;
      expect(line.expectedUseMicros, expectedUse);
      expect(line.actualDepletionMicros, 27000000);
      expect(line.varianceMicros, 27000000 - expectedUse);
      expect(line.stockout, isTrue);
    });
  });
}
