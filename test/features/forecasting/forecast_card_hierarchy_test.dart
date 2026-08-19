/// ONE answer per forecast card. The card used to print Expected / Planned /
/// Load / Acquire at identical weight; it now carries exactly two figures,
/// and both are actions: "Bring 60" ([Numerals.hero]) and, only when there
/// is something to buy, "Buy 60 more" ([Numerals.glance]).
///
/// Expected and Planned are gone entirely. They were the last of the four-up
/// grid still standing, demoted to a caption — but they are engine
/// intermediates (the median before the reserve, the reserve before the pack
/// rounding) and there is nothing a volunteer can do with either. The
/// line-detail screen says what the number rests on in a sentence instead.
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
    expect(acquire.style!.fontSize!, lessThan(heroSize!));

    // The engine's intermediates are not on the card at all.
    expect(find.textContaining('Expected'), findsNothing);
    expect(find.textContaining('Planned'), findsNothing);
    expect(find.textContaining('49.5'), findsNothing);

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
    expect(find.text('60'), findsOneWidget);
    // … and nothing invents a "Buy 0 more".
    expect(find.textContaining('Buy '), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('the card survives 200 % text scale on a 320 dp phone', (
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
    // On a 320 dp phone at 200 % the header alone fills the fold, so the
    // hero is scrolled to — an overflow anywhere on the way fails here.
    await tester.scrollUntilVisible(
      find.text('60'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('60'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.flushTimers(tester);
  });
}
