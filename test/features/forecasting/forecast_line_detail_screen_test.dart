/// ForecastLineDetailScreen widget tests (design §11.3): the full story for
/// one line — evidence value-copies, assumptions, warnings verbatim, the
/// method footer — plus override apply (mandatory reason ≥ 3 chars), the
/// NULL-load clear-override, the append-only history, and the baseline
/// entry point for lines with no history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/data/db/app_database.dart' show ForecastOverride;

import '../../support/app_harness.dart';
import 'forecast_test_data.dart';

void main() {
  testWidgets('shows evidence, assumptions, warnings verbatim, and the '
      'method footer', (tester) async {
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

    // Result narrated from the persisted line.
    expect(find.textContaining('Median of 1 observed rate'), findsOneWidget);
    expect(find.textContaining('rounded up to packs of 12,'), findsOneWidget);

    // Evidence: the stored value-copy with its source event and exposure.
    expect(find.textContaining('Past market · 2026-07-01'), findsOneWidget);
    expect(
      find.textContaining('100 attendance · depletion 30'),
      findsOneWidget,
    );

    // Assumptions (§9): policy, pack rounding, on-hand, inbound 0, window.
    await tester.scrollUntilVisible(
      find.text('Confirmed inbound'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Balanced +10 % reserve'), findsOneWidget);
    expect(find.text('12 per pack'), findsOneWidget);
    expect(find.text('0'), findsOneWidget); // confirmed inbound
    expect(find.textContaining('last 12 closed events'), findsOneWidget);

    // Warnings verbatim, then the method/version footer (assertions follow
    // scroll order: children scrolled past are unmounted by the ListView).
    await tester.scrollUntilVisible(
      find.text('Upcoming exposure is outside the observed range.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('direct_median · v3'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('direct_median · v3'), findsOneWidget);
  });

  testWidgets('the assumptions say what was done about days that ran out', (
    tester,
  ) async {
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

    await tester.scrollUntilVisible(
      find.text('Days you ran out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1 of 3 — raised to your typical rate'), findsOneWidget);

    // The evidence rows still show the CONFIRMED 40, never the 55 the engine
    // was handed.
    expect(
      find.textContaining('100 attendance · depletion 40'),
      findsOneWidget,
    );
    expect(find.text('Ran out'), findsOneWidget);
  });

  testWidgets('override demands a reason of 3+ chars, appends rows, and '
      'clear-override appends a NULL-load row', (tester) async {
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
    await tester.scrollUntilVisible(
      find.text('Load set to 72'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('roadworks reroute foot traffic'), findsWidgets);

    // Clear also demands a reason (§12.17)...
    await tester.scrollUntilVisible(
      find.text('Clear override'),
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Clear override'));
    await tester.pumpAndSettle();
    expect(find.text('Give a reason (at least 3 characters)'), findsOneWidget);
    expect((await overrideRows()).length, 1);

    // ...and appends a NULL-load row that reverts to the engine value.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason (required)'),
      'back to plan',
    );
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

  testWidgets('no-history line offers Set a baseline and prefills the '
      'override reason', (tester) async {
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

    // Insufficient data: badge, dashes, verbatim engine warning, CTA.
    expect(find.text('No history'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4));
    expect(
      find.text('No comparable confirmed outcomes. Create a baseline plan.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Set a baseline'));
    await tester.pumpAndSettle();

    // Line detail opened with the reason prefilled "baseline" (§9).
    await tester.scrollUntilVisible(
      find.text('baseline'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('baseline'), findsOneWidget);
  });

  testWidgets('a "1 serves N" line narrates the estimate and names no pack', (
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

    // Narrated in the owner's own terms, not the engine's.
    expect(
      find.textContaining('One serves 4 × 150 attendance'),
      findsOneWidget,
    );
    expect(find.textContaining('Median of'), findsNothing);
    expect(find.textContaining('set a baseline load below'), findsNothing);

    // Pack size left the product surface: one thing per pack is a no-op and
    // must not be narrated or listed.
    expect(find.textContaining('rounded up to packs'), findsNothing);
    expect(find.text('Pack rounding'), findsNothing);
    expect(find.text('One serves'), findsOneWidget);
    expect(find.textContaining('each'), findsNothing);
  });
}
