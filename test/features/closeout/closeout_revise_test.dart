/// Closeout revise flow (§11.3, §5): revising a closed event reopens the
/// same screen prefilled from the latest revision; confirming appends
/// revision N+1 with mirroring reversal movements plus fresh consume/waste
/// rows, so inventory and labels can never disagree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

/// Scrolls [finder] clear of the docked confirm bar, then taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('revise prefills the latest revision and appends N+1', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String itemId;
    late String eventId;
    await tester.runAsync(() async {
      itemId = await seedItem(h); // Tortillas: a counted thing
      eventId = await seedEvent(
        h,
        name: 'Night market',
        date: '2026-08-01',
        exposure: 120,
        itemIds: [itemId],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 120,
        lines: [
          CloseoutFormLine(
            itemId: itemId,
            loaded: Quantity.fromMicros(10000000),
            returned: Quantity.fromMicros(2000000),
            waste: Quantity.fromMicros(1000000),
            depletion: Quantity.fromMicros(7000000),
          ),
        ],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // Revise mode, prefilled from revision 1. The line comes back already
    // confirmed, so its card opens folded to the one-row summary.
    expect(find.text('Revise closeout'), findsOneWidget);
    expect(find.text('Confirming appends revision 2.'), findsOneWidget);
    expect(find.text('120'), findsOneWidget); // confirmed exposure
    expect(find.text('Used: 7'), findsOneWidget); // derived, on the summary
    expect(
      find.widgetWithText(TextFormField, 'How many are left?'),
      findsNothing,
    );

    // Tap it open and correct the leftover count: 2 → 3, used re-derives
    // live. The thrown-out box is back out because there is a 1 in it.
    await _tap(tester, find.text('Tortillas'));
    expect(find.widgetWithText(TextFormField, 'Thrown out'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '3',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 6'), findsOneWidget);

    await _tap(tester, find.text('Confirm revision'));
    expect(find.text('Confirm revision 2?'), findsOneWidget);
    expect(
      find.text('This becomes the history your forecasts learn from.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // A revision ends in the same artifact a first count does, over the
    // corrected figures (used 6, not 7).
    expect(find.text('Closeout report'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);

    // Back on the detail screen: both revisions on record.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Revision 2'), findsOneWidget);
    expect(find.text('Revision 1'), findsOneWidget);

    await tester.runAsync(() async {
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      expect(revisions, hasLength(2));
      final latest = revisions.first; // newest revision first
      expect(latest.revision, 2);
      expect(latest.supersedes, isNotNull);
      expect(latest.supersedes! as String, revisions.last.id as String);
      final line = latest.lines.single;
      expect(line.depletion.micros, 6000000);
      expect(line.returned!.micros, 3000000);

      // Revision 1's movements were mirrored by reversals; revision 2
      // wrote fresh consume/waste rows (§5).
      final movements = await h
          .read(inventoryLedgerProvider)
          .movements(event: EventId(eventId));
      expect(movements, hasLength(6));
      expect(
        movements.where((m) => m.kind == MovementKind.reversal),
        hasLength(2),
      );
      // Net on-hand: −6 (consume) − 1 (waste) after the round trip.
      final position = await h
          .read(inventoryLedgerProvider)
          .position(ItemId(itemId));
      expect(position.onHandMicros, -7000000);
    });
  });

  testWidgets('a fresh revise run marks previously skipped items skipped', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final confirmedItem = await seedItem(h, name: 'Al pastor');
      final skippedItem = await seedItem(h, name: 'Barbacoa');
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-02',
        exposure: 60,
        itemIds: [confirmedItem, skippedItem],
      );
      await activateEvent(h, eventId);
      // Revision 1 confirmed only the first item.
      await confirmCloseout(
        h,
        eventId,
        exposure: 55,
        lines: [
          CloseoutFormLine(
            itemId: confirmedItem,
            depletion: Quantity.fromMicros(4000000),
          ),
        ],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // The item without a revision-1 line reopens as skipped; the confirmed
    // one carries its depletion. Both are done, so both open folded.
    expect(find.text('55'), findsOneWidget);
    expect(find.text('Used: 4'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    // A skip is not part of the population that still needs counting, so
    // the header and the confirm bar agree there is nothing left to do.
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    expect(find.textContaining('not confirmed yet'), findsNothing);

    // Tapping the confirmed line open shows the number in the box that
    // recorded it: a plain "used" figure, entered directly.
    await _tap(tester, find.text('Al pastor'));
    expect(find.widgetWithText(TextFormField, 'Used'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'How many are left?'),
      findsNothing,
    );
    expect(find.text('4'), findsOneWidget);
  });
}
