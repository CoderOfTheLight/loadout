/// ForecastLineDetailScreen widget tests (design §11.3).
///
/// The screen is one sentence plus the evidence it rests on. The four-cell
/// Expected / Planned / Load / Acquire grid and the whole Assumptions table
/// (Exposure, Policy, Basis, "You had at generation", "Confirmed inbound",
/// "History window") are gone: they were the data model on the face of a
/// screen a volunteer opens to answer "why that number?". So these tests pin
/// the SENTENCE for every stored shape a line can take, that the banned
/// vocabulary appears nowhere in the forecasting UI, and that the override —
/// the one action here — still works exactly as §9/§12.17 require.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/data/db/app_database.dart' show ForecastOverride;
import 'package:loadout/features/forecasting/presentation/forecast_line_detail_screen.dart';

import '../../support/app_harness.dart';
import 'forecast_test_data.dart';

/// The vocabulary the audit found on these screens' faces. None of it may
/// come back, on any forecasting screen, in any state.
const bannedOnForecastScreens = [
  'Expected',
  'Planned ',
  'Assumptions',
  'Confirmed inbound',
  'History window',
  'direct_median',
];

void expectNoInternalModel(WidgetTester tester) {
  for (final word in bannedOnForecastScreens) {
    expect(
      find.textContaining(word),
      findsNothing,
      reason: '"$word" is the data model, not an answer',
    );
  }
}

