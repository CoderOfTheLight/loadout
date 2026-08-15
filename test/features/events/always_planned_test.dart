/// Always-planned folders (proposal §3): a folder marked "comes along to
/// every event" has its live items pre-added on creation — the standing
/// stuff is a review, not forty taps. The new-event form previews what will
/// arrive and which folder brings it; the detail sections show the folder
/// that brought each item, so unticking (via edit, where updates never
/// re-add) is informed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

void main() {
  testWidgets('always-planned items arrive on creation, show their folder, '
      'and an informed untick sticks', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final cleaning = await folderIdByName(h, 'Cleaning & setup');
      await seedItem(h, name: 'Dish soap', folderId: cleaning);
      await seedItem(h, name: 'Paper towels', folderId: cleaning);
      await markFolderAlwaysPlanned(h, 'Cleaning & setup');
      await seedItem(h, name: 'Tortillas');
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Village fete',
    );

    // The form says what will arrive and which folder brings it.
    expect(find.text('Comes along to every event'), findsOneWidget);
    expect(
      find.text('Cleaning & setup: Dish soap, Paper towels'),
      findsOneWidget,
    );

    // The owner picks only Tortillas by hand.
    await tester.ensureVisible(find.text('Add items'));
    await tester.tap(find.text('Add items'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tortillas'));
    await tester.pump();
    await tester.tap(find.text('1 item picked · Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();

    // Creation composed the standing stuff in; the sections say which
    // folder brought it.
    expect(find.text('Planned items (3)'), findsOneWidget);
    expect(find.text('Cleaning & setup · 2'), findsOneWidget);
    expect(find.text('Unfiled · 1'), findsOneWidget);
    expect(find.text('Dish soap'), findsOneWidget);
    expect(find.text('Paper towels'), findsOneWidget);

    // Informed untick: edit, remove Dish soap. Updates never re-compose,
    // so the removal sticks.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(InputChip, 'Dish soap');
    await tester.ensureVisible(chip);
    await tester.tap(
      find.descendant(of: chip, matching: find.byTooltip('Remove from plan')),
    );
    await tester.pump();
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();

    expect(find.text('Planned items (2)'), findsOneWidget);
    expect(find.text('Cleaning & setup · 1'), findsOneWidget);
    expect(find.text('Dish soap'), findsNothing);
    expect(find.text('Paper towels'), findsOneWidget);
    // Leaving routes/sheets disposes providers; flush drift's stream-close
    // timers before the test ends.
    await h.flushTimers(tester);
  });
}
