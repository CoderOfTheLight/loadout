/// The per-event demand basis end to end (v3, method version 3): the soap
/// example that motivates the whole feature, the per-event cold start, the
/// stored basis on every line, staleness when the basis flips, and the
/// §4.3 label query staying structurally blind to all of it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/unit_ratio.dart';
import 'package:loadout/data/db/daos/forecast_dao.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/forecasting/application/forecast_service.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/forecasting/domain/snapshot.dart';
import 'package:loadout/features/forecasting/presentation/forecast_presentation_support.dart';
import 'package:loadout/features/settings/application/settings_service.dart';

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

  /// The folder id of the seeded per-event starter, "Cleaning & setup".
  Future<String> cleaningFolderId() async => (await h.db.folderDao.live())
      .firstWhere((f) => f.demandBasis == 'per_event')
      .id;

  Future<void> closedEvent({
    required String itemId,
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

  group('the soap example — the literal numbers from the proposal', () {
    test('2 soap at three 200-person events forecasts ~2-3 for a 2000-person '
        'event, never 17', () async {
      final folder = await cleaningFolderId();
      final soap = await h.createItem(name: 'Dish soap');
      await h.ok(
        MoveItemToFolder(itemId: ItemId(soap), folderId: FolderId(folder)),
      );
      for (final (i, date) in [
        '2026-05-01',
        '2026-06-01',
        '2026-07-01',
      ].indexed) {
        await closedEvent(
          itemId: soap,
          name: 'Event $i',
          date: date,
          exposure: 200,
          depletionMicros: 2000000,
        );
      }
      final big = await h.createEvent(
        name: 'The big one',
        scheduledDate: '2026-09-01',
        plannedExposure: 2000,
        plannedItemIds: [soap],
      );

      final view = await generate(big);
      final line = view.lines.single;

      expect(view.methodVersion, 3);
      expect(line.demandBasis, DemandBasis.perEvent);
      expect(line.expectedUseMicros, 2000000, reason: 'the median: 2 soap');
      expect(
        line.loadMicros,
        3000000,
        reason: 'the usual +10 % reserve rounded up to whole things: 3',
      );
      expect(line.evidenceGrade, EvidenceGrade.observedRange);
      // Never the per-person arithmetic: 2/200 × 2000 would demand 20 — and
      // the proposal's dreaded 17 must be nowhere in sight either.
      expect(line.loadMicros, isNot(20000000));
      expect(line.loadMicros, isNot(17000000));
      expect(line.loadMicros! < 17000000, isTrue);

      // The stored evidence keeps the REAL exposures — the mapping to
      // exposure 1 lives only on the way into the engine.
      expect([for (final e in line.evidence) e.exposure], [200, 200, 200]);
      expect(
        [for (final e in line.evidence) e.depletionMicros],
        [2000000, 2000000, 2000000],
      );

      // And the line explains itself in the owner's words — quoting what
      // was used and NEVER the headcount it was used at, which is the whole
      // claim the per-event basis makes.
      final words = forecastLineSentence(
        line,
        upcomingExposure: view.upcomingExposure,
        exposureLabel: 'attendance',
      );
      expect(words, contains('Last time you used 2; before that, 2.'));
      expect(words, isNot(contains('200')));
    });

    test('the same item as per-person WOULD scale — proving the basis is the '
        'difference, not the data', () async {
      final soap = await h.createItem(name: 'Dish soap');
      for (final (i, date) in [
        '2026-05-01',
        '2026-06-01',
        '2026-07-01',
      ].indexed) {
        await closedEvent(
          itemId: soap,
          name: 'Event $i',
          date: date,
          exposure: 200,
          depletionMicros: 2000000,
        );
      }
      final big = await h.createEvent(
        name: 'The big one',
        scheduledDate: '2026-09-01',
        plannedExposure: 2000,
        plannedItemIds: [soap],
      );
      final line = (await generate(big)).lines.single;
      expect(line.demandBasis, DemandBasis.perPerson);
      expect(
        line.expectedUseMicros,
        20000000,
        reason:
            'unfiled = per person: 0.01/person × 2000 = 20 — the honest '
            'per-person answer, which is exactly what soap must escape',
      );
      // The per-person line quotes the headcount each observation came
      // from, because for this basis that is exactly what makes it scale.
      expect(
        forecastLineSentence(
          line,
          upcomingExposure: 2000,
          exposureLabel: 'attendance',
        ),
        contains(
          'Last time you used 2 for 200 attendance; before that, '
          '2 for 200.',
        ),
      );
    });
  });

  group('per-event cold start', () {
    test('"you usually bring 2" plans 3 with the balanced reserve', () async {
      final folder = await cleaningFolderId();
      final soap = await h.ok(
        CreateItem(
          name: 'Dish soap',
          folderId: FolderId(folder),
          perEventBaseline: Quantity.whole(2),
        ),
      );
      final soapId = soap.createdRecordIds.first;
      final eventId = await h.createEvent(
        name: 'First ever',
        plannedExposure: 2000,
        plannedItemIds: [soapId],
      );

      final line = (await generate(eventId)).lines.single;
      expect(line.demandBasis, DemandBasis.perEvent);
      expect(line.evidenceGrade, EvidenceGrade.insufficientData);
      expect(line.expectedUseMicros, isNull, reason: 'the engine saw nothing');
      expect(line.basis, ForecastBasis.perEventBaseline);
      expect(line.baselinePerEventMicros, 2000000);
      expect(line.baselineExpectedUseMicros, 2000000);
      expect(line.baselinePlannedMicros, 2200000);
      expect(line.baselineLoadMicros, 3000000);
      expect(line.baselineServesPerUnitMicros, isNull);
      expect(line.warnings.last, contains('usual 2 per event'));
      expect(
        forecastLineSentence(
          line,
          upcomingExposure: 2000,
          exposureLabel: 'attendance',
        ),
        contains(
          'A guess — no past events to learn from yet. You said you usually '
          'bring 2.',
        ),
      );
    });

    test(
      'a per-event item with no usual amount gets an honest blank',
      () async {
        final folder = await cleaningFolderId();
        final soap = await h.createItem(name: 'Dish soap');
        await h.ok(
          MoveItemToFolder(itemId: ItemId(soap), folderId: FolderId(folder)),
        );
        final eventId = await h.createEvent(
          name: 'First ever',
          plannedExposure: 100,
          plannedItemIds: [soap],
        );
        final line = (await generate(eventId)).lines.single;
        expect(line.basis, ForecastBasis.insufficientData);
        expect(line.isBaseline, isFalse);
      },
    );

    test('the flipped "N per person" cold start: 200 people × 3 per person '
        'is exactly 600', () async {
      final napkins = await h.ok(
        CreateItem(name: 'Napkins', perPersonRatio: UnitRatio(3, 1)),
      );
      final eventId = await h.createEvent(
        name: 'First ever',
        plannedExposure: 200,
        plannedItemIds: [napkins.createdRecordIds.first],
      );
      final line = (await generate(eventId)).lines.single;
      expect(line.demandBasis, DemandBasis.perPerson);
      expect(line.basis, ForecastBasis.servesBaseline);
      expect(line.baselineExpectedUseMicros, 600000000, reason: 'exactly 600');
      expect(line.baselinePerPersonNumerator, 3);
      expect(line.baselinePerPersonDenominator, 1);
      expect(line.warnings.last, contains('3 per person'));
    });
  });

  group('the supplies-jump warning — the literal 100 → 500 case', () {
    Future<String> soapWithHistoryAt100() async {
      final folder = await cleaningFolderId();
      final soap = await h.createItem(name: 'Dish soap');
      await h.ok(
        MoveItemToFolder(itemId: ItemId(soap), folderId: FolderId(folder)),
      );
      for (final (i, date) in [
        '2026-05-01',
        '2026-06-01',
        '2026-07-01',
      ].indexed) {
        await closedEvent(
          itemId: soap,
          name: 'Small event $i',
          date: date,
          exposure: 100,
          depletionMicros: 2000000,
        );
      }
      return soap;
    }

    test('estimates learned at 100 people warn at a 500-person event — and '
        'the number itself is untouched: no invented scaling', () async {
      final soap = await soapWithHistoryAt100();
      final big = await h.createEvent(
        name: 'The big one',
        scheduledDate: '2026-09-01',
        plannedExposure: 500,
        plannedItemIds: [soap],
      );

      final line = (await generate(big)).lines.single;
      expect(line.demandBasis, DemandBasis.perEvent);
      expect(
        line.warnings,
        contains(
          'This estimate comes from much smaller events — bring more than '
          'usual and count what you use.',
        ),
      );
      expect(
        line.expectedUseMicros,
        2000000,
        reason: 'still the median — a warning, never arithmetic',
      );
      expect(line.loadMicros, 3000000);

      // Snapshot-persisted like every other warning: the stored row carries
      // it, not just this in-memory view.
      final stored = await h.db
          .customSelect('SELECT warnings_json FROM forecast_lines')
          .getSingle();
      expect(
        stored.read<String>('warnings_json'),
        contains('much smaller events'),
      );
    });

    test('exactly 2× the largest observed exposure is still inside the '
        'learned range: no warning at 200', () async {
      final soap = await soapWithHistoryAt100();
      final event = await h.createEvent(
        name: 'Twice the size',
        scheduledDate: '2026-09-01',
        plannedExposure: 200,
        plannedItemIds: [soap],
      );
      final line = (await generate(event)).lines.single;
      expect(
        line.warnings.any((w) => w.contains('much smaller events')),
        isFalse,
      );
    });

    test('a per-person line never carries it — scaling is that basis\'s own '
        'arithmetic', () async {
      final soap = await h.createItem(name: 'Dish soap');
      await closedEvent(
        itemId: soap,
        name: 'Small event',
        date: '2026-07-01',
        exposure: 100,
        depletionMicros: 2000000,
      );
      final big = await h.createEvent(
        name: 'The big one',
        scheduledDate: '2026-09-01',
        plannedExposure: 500,
        plannedItemIds: [soap],
      );
      final line = (await generate(big)).lines.single;
      expect(line.demandBasis, DemandBasis.perPerson);
      expect(
        line.warnings.any((w) => w.contains('much smaller events')),
        isFalse,
      );
    });

    test('a per-event cold start (no evidence) has no learned range to be '
        'outside of', () async {
      final folder = await cleaningFolderId();
      final soap = await h.ok(
        CreateItem(
          name: 'Dish soap',
          folderId: FolderId(folder),
          perEventBaseline: Quantity.whole(2),
        ),
      );
      final big = await h.createEvent(
        name: 'First ever',
        plannedExposure: 500,
        plannedItemIds: [soap.createdRecordIds.first],
      );
      final line = (await generate(big)).lines.single;
      expect(
        line.warnings.any((w) => w.contains('much smaller events')),
        isFalse,
      );
    });
  });

  group('the basis is part of the stored record', () {
    test('every line stores its basis; flipping an item goes stale, and '
        'regeneration changes the number', () async {
      final folder = await cleaningFolderId();
      final soap = await h.createItem(name: 'Dish soap');
      await closedEvent(
        itemId: soap,
        name: 'Small event',
        date: '2026-07-01',
        exposure: 200,
        depletionMicros: 2000000,
      );
      final big = await h.createEvent(
        name: 'The big one',
        scheduledDate: '2026-09-01',
        plannedExposure: 2000,
        plannedItemIds: [soap],
      );

      // Per-person first (unfiled): 0.01/person × 2000 = 20.
      final before = await generate(big);
      expect(before.lines.single.demandBasis, DemandBasis.perPerson);
      expect(before.lines.single.expectedUseMicros, 20000000);
      expect(await service.isStale(big), isFalse);

      // Filing it under the per-event folder flips the effective basis:
      // the stored snapshot must read as out of date, never silently change.
      await h.ok(
        MoveItemToFolder(itemId: ItemId(soap), folderId: FolderId(folder)),
      );
      expect(await service.isStale(big), isTrue);

      final after = await generate(big);
      expect(after.lines.single.demandBasis, DemandBasis.perEvent);
      expect(after.lines.single.expectedUseMicros, 2000000);

      // Both snapshots persist — append-only regeneration, and each row
      // says which question it answered.
      final stored = await h.db
          .customSelect(
            'SELECT demand_basis FROM forecast_lines ORDER BY snapshot_id',
          )
          .get();
      expect(
        [for (final row in stored) row.read<String>('demand_basis')],
        ['per_person', 'per_event'],
      );
    });

    test(
      'an item-level override beats the folder in the effective basis',
      () async {
        final soap = await h.ok(
          const CreateItem(
            name: 'Dish soap',
            demandBasis: DemandBasis.perEvent,
          ),
        );
        final soapId = soap.createdRecordIds.first;
        await closedEvent(
          itemId: soapId,
          name: 'Small event',
          date: '2026-07-01',
          exposure: 200,
          depletionMicros: 2000000,
        );
        final big = await h.createEvent(
          name: 'The big one',
          scheduledDate: '2026-09-01',
          plannedExposure: 2000,
          plannedItemIds: [soapId],
        );
        final line = (await generate(big)).lines.single;
        expect(line.demandBasis, DemandBasis.perEvent);
        expect(line.expectedUseMicros, 2000000);
      },
    );
  });

  group('nothing leaks into history', () {
    test('the label query cannot name the v3 columns', () {
      const sql = ForecastDao.labelQuerySql;
      for (final forbidden in [
        'folder',
        'demand_basis',
        'per_event',
        'per_person',
        'baseline',
      ]) {
        expect(
          sql.contains(forbidden),
          isFalse,
          reason: 'the label query must not read $forbidden',
        );
      }
    });

    test(
      'a per-event baseline is stored but the label query stays empty',
      () async {
        final folder = await cleaningFolderId();
        final soap = await h.ok(
          CreateItem(
            name: 'Dish soap',
            folderId: FolderId(folder),
            perEventBaseline: Quantity.whole(2),
          ),
        );
        final soapId = soap.createdRecordIds.first;
        final eventId = await h.createEvent(
          name: 'First ever',
          plannedExposure: 100,
          plannedItemIds: [soapId],
        );
        await generate(eventId);
        expect(
          await h.db.forecastDao.labelHistory(soapId, historyWindow: 12),
          isEmpty,
          reason: 'confirmed closeouts are the only history',
        );
      },
    );
  });
}
