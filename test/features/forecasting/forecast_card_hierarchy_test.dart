/// ONE answer per forecast card. The card used to print Expected /
/// Planned / Load / Acquire at identical weight; it now leads with the
/// single figure the owner acts on ("Bring 60", [Numerals.hero]), gives the
/// acquisition the second emphasis WHEN there is something to buy, and
/// drops the rest to caption tier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/theme.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/forecasting/presentation/forecast_review_screen.dart';

import '../../support/app_harness.dart';
import 'forecast_test_data.dart';

void main() {
  testWidgets('the card leads with one hero figure and demotes the rest to '
      'captions', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    // 30 used at 100 attendance, replanned for 150: expected 45, planned
    // 49.5, load 60 (pack of 12), acquire 60. The item carries no price,
    // so the only hero on the screen is the card's own.
    final scenario = (await tester.runAsync(() => seedScenario(h)))!;
    await tester.runAsync(
      () => h
          .read(forecastServiceProvider)
          .generateSnapshot(scenario.upcomingEventId),
    );

    await h.pumpScreen(
      tester,
      ForecastReviewScreen(eventId: scenario.upcomingEventId),
    );

    final context = tester.element(find.text('Bring'));
    final text = Theme.of(context).textTheme;

    // Exactly one figure on the screen is set at hero size, and it is the
    // one that says what to do.
    final heroSize = Numerals.hero(text)!.fontSize;
    final heroes = tester
        .widgetList<Text>(find.byType(Text))
        .where((widget) => widget.style?.fontSize == heroSize)
        .toList();
    expect(heroes, hasLength(1));
    expect(heroes.single.data, '60');
    expect(heroes.single.style, Numerals.hero(text));

    // The acquisition is the second action, one tier down.
    final acquire = tester.widget<Text>(find.text('Buy 60 more'));
    expect(acquire.style, Numerals.glance(text));

    // Expected and planned survive as ONE caption-tier line, subordinate
    // by weight and size rather than deleted.
    final caption = tester.widget<Text>(
      find.text('Expected 45 · Planned 49.5'),
    );
    expect(caption.style?.fontSize, Numerals.caption(text)?.fontSize);
    expect(caption.style?.fontWeight, Numerals.caption(text)?.fontWeight);
    expect(caption.style!.fontSize!, lessThan(heroSize!));
    // Tabular everywhere a figure is read.
    expect(caption.style?.fontFeatures, Numerals.tabular);

    // The evidence badge is untouched.
    expect(find.text('1 event'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('the acquisition emphasis appears only when something has to '
      'be bought', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = (await tester.runAsync(() async {
      // Same arithmetic as above, but 200 already on the shelf: the load
      // is covered, so the engine asks for nothing.
      final itemId = unwrap(
        await h
            .read(catalogServiceProvider)
            .createItem(
              ItemDraft(
                name: 'Tortillas',
                unit: ItemUnit.each,
                packSize: Quantity.fromMicros(12 * 1000000),
              ),
              openingCount: Quantity.whole(200),
            ),
      );
      final past = await seedEvent(
        h,
        name: 'Past market',
        date: '2026-07-01',
        exposure: 100,
        itemIds: [itemId],
      );
      await seedCloseout(
        h,
        eventId: past,
        confirmedExposure: 100,
        itemId: itemId,
        depletionMicros: 30 * 1000000,
      );
      final upcoming = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-09-01',
        exposure: 150,
        itemIds: [itemId],
      );
      unwrap(await h.read(forecastServiceProvider).generateSnapshot(upcoming));
      return upcoming;
    }))!;

    await h.pumpScreen(tester, ForecastReviewScreen(eventId: eventId));

    // The answer is still there …
    expect(find.text('Bring'), findsOneWidget);
    expect(find.text('Expected 45 · Planned 49.5'), findsOneWidget);
    // … and nothing invents a "Buy 0 more".
    expect(find.textContaining('Buy '), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('the card survives 200 % text scale', (tester) async {
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

    // An overflow at 200 % fails the test; the hero must still be there.
    await h.pumpScreen(
      tester,
      ForecastReviewScreen(eventId: scenario.upcomingEventId),
    );
    expect(find.text('60'), findsOneWidget);
    await h.flushTimers(tester);
  });
}
