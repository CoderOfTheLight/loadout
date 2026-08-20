/// The confirm sheet's 'Counted so far: $X' (v7): the not-skipped lines'
/// depletions at the items' CURRENT prices — the same number the applier
/// is about to snapshot onto the confirmed lines. With no priced counted
/// line the sheet says nothing rather than invent a $0.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

void main() {
  testWidgets("the sheet totals the counted lines at today's prices", (
    tester,
  ) async {
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

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    // Loaded 10, 2 left → used 8 (thrown out counts as 0), at $2.50 each
    // = $20.
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 8'), findsOneWidget);

    await tester.ensureVisible(find.text('Finish closeout'));
    await tester.tap(find.text('Finish closeout'));
    await tester.pumpAndSettle();
    expect(find.text(r'Counted so far: $20'), findsOneWidget);

    // Back out — this pin is about the sheet, not the commit.
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    // Let the debounced draft autosave fire before the test ends.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });

  testWidgets('an unpriced closeout shows no counted line on the sheet', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final itemId = await seedItem(h, name: 'Napkins');
      eventId = await seedEvent(
        h,
        name: 'Market',
        date: '2026-08-10',
        exposure: 150,
        itemIds: [itemId],
      );
      await activateEvent(h, eventId);
    });

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    // 'None used' with nothing on record confirms a direct used of 0.
    await tester.ensureVisible(find.text('None used'));
    await tester.tap(find.text('None used'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish closeout'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm this closeout?'), findsOneWidget);
    expect(find.textContaining('Counted so far'), findsNothing);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });
}
