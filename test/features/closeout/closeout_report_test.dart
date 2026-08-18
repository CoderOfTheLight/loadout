/// The closeout report ([CloseoutReportScreen] at
/// `/events/:eventId/closeout/report`) — the artifact a confirmed count
/// produces. Over the REAL pipeline (§11.3): items, events, snapshots and
/// closeouts all go through the application services.
///
/// What is pinned here: the money is the price SNAPSHOTTED at confirm (a
/// later price edit must not move it), the variance counts are right
/// including the no-forecast and no-price cases, and confirming actually
/// lands on the report.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/closeout/presentation/closeout_report_screen.dart';
import 'package:loadout/features/events/domain/event.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

void main() {
  group('varianceHeadline', () {
    test('says only the non-zero clauses, with the noun on the first', () {
      expect(
        varianceHeadline(matched: 12, over: 3, short: 1, hadForecast: true),
        '12 items matched, 3 over, 1 short',
      );
      expect(
        varianceHeadline(matched: 1, over: 0, short: 0, hadForecast: true),
        '1 item matched',
      );
      expect(
        varianceHeadline(matched: 0, over: 3, short: 1, hadForecast: true),
        '3 items over, 1 short',
      );
    });

    test('says plainly when there is nothing to compare against', () {
      expect(
        varianceHeadline(matched: 0, over: 0, short: 0, hadForecast: false),
        'No forecast was made for this event, so there is nothing to '
        'compare with.',
      );
      expect(
        varianceHeadline(matched: 0, over: 0, short: 0, hadForecast: true),
        'None of these items was in the forecast, so there is nothing to '
        'compare with.',
      );
    });
  });

  testWidgets('the report totals what was used at the prices snapshotted at '
      'confirm — a later price edit does not move it', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String itemId;
    late String eventId;
    await tester.runAsync(() async {
      itemId = await seedItem(
        h,
        name: 'Tortillas',
        unitPrice: Money.fromCents(250),
      );
      eventId = await seedEvent(
        h,
        name: 'Market',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [itemId],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [
          CloseoutFormLine(itemId: itemId, depletion: Quantity.whole(30)),
        ],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, closeoutReportLocation(eventId));

    // 30 used at the $2.50 the line froze = $75, exact cents.
    expect(find.text('TOTAL SPENT'), findsOneWidget);
    expect(find.text(r'$75'), findsOneWidget);
    expect(
      find.text('At the prices recorded when you closed out.'),
      findsOneWidget,
    );
    expect(find.text(r'$75 · $2.50 each'), findsOneWidget);

    // The catalog price quadruples afterwards …
    await tester.runAsync(
      () => h
          .read(catalogServiceProvider)
          .updateItem(
            itemId: itemId,
            draft: ItemDraft(
              name: 'Tortillas',
              unitPrice: Money.fromCents(1000),
            ),
          ),
    );
    // … and the report is re-read from scratch (leaving the route disposes
    // its providers, so this is a genuine second read of the record).
    await h.go(tester, '/events/$eventId');
    await h.go(tester, closeoutReportLocation(eventId));

    expect(find.text(r'$75'), findsOneWidget);
    expect(find.text(r'$300'), findsNothing);
    expect(find.text(r'$75 · $2.50 each'), findsOneWidget);
  });

  testWidgets('the variance counts cover matched, over, short, the item with '
      'no forecast and the item with no price', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final tortillas = await seedItem(
        h,
        name: 'Tortillas',
        unitPrice: Money.fromCents(250),
      );
      final napkins = await seedItem(h, name: 'Napkins'); // no price
      final cups = await seedItem(
        h,
        name: 'Cups',
        unitPrice: Money.fromCents(100),
      );
      final plates = await seedItem(
        h,
        name: 'Plates',
        unitPrice: Money.fromCents(50),
      );
      // One closed event at 100 gives every forecast line its rate.
      final past = await seedEvent(
        h,
        name: 'Past market',
        date: '2026-07-01',
        exposure: 100,
        itemIds: [tortillas, napkins, cups],
      );
      await activateEvent(h, past);
      await confirmCloseout(
        h,
        past,
        exposure: 100,
        lines: [
          CloseoutFormLine(itemId: tortillas, depletion: Quantity.whole(30)),
          CloseoutFormLine(itemId: napkins, depletion: Quantity.whole(50)),
          CloseoutFormLine(itemId: cups, depletion: Quantity.whole(20)),
        ],
      );
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [tortillas, napkins, cups],
      );
      // The forecast is made BEFORE the plates join the event, so the
      // plates line has nothing to be compared against.
      await unwrap(h.read(forecastServiceProvider).generateSnapshot(eventId));
      await unwrap(
        h
            .read(eventServiceProvider)
            .updateEvent(
              eventId: eventId,
              draft: EventDraft(
                name: 'Street fair',
                scheduledDate: '2026-08-10',
                plannedExposure: 100,
                plannedItemIds: [tortillas, napkins, cups, plates],
              ),
            ),
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [
          // expected 30 → matched
          CloseoutFormLine(itemId: tortillas, depletion: Quantity.whole(30)),
          // expected 50 → 5 over
          CloseoutFormLine(itemId: napkins, depletion: Quantity.whole(55)),
          // expected 20 → 5 short
          CloseoutFormLine(itemId: cups, depletion: Quantity.whole(15)),
          // never forecast
          CloseoutFormLine(itemId: plates, depletion: Quantity.whole(4)),
        ],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, closeoutReportLocation(eventId));

    // Money: $75 tortillas + $15 cups + $2 plates; the napkins had no
    // price at confirm and are counted out loud instead of as free.
    expect(find.text(r'$92'), findsOneWidget);
    expect(find.text('1 item had no price — not counted.'), findsOneWidget);

    // The headline, and the honest note for the item nobody forecast.
    expect(find.text('1 item matched, 1 over, 1 short'), findsOneWidget);
    expect(
      find.text('1 item was not in the forecast — nothing to compare.'),
      findsOneWidget,
    );

    // Per line: counted, expected, and the gap in words. Name order, so
    // the list reads Cups, Napkins, Plates, Tortillas.
    Future<void> scrollTo(Finder finder) => tester.dragUntilVisible(
      finder,
      find.byType(ListView),
      const Offset(0, -120),
    );
    await scrollTo(find.text('Expected 20 · 5 fewer')); // cups: 15 of 20
    await scrollTo(find.text('Expected 50 · 5 more')); // napkins: 55 of 50
    expect(find.text('No price recorded — not counted.'), findsOneWidget);
    await scrollTo(find.text('No forecast for this item.')); // plates
    expect(find.text(r'$2 · $0.50 each'), findsOneWidget);
    await scrollTo(find.text('Expected 30 · matched')); // tortillas
    expect(find.text(r'$75 · $2.50 each'), findsOneWidget);
  });

  testWidgets('with no forecast at all the report says so instead of '
      'inventing an expectation', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final itemId = await seedItem(h, name: 'Napkins'); // no price either
      eventId = await seedEvent(
        h,
        name: 'Market',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [itemId],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [
          CloseoutFormLine(itemId: itemId, depletion: Quantity.whole(12)),
        ],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, closeoutReportLocation(eventId));

    expect(
      find.text(
        'No forecast was made for this event, so there is nothing to '
        'compare with.',
      ),
      findsOneWidget,
    );
    // No prices anywhere: no total is shown, and no $0 is invented.
    expect(
      find.text('No prices were recorded, so there is no total to show.'),
      findsOneWidget,
    );
    expect(find.textContaining(r'$'), findsNothing);
    // The count itself is still on the page.
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('confirming a closeout lands on the report, and Back leads to '
      'the event', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final itemId = await seedItem(
        h,
        name: 'Tortillas',
        unitPrice: Money.fromCents(250),
      );
      eventId = await seedEvent(
        h,
        name: 'Market',
        date: '2026-08-10',
        exposure: 150,
        itemIds: [itemId],
      );
      await activateEvent(h, eventId);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // Count it the leftover way: loaded 10, 2 left → used 8.
    await tester.ensureVisible(find.textContaining('Worksheet'));
    await tester.tap(find.textContaining('Worksheet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 8'), findsOneWidget);

    await tester.tap(find.text('Finish closeout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // The count produced an artifact: 8 × $2.50 = $20 at the snapshotted
    // price, and the worksheet is gone rather than sitting under it.
    expect(find.text('Closeout report'), findsOneWidget);
    expect(find.text(r'$20'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Finish closeout'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Closed on'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('the report renders at 200 % text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final itemId = await seedItem(
        h,
        name: 'Tortillas',
        unitPrice: Money.fromCents(250),
      );
      eventId = await seedEvent(
        h,
        name: 'Market',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [itemId],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [
          CloseoutFormLine(itemId: itemId, depletion: Quantity.whole(30)),
        ],
      );
    });

    // An overflow at 200 % fails the test.
    await h.pumpScreen(tester, CloseoutReportScreen(eventId: eventId));
    expect(find.text(r'$75'), findsOneWidget);
    await h.flushTimers(tester);
  });
}
