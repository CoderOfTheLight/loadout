/// ForecastReviewScreen widget tests (design §11.3): generate persists a
/// snapshot and the screen renders the persisted row; the staleness banner
/// appears after an input change; Refresh APPENDS a new snapshot; closed
/// events become the accuracy review; empty states; 200 % text scale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../../support/app_harness.dart';
import 'forecast_test_data.dart';

void main() {
  testWidgets('generate persists a snapshot and renders the persisted row', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final scenario = (await tester.runAsync(() => seedScenario(h)))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/${scenario.upcomingEventId}/forecast');

    // Empty state: explainer + Generate.
    expect(find.text('Generate forecast'), findsOneWidget);
    await tester.tap(find.text('Generate forecast'));
    await tester.pumpAndSettle();

    // Header values come from the snapshot row, never hardcoded.
    expect(find.textContaining('direct_median v3'), findsOneWidget);
    expect(find.textContaining('computed just now'), findsOneWidget);
    expect(find.text('Balanced +10 %'), findsOneWidget);
    expect(find.text('for 150 attendance'), findsOneWidget);

    // The per-line four figures, evidence badge, warning verbatim.
    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('45'), findsOneWidget); // expected
    expect(find.text('49.5'), findsOneWidget); // planned (+10 %)
    expect(find.text('60'), findsNWidgets(2)); // load + acquire
    expect(find.text('1 event'), findsOneWidget);
    expect(
      find.text('Upcoming exposure is outside the observed range.'),
      findsOneWidget,
    );

    // The snapshot really was persisted (rendered from the DB row).
    final latest = await tester.runAsync(
      () => h
          .read(appDatabaseProvider)
          .forecastDao
          .latestSnapshotForEvent(scenario.upcomingEventId),
    );
    expect(latest, isNotNull);
    expect(latest!.method, 'direct_median');
    expect(latest.methodVersion, 3);
  });

  testWidgets('staleness banner appears after a ledger write and Refresh '
      'appends a new snapshot', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final scenario = (await tester.runAsync(() => seedScenario(h)))!;
    final first = unwrap(
      (await tester.runAsync(
        () => h
            .read(forecastServiceProvider)
            .generateSnapshot(scenario.upcomingEventId),
      ))!,
    );

    await h.pumpApp(tester);
    await h.go(tester, '/events/${scenario.upcomingEventId}/forecast');
    expect(
      find.textContaining('Inputs changed since this forecast'),
      findsNothing,
    );

    // An input change: a purchase arrives, moving on-hand 0 → 5.
    await tester.runAsync(
      () => h
          .read(inventoryServiceProvider)
          .record(
            MovementFormDraft(
              itemId: scenario.itemId,
              kind: MovementKind.receive,
              quantity: Quantity.fromMicros(5 * 1000000),
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Inputs changed since this forecast'),
      findsOneWidget,
    );

    // Refresh APPENDS; the old snapshot remains untouched.
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Inputs changed since this forecast'),
      findsNothing,
    );

    final latest = await tester.runAsync(
      () => h
          .read(appDatabaseProvider)
          .forecastDao
          .latestSnapshotForEvent(scenario.upcomingEventId),
    );
    expect(latest!.id, isNot(equals(first.id as String)));
    final original = await tester.runAsync(
      () => h
          .read(appDatabaseProvider)
          .forecastDao
          .snapshotById(first.id as String),
    );
    expect(original, isNotNull);
    // The appended snapshot froze the CHANGED input: on-hand moved from
    // −30 (history consume) to −25 after the +5 receive.
    final lines = await tester.runAsync(
      () => h.read(appDatabaseProvider).forecastDao.linesForSnapshot(latest.id),
    );
    expect(lines!.single.onHandMicros, -25 * 1000000);
  });

  testWidgets('closed event shows the accuracy review', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final scenario = (await tester.runAsync(() => seedScenario(h)))!;
    await tester.runAsync(() async {
      // Snapshot while still planned; then activate + confirm the closeout
      // (the label factory) which closes the event.
      unwrap(
        await h
            .read(forecastServiceProvider)
            .generateSnapshot(scenario.upcomingEventId),
      );
      await seedCloseout(
        h,
        eventId: scenario.upcomingEventId,
        confirmedExposure: 150,
        itemId: scenario.itemId,
        depletionMicros: 31 * 1000000,
        stockout: true,
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/${scenario.upcomingEventId}/forecast');

    expect(find.text('Accuracy review'), findsOneWidget);
    expect(find.text('Generate forecast'), findsNothing);
    expect(find.textContaining('confirmed 150'), findsOneWidget);
    expect(find.text('45'), findsOneWidget); // forecast
    expect(find.text('60'), findsOneWidget); // load
    expect(find.text('31'), findsOneWidget); // actual (derived by join)
    expect(
      find.textContaining('forecast 45, actual 31, -31 %'),
      findsOneWidget,
    );
    expect(find.text('Ran out'), findsOneWidget);
  });

  testWidgets('empty states: no planned items, and Generate disabled until '
      'exposure is set', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final ids = (await tester.runAsync(() async {
      final itemId = await seedItem(h);
      final noItems = await seedEvent(
        h,
        name: 'Bare event',
        date: '2026-09-02',
        exposure: 50,
      );
      final noExposure = await seedEvent(
        h,
        name: 'Vague event',
        date: '2026-09-03',
        itemIds: [itemId],
      );
      return (noItems: noItems, noExposure: noExposure);
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/${ids.noItems}/forecast');
    expect(
      find.text('Add items to this event to see a load list.'),
      findsOneWidget,
    );

    await h.go(tester, '/events/${ids.noExposure}/forecast');
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate forecast'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('Set a planned exposure on the event before generating.'),
      findsOneWidget,
    );
  });

  testWidgets('renders the snapshot at 200 % text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final scenario = (await tester.runAsync(() => seedScenario(h)))!;
    await tester.runAsync(
      () => h
          .read(forecastServiceProvider)
          .generateSnapshot(scenario.upcomingEventId),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/events/${scenario.upcomingEventId}/forecast');
    // Overflow errors at 200 % would fail the test; the header must render.
    expect(find.textContaining('direct_median v3'), findsOneWidget);
  });

  testWidgets('a sell-out in the history plans higher and says why in plain '
      'language', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final scenario = (await tester.runAsync(() => seedSelloutScenario(h)))!;
    await tester.runAsync(
      () => h
          .read(forecastServiceProvider)
          .generateSnapshot(scenario.upcomingEventId),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/events/${scenario.upcomingEventId}/forecast');

    // 55, not the 50 the raw median of {60, 50, 40} would have given.
    expect(find.text('55'), findsOneWidget); // expected
    expect(find.text('60.5'), findsOneWidget); // planned (+10 %)
    expect(find.text('50'), findsNothing);

    expect(
      find.textContaining('You ran out on 1 of these days'),
      findsOneWidget,
    );
    // The owner never has to meet the vocabulary.
    expect(find.textContaining('censored'), findsNothing);
    expect(find.textContaining('quantile'), findsNothing);
  });

  testWidgets('a "1 serves N" line shows its estimate instead of being '
      'badged as having no history', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final ids = (await tester.runAsync(() async {
      final itemId = await seedServesItem(h, name: 'Pizzas', servesPerUnit: 4);
      final eventId = await seedEvent(
        h,
        name: 'First outing',
        date: '2026-09-06',
        exposure: 150,
        itemIds: [itemId],
      );
      unwrap(await h.read(forecastServiceProvider).generateSnapshot(eventId));
      return (itemId: itemId, eventId: eventId);
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/${ids.eventId}/forecast');

    // The owner's complaint 3 paying off: ceil(150 / 4) = 38, +10 % = 41.8,
    // rounded up to whole things = 42, minus nothing on hand = 42.
    expect(find.text('38'), findsOneWidget); // expected
    expect(find.text('41.8'), findsOneWidget); // planned (+10 %)
    expect(find.text('42'), findsNWidgets(2)); // load + acquire
    expect(find.text('—'), findsNothing);

    // Badged as what it is, and never as confirmed history.
    expect(find.text('Estimate'), findsOneWidget);
    expect(find.text('No history'), findsNothing);
    expect(find.text('1 event'), findsNothing);
    expect(
      find.textContaining('Estimate only: worked out from "1 serves 4"'),
      findsOneWidget,
    );

    // It already has a number, so it is not asking for a baseline.
    expect(find.text('Set a baseline'), findsNothing);

    // Units left the product surface: nothing on this screen says "each".
    expect(find.textContaining('each'), findsNothing);
  });
}
