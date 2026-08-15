/// "Copy items from a previous event" (proposal §3): choose an event, its
/// still-live planned list arrives pre-ticked in the picker, untick what
/// differs. Uses EventService.clonePlannedItemsFrom — archived items never
/// ride along.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

void main() {
  testWidgets('clone arrives pre-ticked, untick what differs, archived '
      'items stay behind', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final disposables = await folderIdByName(h, 'Disposables');
      final drinks = await folderIdByName(h, 'Drinks');
      final plates = await seedItem(
        h,
        name: 'Paper plates',
        folderId: disposables,
      );
      final lemonade = await seedItem(h, name: 'Lemonade', folderId: drinks);
      final tortillas = await seedItem(h, name: 'Tortillas');
      await seedEvent(
        h,
        name: 'Spring fair',
        date: '2026-05-01',
        exposure: 150,
        itemIds: [plates, lemonade, tortillas],
      );
      // Archived since: the clone must not carry it forward.
      await unwrap(
        h
            .read(catalogServiceProvider)
            .setArchived(itemId: tortillas, archived: true),
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Summer fair',
    );
    await tester.ensureVisible(find.text('Copy items from a previous event'));
    await tester.tap(find.text('Copy items from a previous event'));
    await tester.pumpAndSettle();

    // The chooser explains itself and lists the previous event.
    expect(
      find.text('Its list arrives pre-ticked — untick what differs.'),
      findsOneWidget,
    );
    expect(find.text('2026-05-01 · Planned'), findsOneWidget);
    await tester.tap(find.text('Spring fair'));
    await tester.pumpAndSettle();

    // The picker opened pre-ticked with the two still-live items.
    expect(find.text('2 items picked · Done'), findsOneWidget);
    expect(find.text('Disposables · 1 of 1'), findsOneWidget);
    expect(find.text('Drinks · 1 of 1'), findsOneWidget);
    expect(find.text('Tortillas'), findsNothing);

    // Untick what differs this time.
    await tester.tap(find.text('Lemonade'));
    await tester.pump();
    expect(find.text('1 item picked · Done'), findsOneWidget);
    await tester.tap(find.text('1 item picked · Done'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Paper plates'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Lemonade'), findsNothing);

    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(find.text('Planned items (1)'), findsOneWidget);
    expect(find.text('Disposables · 1'), findsOneWidget);
    // Leaving routes/sheets disposes providers; drift closes their query
    // streams on zero-duration timers — flush them before the test ends.
    await h.flushTimers(tester);
  });

  testWidgets('with no other events the chooser says so instead of a dead '
      'list', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() => seedItem(h, name: 'Tortillas'));

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await tester.ensureVisible(find.text('Copy items from a previous event'));
    await tester.tap(find.text('Copy items from a previous event'));
    await tester.pumpAndSettle();

    expect(find.text('No other events to copy from yet.'), findsOneWidget);
    await h.flushTimers(tester);
  });
}
