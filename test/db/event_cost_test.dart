/// §11.1 family F (event cost, schema v7): the two answers of
/// `forecasting/domain/event_cost.dart`, computed over the real write path.
///
/// [PlannedCost] is arithmetic over the list the owner is building — the
/// override-winning forecast load × the item's CURRENT price — and says out
/// loud how much of the list it could not count. [EventCostPrediction] is
/// read from CONFIRMED closeouts alone (§4.3): latest revision per closed
/// event, priced with the cents SNAPSHOTTED on the line, over the confirmed
/// exposure from the header, medianed with the frozen engine's own
/// convention. With nothing confirmed there is no prediction at all — never
/// a zero.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/forecasting/application/event_cost_service.dart';
import 'package:loadout/features/forecasting/application/forecast_service.dart';
import 'package:loadout/features/forecasting/domain/event_cost.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/settings/application/settings_service.dart';

import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;
  late DriftSettingsService settings;
  late DriftForecastService forecast;
  late DriftEventCostService cost;

  setUp(() async {
    h = WritePathHarness();
    settings = DriftSettingsService(h.db, clock: h.clock);
    forecast = DriftForecastService(
      h.db,
      h.applier,
      settings,
      idGenerator: h.ids,
      clock: h.clock,
    );
    cost = DriftEventCostService(h.db, forecast, settings);
    // Lean adds no reserve, so every load below is exactly the arithmetic
    // the test states rather than the arithmetic plus a policy percentage.
    await settings.updatePreferences(defaultPolicy: PlanningPolicy.lean);
  });

  tearDown(() => h.close());

  // ------------------------------------------------------------- builders

  Future<String> item(
    String name, {
    int? cents,
    int? servesPerUnitMicros,
  }) async {
    final receipt = await h.ok(
      CreateItem(
        name: name,
        unitPrice: cents == null ? null : Money.fromCents(cents),
        servesPerUnit: servesPerUnitMicros == null
            ? null
            : Quantity.fromMicros(servesPerUnitMicros),
      ),
    );
    return receipt.createdRecordIds.first;
  }

  Future<String> snapshotFor(String eventId) async {
    final result = await forecast.generateSnapshot(eventId);
    return result.fold(
      (view) => view.id as String,
      (error) => fail('generateSnapshot failed: ${error.message}'),
    );
  }

  /// Pins one line's load through the override log — the same
  /// override-winning figure the forecast screen shows.
  Future<void> pinLoad(String snapshotId, String itemId, int micros) async {
    final result = await forecast.setOverride(
      snapshotId: snapshotId,
      itemId: itemId,
      load: Quantity.fromMicros(micros),
      reason: 'pinned by test',
    );
    result.fold(
      (_) {},
      (error) => fail('setOverride failed: ${error.message}'),
    );
  }

  Future<String> closedEvent({
    required String name,
    required String date,
    required int exposure,
    required Map<String, int> depletions,
  }) async {
    final eventId = await h.createEvent(
      name: name,
      scheduledDate: date,
      plannedExposure: exposure,
      plannedItemIds: depletions.keys.toList(),
    );
    await h.ok(ActivateEvent(EventId(eventId)));
    await h.ok(
      RecordCloseout(
        eventId: EventId(eventId),
        confirmedExposure: exposure,
        lines: [
          for (final entry in depletions.entries)
            CloseoutLineDraft(
              itemId: ItemId(entry.key),
              depletion: Quantity.fromMicros(entry.value),
            ),
        ],
      ),
    );
    return eventId;
  }

  // =========================================================== planned cost

  group('PlannedCost — what I am about to spend', () {
    test(
      'an event with no planned items is empty, not zero-with-a-total',
      () async {
        final eventId = await h.createEvent(name: 'Empty', plannedExposure: 50);
        final planned = await cost.plannedCost(eventId);
        expect(planned.isEmpty, isTrue);
        expect(planned.total, Money.zero);
        expect(planned.pricedItemCount, 0);
        expect(planned.unpricedItemCount, 0);
      },
    );

    test('before a forecast exists there are no planned quantities, so every '
        'item is uncounted and no total is shown', () async {
      final tortillas = await item('Tortillas', cents: 299);
      final salsa = await item('Salsa', cents: 150);
      final eventId = await h.createEvent(
        name: 'Market',
        plannedExposure: 100,
        plannedItemIds: [tortillas, salsa],
      );

      final planned = await cost.plannedCost(eventId);
      expect(planned.isEmpty, isTrue, reason: 'nothing priced yet drives it');
      expect(planned.pricedItemCount, 0);
      expect(
        planned.unpricedItemCount,
        2,
        reason: 'priced but with no quantity to price: said out loud',
      );
    });

    test('mixed priced and unpriced items: exact integer cents over the '
        'override-winning loads, unpriced counted out loud', () async {
      final tortillas = await item('Tortillas', cents: 299);
      final salsa = await item('Salsa', cents: 150);
      final napkins = await item('Napkins');
      final eventId = await h.createEvent(
        name: 'Market',
        plannedExposure: 100,
        plannedItemIds: [tortillas, salsa, napkins],
      );
      final snapshotId = await snapshotFor(eventId);
      await pinLoad(snapshotId, tortillas, 10000000); // 10 × 299
      await pinLoad(snapshotId, salsa, 4000000); //      4 × 150
      await pinLoad(snapshotId, napkins, 5000000); //     no price at all

      final planned = await cost.plannedCost(eventId);
      expect(planned.total, Money.fromCents(3590));
      expect(planned.pricedItemCount, 2);
      expect(planned.unpricedItemCount, 1);
      expect(planned.isPartial, isTrue);
      expect(planned.isEmpty, isFalse);
    });

    test(
      'a fractional load costs exact cents, truncated at the cent',
      () async {
        final mince = await item('Mince', cents: 3);
        final eventId = await h.createEvent(
          name: 'Market',
          plannedExposure: 10,
          plannedItemIds: [mince],
        );
        final snapshotId = await snapshotFor(eventId);
        await pinLoad(snapshotId, mince, 1500000); // 1.5 × 3c = 4.5c

        final planned = await cost.plannedCost(eventId);
        expect(planned.total, Money.fromCents(4), reason: 'never a double');
      },
    );

    test('a load of zero is a counted line, not an uncounted one', () async {
      final tortillas = await item('Tortillas', cents: 299);
      final eventId = await h.createEvent(
        name: 'Market',
        plannedExposure: 100,
        plannedItemIds: [tortillas],
      );
      final snapshotId = await snapshotFor(eventId);
      await pinLoad(snapshotId, tortillas, 0);

      final planned = await cost.plannedCost(eventId);
      expect(planned.total, Money.zero);
      expect(planned.pricedItemCount, 1, reason: '"bring none" is an answer');
      expect(planned.unpricedItemCount, 0);
      expect(planned.isEmpty, isFalse);
    });

    test('every planned item unpriced: empty with the right count, never a '
        'cheaper-looking total', () async {
      final napkins = await item('Napkins');
      final cups = await item('Cups');
      final eventId = await h.createEvent(
        name: 'Market',
        plannedExposure: 100,
        plannedItemIds: [napkins, cups],
      );
      final snapshotId = await snapshotFor(eventId);
      await pinLoad(snapshotId, napkins, 20000000);
      await pinLoad(snapshotId, cups, 30000000);

      final planned = await cost.plannedCost(eventId);
      expect(planned.isEmpty, isTrue);
      expect(planned.total, Money.zero);
      expect(planned.pricedItemCount, 0);
      expect(planned.unpricedItemCount, 2);
      expect(planned.isPartial, isFalse, reason: 'nothing real to be partial');
    });

    test('with no override the engine/baseline load is used — the same figure '
        'the forecast screen shows', () async {
      // "1 serves 4" over 100 people is 25 units; lean adds no reserve and a
      // pack of one unit rounds to whole things.
      final pizza = await item(
        'Pizza',
        cents: 100,
        servesPerUnitMicros: 4000000,
      );
      final eventId = await h.createEvent(
        name: 'Market',
        plannedExposure: 100,
        plannedItemIds: [pizza],
      );
      final snapshotId = await snapshotFor(eventId);

      expect((await cost.plannedCost(eventId)).total, Money.fromCents(2500));

      // …and an override wins over it, exactly as it does on screen.
      await pinLoad(snapshotId, pizza, 30000000);
      expect((await cost.plannedCost(eventId)).total, Money.fromCents(3000));
    });

    test('the stream re-costs when an item is added, removed, repriced, or '
        'its forecast load overridden', () async {
      final tortillas = await item('Tortillas', cents: 299);
      final salsa = await item('Salsa', cents: 150);
      final eventId = await h.createEvent(
        name: 'Market',
        plannedExposure: 100,
        plannedItemIds: [tortillas, salsa],
      );
      final snapshotId = await snapshotFor(eventId);
      await pinLoad(snapshotId, tortillas, 10000000);
      await pinLoad(snapshotId, salsa, 4000000);

      final seen = <PlannedCost>[];
      final sub = cost.watchPlannedCost(eventId).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.last.total, Money.fromCents(3590));

      // Repriced.
      await h.ok(
        UpdateItem(itemId: ItemId(tortillas), unitPrice: Money.fromCents(349)),
      );
      await pumpEventQueue();
      expect(seen.last.total, Money.fromCents(4090));

      // Overridden.
      await pinLoad(snapshotId, salsa, 6000000);
      await pumpEventQueue();
      expect(seen.last.total, Money.fromCents(4390));

      // Removed from the list.
      await h.ok(
        UpdateEvent(
          eventId: EventId(eventId),
          plannedItemIds: [ItemId(tortillas)],
        ),
      );
      await pumpEventQueue();
      expect(seen.last.total, Money.fromCents(3490));
      expect(seen.last.unpricedItemCount, 0);

      // Added — the snapshot predates it, so it has no quantity yet and is
      // counted as uncounted rather than silently ignored.
      final cups = await item('Cups', cents: 25);
      await h.ok(
        UpdateEvent(
          eventId: EventId(eventId),
          plannedItemIds: [ItemId(tortillas), ItemId(cups)],
        ),
      );
      await pumpEventQueue();
      expect(seen.last.total, Money.fromCents(3490));
      expect(seen.last.pricedItemCount, 1);
      expect(seen.last.unpricedItemCount, 1);
      expect(seen.last.isPartial, isTrue);
    });
  });

  // ============================================================ prediction

  group('EventCostPrediction — what events like this usually cost', () {
    late String tortillas;
    late String target;

    setUp(() async {
      tortillas = await item('Tortillas', cents: 100);
      target = await h.createEvent(
        name: 'Next market',
        scheduledDate: '2026-12-01',
        plannedExposure: 25,
        plannedItemIds: [tortillas],
      );
    });

    /// perPerson 100 / 200 / 500 respectively, all at 100c a unit.
    Future<void> januaryToMarch() async {
      await closedEvent(
        name: 'January',
        date: '2026-01-01',
        exposure: 10,
        depletions: {tortillas: 10000000},
      );
      await closedEvent(
        name: 'February',
        date: '2026-02-01',
        exposure: 10,
        depletions: {tortillas: 20000000},
      );
      await closedEvent(
        name: 'March',
        date: '2026-03-01',
        exposure: 10,
        depletions: {tortillas: 50000000},
      );
    }

    test(
      'no confirmed history means no prediction at all — never a zero',
      () async {
        expect(await cost.costPrediction(target), isNull);
      },
    );

    test('an event with no planned exposure has nothing to scale to', () async {
      await januaryToMarch();
      final noExposure = await h.createEvent(
        name: 'Undecided',
        scheduledDate: '2026-12-02',
        plannedItemIds: [tortillas],
      );
      expect(await cost.costPrediction(noExposure), isNull);
    });

    test(
      'median across three events (odd), scaled to this event\'s exposure',
      () async {
        await januaryToMarch();

        final prediction = (await cost.costPrediction(target))!;
        expect(prediction.perPerson, Money.fromCents(200));
        expect(prediction.exposure, 25);
        expect(prediction.total, Money.fromCents(5000));
        expect(prediction.isThin, isFalse);
        expect(prediction.understates, isFalse);
        expect(
          [for (final e in prediction.evidence) e.eventName],
          ['March', 'February', 'January'],
          reason: 'newest first',
        );
        final march = prediction.evidence.first;
        expect(march.total, Money.fromCents(5000));
        expect(march.confirmedExposure, 10);
        expect(march.perPersonCents, 500);
        expect(march.unpricedLineCount, 0);
      },
    );

    test('even counts take the truncating mean of the two middle values — '
        'the frozen engine\'s own convention', () async {
      // Two events: 100 and 500 → (100 + 500) ~/ 2 = 300.
      await closedEvent(
        name: 'January',
        date: '2026-01-01',
        exposure: 10,
        depletions: {tortillas: 10000000},
      );
      await closedEvent(
        name: 'March',
        date: '2026-03-01',
        exposure: 10,
        depletions: {tortillas: 50000000},
      );
      var prediction = (await cost.costPrediction(target))!;
      expect(prediction.perPerson, Money.fromCents(300));
      expect(prediction.total, Money.fromCents(7500));
      expect(prediction.isThin, isTrue, reason: 'two events is not a pattern');

      // Four events: 100, 200, 401, 500 → (200 + 401) ~/ 2 = 300, TRUNCATED
      // (300.5 never rounds up: integer-only, deterministic).
      await closedEvent(
        name: 'February',
        date: '2026-02-01',
        exposure: 10,
        depletions: {tortillas: 20000000},
      );
      await closedEvent(
        name: 'April',
        date: '2026-04-01',
        exposure: 10,
        depletions: {tortillas: 40100000},
      );
      prediction = (await cost.costPrediction(target))!;
      expect(prediction.evidence, hasLength(4));
      expect(prediction.perPerson, Money.fromCents(300));
      expect(prediction.total, Money.fromCents(7500));
      expect(prediction.isThin, isFalse);
    });

    test('the SNAPSHOTTED price is used: repricing the item afterwards never '
        'moves a prediction', () async {
      await januaryToMarch();
      final before = (await cost.costPrediction(target))!;

      await h.ok(
        UpdateItem(itemId: ItemId(tortillas), unitPrice: Money.fromCents(999)),
      );

      final after = (await cost.costPrediction(target))!;
      expect(after.perPerson, before.perPerson);
      expect(after.total, Money.fromCents(5000));
      expect(
        [for (final e in after.evidence) e.total.cents],
        [5000, 2000, 1000],
        reason: 'history is priced at the cents it recorded',
      );
    });

    test('a revised closeout is read at its LATEST revision only', () async {
      final eventId = await closedEvent(
        name: 'January',
        date: '2026-01-01',
        exposure: 10,
        depletions: {tortillas: 10000000},
      );
      await h.ok(
        ReviseCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 20,
          lines: [
            CloseoutLineDraft(
              itemId: ItemId(tortillas),
              depletion: Quantity.fromMicros(40000000),
            ),
          ],
        ),
      );

      final prediction = (await cost.costPrediction(target))!;
      expect(prediction.evidence, hasLength(1), reason: 'one event, not two');
      final january = prediction.evidence.single;
      expect(january.confirmedExposure, 20);
      expect(january.total, Money.fromCents(4000));
      expect(prediction.perPerson, Money.fromCents(200));
    });

    test('planned, active and cancelled events are never evidence', () async {
      await januaryToMarch();
      // A planned event with the same items, and an active one: neither has
      // a confirmed outcome, so neither says anything about cost.
      final active = await h.createEvent(
        name: 'Running now',
        scheduledDate: '2026-07-01',
        plannedExposure: 10,
        plannedItemIds: [tortillas],
      );
      await h.ok(ActivateEvent(EventId(active)));
      final cancelled = await h.createEvent(
        name: 'Called off',
        scheduledDate: '2026-06-01',
        plannedExposure: 10,
        plannedItemIds: [tortillas],
      );
      await h.ok(
        CancelEvent(eventId: EventId(cancelled), reason: 'rained off'),
      );
      // Even a closeout stapled straight onto the cancelled event by hand —
      // dated NEWER than every real one, so a missing status filter would
      // show — must not become evidence.
      final commandId =
          (await h.db
                  .customSelect('SELECT id FROM commands LIMIT 1')
                  .getSingle())
              .read<String>('id');
      final forgedId = h.ids.newId();
      await h.db.customStatement(
        'INSERT INTO event_closeouts (id, event_id, revision, '
        'confirmed_exposure, source_command_id, confirmed_at_micros) '
        'VALUES (?, ?, 1, 10, ?, 1700000000000000)',
        [forgedId, cancelled, commandId],
      );
      await h.db.customStatement(
        'INSERT INTO closeout_lines (closeout_id, item_id, depletion_micros, '
        'unit_price_cents) VALUES (?, ?, 90000000, 100)',
        [forgedId, tortillas],
      );

      final prediction = (await cost.costPrediction(target))!;
      expect(
        [for (final e in prediction.evidence) e.eventName],
        ['March', 'February', 'January'],
      );
      expect(prediction.perPerson, Money.fromCents(200));
    });

    test('an event with no priced lines is excluded entirely, not counted as '
        'a free event', () async {
      final napkins = await item('Napkins');
      await closedEvent(
        name: 'Nothing priced',
        date: '2026-05-01',
        exposure: 10,
        depletions: {napkins: 30000000},
      );

      expect(
        await cost.costPrediction(target),
        isNull,
        reason: 'not evidence, not zero',
      );

      await closedEvent(
        name: 'January',
        date: '2026-01-01',
        exposure: 10,
        depletions: {tortillas: 10000000},
      );
      final prediction = (await cost.costPrediction(target))!;
      expect([for (final e in prediction.evidence) e.eventName], ['January']);
      expect(prediction.perPerson, Money.fromCents(100));
      expect(prediction.understates, isFalse);
    });

    test(
      'an evidence event with unpriced lines understates, and says so',
      () async {
        final napkins = await item('Napkins');
        await closedEvent(
          name: 'January',
          date: '2026-01-01',
          exposure: 10,
          depletions: {tortillas: 10000000, napkins: 30000000},
        );

        final prediction = (await cost.costPrediction(target))!;
        final january = prediction.evidence.single;
        expect(
          january.total,
          Money.fromCents(1000),
          reason: 'priced lines only',
        );
        expect(january.unpricedLineCount, 1);
        expect(prediction.understates, isTrue);
        expect(prediction.isThin, isTrue);
      },
    );

    test('the workspace history window bounds the lookback', () async {
      await januaryToMarch();
      await settings.updatePreferences(historyWindow: 2);

      final prediction = (await cost.costPrediction(target))!;
      expect(
        [for (final e in prediction.evidence) e.eventName],
        ['March', 'February'],
      );
      expect(prediction.perPerson, Money.fromCents(350), reason: '(500+200)/2');
    });

    test('the stream re-predicts when a new event is closed out', () async {
      await januaryToMarch();
      final seen = <EventCostPrediction?>[];
      final sub = cost.watchCostPrediction(target).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.last?.perPerson, Money.fromCents(200));

      await closedEvent(
        name: 'April',
        date: '2026-04-01',
        exposure: 10,
        depletions: {tortillas: 60000000},
      );
      await pumpEventQueue();
      expect(seen.last?.evidence, hasLength(4));
      expect(seen.last?.perPerson, Money.fromCents(350), reason: '(200+500)/2');
    });

    test('the same inputs give the same output', () async {
      await januaryToMarch();
      final first = (await cost.costPrediction(target))!;
      final second = (await cost.costPrediction(target))!;
      expect(second.perPerson, first.perPerson);
      expect(second.total, first.total);
      expect(second.exposure, first.exposure);
      expect(
        [for (final e in second.evidence) (e.eventId, e.total.cents)],
        [for (final e in first.evidence) (e.eventId, e.total.cents)],
      );

      final plannedOnce = await cost.plannedCost(target);
      final plannedTwice = await cost.plannedCost(target);
      expect(plannedTwice.total, plannedOnce.total);
      expect(plannedTwice.pricedItemCount, plannedOnce.pricedItemCount);
      expect(plannedTwice.unpricedItemCount, plannedOnce.unpricedItemCount);
    });
  });

  group('medianCents', () {
    test('matches the frozen engine: middle value, else truncating mean', () {
      expect(medianCents([5]), 5);
      expect(medianCents([300, 100, 200]), 200, reason: 'sorted, then middle');
      expect(
        medianCents([100, 201]),
        150,
        reason: '150.5 truncates, no half-up',
      );
      expect(medianCents([500, 100, 200, 401]), 300);
    });
  });
}
