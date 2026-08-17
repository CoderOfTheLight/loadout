/// Forecast cost estimate (v7) over the REAL snapshot pipeline: a priced
/// line gets a cost caption (effective load × the item's CURRENT unit
/// price, exact cents), the list closes with 'Estimated cost: $X' over the
/// priced lines, and unpriced items are counted out loud ('N items have no
/// price yet — not counted.', singular handled). With no priced item at
/// all, no cost UI renders — an invented $0 would break the honesty rules.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/forecasting/presentation/forecast_review_screen.dart';

import '../../support/app_harness.dart';
import 'forecast_test_data.dart';

/// One priced Tortillas (pack 12, $2.50 each) and one unpriced Napkins,
/// both with confirmed history at exposure 100 and both planned on an
/// upcoming event for 150. The Tortillas arithmetic is [seedScenario]'s:
/// depletion 30 at 100 → load 60 for 150 — so the cost is 60 × $2.50 =
/// $150 exactly.
Future<String> seedPricedScenario(AppHarness h) async {
  final tortillas = unwrap(
    await h
        .read(catalogServiceProvider)
        .createItem(
          ItemDraft(
            name: 'Tortillas',
            unit: ItemUnit.each,
            packSize: Quantity.fromMicros(12 * 1000000),
            unitPrice: Money.fromCents(250),
          ),
        ),
  );
  final napkins = await seedItem(h, name: 'Napkins');
  final history = await seedEvent(
    h,
    name: 'Past market',
    date: '2026-07-01',
    exposure: 100,
    itemIds: [tortillas, napkins],
  );
  unwrap(await h.read(eventServiceProvider).activate(history));
  unwrap(
    await h
        .read(closeoutServiceProvider)
        .confirm(
          CloseoutFormDraft(
            eventId: history,
            confirmedExposure: 100,
            lines: [
              CloseoutFormLine(
                itemId: tortillas,
                depletion: Quantity.whole(30),
              ),
              CloseoutFormLine(itemId: napkins, depletion: Quantity.whole(50)),
            ],
          ),
        ),
  );
  final upcoming = await seedEvent(
    h,
    name: 'Street fair',
    date: '2026-09-01',
    exposure: 150,
    itemIds: [tortillas, napkins],
  );
  unwrap(await h.read(forecastServiceProvider).generateSnapshot(upcoming));
  return upcoming;
}

void main() {
  testWidgets('a priced line carries its cost caption, and the list closes '
      'with the estimated total plus the singular honesty note', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = (await tester.runAsync(() => seedPricedScenario(h)))!;

    await h.pumpScreen(tester, ForecastReviewScreen(eventId: eventId));

    // The per-line caption: load 60 × $2.50 each = $150, exact cents.
    await tester.dragUntilVisible(
      find.text(r'Cost: $150 · $2.50 each'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.text(r'Cost: $150 · $2.50 each'), findsOneWidget);

    // The closing summary counts only the priced line — and says so.
    await tester.dragUntilVisible(
      find.text(r'Estimated cost: $150'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.text(r'Estimated cost: $150'), findsOneWidget);
    expect(find.text('At your current item prices.'), findsOneWidget);
    expect(find.text('1 item has no price yet — not counted.'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('with no priced item at all there is no cost UI anywhere', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    // seedScenario's single Tortillas has no price.
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
    // Scroll to the bottom so every list child has been built.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.textContaining('Estimated cost'), findsNothing);
    expect(find.textContaining(r'Cost: $'), findsNothing);
    expect(find.textContaining('no price yet'), findsNothing);
    await h.flushTimers(tester);
  });
}