void main() {
  testWidgets('full history: the sentence names the last two events, and '
      'the evidence rows carry every one', (tester) async {
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
    await h.go(
      tester,
      '/events/${scenario.upcomingEventId}/forecast/${scenario.itemId}',
    );

    // Newest first: 'Sold out' (40 at 100), then 'Quiet day' (50 at 100).
    expect(
      find.textContaining(
        'Bring 72. Last time you used 40 for 100 attendance; before that, '
        '50 for 100. You have none.',
      ),
      findsOneWidget,
    );

    // All three closeouts are listed, tappable, with the flag that matters.
    expect(find.textContaining('Sold out (Jul 15) — used 40'), findsOneWidget);
    expect(find.textContaining('Quiet day (Jul 8) — used 50'), findsOneWidget);
    expect(find.textContaining('Full day (Jul 1) — used 60'), findsOneWidget);
    expect(find.text('Ran out'), findsOneWidget);

    expectNoInternalModel(tester);
  });

  testWidgets('an evidence row still opens the event it came from', (
    tester,
  ) async {
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
    await h.go(
      tester,
      '/events/${scenario.upcomingEventId}/forecast/${scenario.itemId}',
    );

    await tester.tap(find.textContaining('Past market (Jul 1) — used 30'));
    await tester.pumpAndSettle();
    expect(find.text('Past market'), findsWidgets);
    expect(find.text('Planned items (1)'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('a single event says so and never invents a second', (
    tester,
  ) async {
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
    await h.go(
      tester,
      '/events/${scenario.upcomingEventId}/forecast/${scenario.itemId}',
    );

    expect(
      find.textContaining(
        'Bring 60. Last time you used 30 for 100 attendance. You have none.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('before that'), findsNothing);

    // The engine's own warning is NOT a cold-start warning, so it stays.
    expect(
      find.text('Upcoming exposure is outside the observed range.'),
      findsOneWidget,
    );
    expectNoInternalModel(tester);
  });

  testWidgets('a "1 serves N" line is called a guess, once, in words', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final ids = (await tester.runAsync(() async {
      final itemId = await seedServesItem(h, name: 'Pizzas', servesPerUnit: 4);
      final eventId = await seedEvent(
        h,
        name: 'First outing',
        date: '2026-09-07',
        exposure: 150,
        itemIds: [itemId],
      );
      unwrap(await h.read(forecastServiceProvider).generateSnapshot(eventId));
      return (itemId: itemId, eventId: eventId);
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/${ids.eventId}/forecast/${ids.itemId}');

    expect(
      find.textContaining(
        'Bring 42. A guess — no past events to learn from yet. One serves 4, '
        'and you are expecting 150 attendance. You have none.',
      ),
      findsOneWidget,
    );
    // Said once: neither engine warning survives beside the sentence.
    expect(
      find.textContaining('No comparable confirmed outcomes'),
      findsNothing,
    );
    expect(find.textContaining('Estimate only:'), findsNothing);
    // Pack size and units left the product surface.
    expect(find.textContaining('rounded up to packs'), findsNothing);
    expect(find.textContaining('each'), findsNothing);
    expectNoInternalModel(tester);
  });

  testWidgets('no history at all: no number, no pretence of a guess, and the '
      'baseline reason prefilled', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final ids = (await tester.runAsync(() async {
      final itemId = await seedItem(h, name: 'Napkins');
      final eventId = await seedEvent(
        h,
        name: 'First outing',
        date: '2026-09-05',
        exposure: 150,
        itemIds: [itemId],
      );
      unwrap(await h.read(forecastServiceProvider).generateSnapshot(eventId));
      return (itemId: itemId, eventId: eventId);
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/${ids.eventId}/forecast');

    // The review card says the answer is missing in words, and carries the
    // ONE cold-start line rather than two stacked amber banners.
    expect(find.text('No number yet.'), findsOneWidget);
    // One short line, and it does not call a missing number "a guess".
    expect(find.text('No past events to learn from yet.'), findsOneWidget);
    expect(find.textContaining('A guess'), findsNothing);
    expect(
      find.text('No comparable confirmed outcomes. Create a baseline plan.'),
      findsNothing,
    );
    await tester.tap(find.text('Set a baseline'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'No number yet. No past events to learn from yet, and nothing saved '
        'for this item to guess from. You have none.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('A guess'), findsNothing);

    // The override reason is prefilled "baseline" (§9).
    await tester.scrollUntilVisible(
      find.text('baseline'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('baseline'), findsOneWidget);
    expectNoInternalModel(tester);
  });

  testWidgets('override demands a reason of 3+ chars, appends rows, is named '
      'in the sentence, and clear-override appends a NULL-load row', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final scenario = (await tester.runAsync(() => seedScenario(h)))!;
    final snapshot = unwrap(
      (await tester.runAsync(
        () => h
            .read(forecastServiceProvider)
            .generateSnapshot(scenario.upcomingEventId),
      ))!,
    );
    final snapshotId = snapshot.id as String;
    Future<List<ForecastOverride>> overrideRows() async =>
        (await tester.runAsync(
          () => h
              .read(appDatabaseProvider)
              .forecastDao
              .overridesForSnapshot(snapshotId),
        ))!;

    await h.pumpApp(tester);
    await h.go(
      tester,
      '/events/${scenario.upcomingEventId}/forecast/${scenario.itemId}',
    );

    // Reach the override form and fill the load.
    await tester.scrollUntilVisible(
      find.text('Apply override'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('override-load')),
        matching: find.byType(TextField),
      ),
      '72',
    );

    // Too-short reason is rejected; nothing is written.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason (required)'),
      'ab',
    );
    await tester.ensureVisible(find.text('Apply override'));
    await tester.tap(find.text('Apply override'));
    await tester.pumpAndSettle();
    expect(find.text('Give a reason (at least 3 characters)'), findsOneWidget);
    expect(await overrideRows(), isEmpty);

    // A proper reason appends an override row; the display flips.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason (required)'),
      'roadworks reroute foot traffic',
    );
    await tester.ensureVisible(find.text('Apply override'));
    await tester.tap(find.text('Apply override'));
    await tester.pumpAndSettle();
    var rows = await overrideRows();
    expect(rows.length, 1);
    expect(rows.single.overrideLoadMicros, 72 * 1000000);

    // The sentence says whose number it is and what the app would have said.
    await tester.scrollUntilVisible(
      find.textContaining('You set that yourself'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining(
        'Bring 72. You set that yourself: roadworks reroute foot traffic. '
        'Loadout worked out 60.',
      ),
      findsOneWidget,
    );

    // Clear also demands a reason (§12.17)...
    await tester.scrollUntilVisible(
      find.text('Clear override'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Clear override'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear override'));
    await tester.pumpAndSettle();
    expect(find.text('Give a reason (at least 3 characters)'), findsOneWidget);
    expect((await overrideRows()).length, 1);

    // ...and appends a NULL-load row that reverts to the engine value.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason (required)'),
      'back to plan',
    );
    await tester.ensureVisible(find.text('Clear override'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear override'));
    await tester.pumpAndSettle();
    rows = await overrideRows();
    expect(rows.length, 2);
    expect(rows.last.overrideLoadMicros, isNull);
    await tester.scrollUntilVisible(
      find.text('Cleared — back to the engine value'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  });

  testWidgets('the whole screen survives 200 % text scale on a 320 dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

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

    // An overflow at 200 % on the narrowest phone fails the test here.
    await h.pumpScreen(
      tester,
      ForecastLineDetailScreen(
        eventId: scenario.upcomingEventId,
        itemId: scenario.itemId,
      ),
    );
    expect(find.textContaining('Bring 72.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.flushTimers(tester);
  });
}
