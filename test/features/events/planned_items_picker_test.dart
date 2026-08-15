/// The rebuilt planned-items picker (proposal §3): a full-height sheet with
/// search pinned top, folder sections each carrying a running count and an
/// "Add all", and the running tally pinned at the bottom as the Done button.
/// Sixty items across six folders must be six decisions plus exceptions —
/// that exact flow is pinned here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/events/presentation/planned_items_picker.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

/// The picker list's scrollable: the sheet holds two (the search field's
/// editable text and the ListView) — the ListView is the last.
Finder pickerList() => find
    .descendant(
      of: find.byType(PlannedItemsSheet),
      matching: find.byType(Scrollable),
    )
    .last;

/// The "Add all"/"Remove all" button on one section header row.
Finder sectionAction(String headerText, String action) => find.descendant(
  of: find.ancestor(of: find.text(headerText), matching: find.byType(Row)),
  matching: find.widgetWithText(TextButton, action),
);

void main() {
  testWidgets('sixty items across six folders: six Add-all decisions plus '
      'two exceptions', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    const folders = [
      'Cooked on site',
      'Bought ready to serve',
      'Fresh produce',
      'Bakery',
      'Drinks',
      'Disposables',
    ];
    await tester.runAsync(() async {
      for (final folder in folders) {
        final folderId = await folderIdByName(h, folder);
        for (var i = 1; i <= 10; i++) {
          await seedItem(
            h,
            name: '$folder item ${i.toString().padLeft(2, '0')}',
            folderId: folderId,
          );
        }
      }
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'The big one',
    );
    await tester.ensureVisible(find.text('Add items'));
    await tester.tap(find.text('Add items'));
    await tester.pumpAndSettle();

    // Six decisions: one Add all per folder section. scrollUntilVisible can
    // leave the header half-clipped at the sheet's bottom edge (where a tap
    // would hit the pinned Done bar instead) — ensureVisible squares it up.
    for (final folder in folders) {
      await tester.scrollUntilVisible(
        find.text('$folder · 0 of 10'),
        200,
        scrollable: pickerList(),
      );
      await tester.ensureVisible(find.text('$folder · 0 of 10'));
      await tester.pump();
      await tester.tap(sectionAction('$folder · 0 of 10', 'Add all'));
      await tester.pump();
      // The header now reports the section fully picked, and the action
      // flips to the way back out.
      expect(find.text('$folder · 10 of 10'), findsOneWidget);
      expect(sectionAction('$folder · 10 of 10', 'Remove all'), findsOneWidget);
    }
    expect(find.text('60 items picked · Done'), findsOneWidget);

    // The exceptions: untick two disposables.
    for (final name in ['Disposables item 01', 'Disposables item 02']) {
      await tester.scrollUntilVisible(
        find.text(name),
        200,
        scrollable: pickerList(),
      );
      await tester.ensureVisible(find.text(name));
      await tester.pump();
      await tester.tap(find.text(name));
      await tester.pump();
    }
    expect(find.text('58 items picked · Done'), findsOneWidget);
    expect(
      find.text('Disposables · 8 of 10', skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.text('58 items picked · Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();

    // The detail screen reads the same sections back.
    expect(find.text('Planned items (58)'), findsOneWidget);
    expect(find.text('Disposables · 8'), findsOneWidget);
    expect(find.text('Drinks · 10'), findsOneWidget);
    expect(find.text('Disposables item 01'), findsNothing);
    // Closing the sheet and leaving the form disposes providers; flush
    // drift's zero-duration stream-close timers before the test ends.
    await h.flushTimers(tester);
  });

  testWidgets('search pinned top filters every folder; quantity-free rows; '
      'counts live on the headers', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final drinks = await folderIdByName(h, 'Drinks');
      final disposables = await folderIdByName(h, 'Disposables');
      await seedItem(h, name: 'Lemonade', folderId: drinks);
      await seedItem(h, name: 'Cola', folderId: drinks);
      await seedItem(h, name: 'Napkins', folderId: disposables);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Fete');
    await tester.ensureVisible(find.text('Add items'));
    await tester.tap(find.text('Add items'));
    await tester.pumpAndSettle();

    // Empty folders never show — only sections with something to pick.
    expect(find.text('Drinks · 0 of 2'), findsOneWidget);
    expect(find.text('Disposables · 0 of 1'), findsOneWidget);
    expect(find.textContaining('Bakery'), findsNothing);
    // Quantity-free: rows are checkboxes, no quantity fields in the sheet.
    expect(
      find.descendant(
        of: find.byType(PlannedItemsSheet),
        matching: find.byType(TextFormField),
      ),
      findsNothing,
    );

    await tester.tap(sectionAction('Drinks · 0 of 2', 'Add all'));
    await tester.pump();
    expect(find.text('Drinks · 2 of 2'), findsOneWidget);
    expect(find.text('2 items picked · Done'), findsOneWidget);

    // Search reaches across folders and hides what does not match. The
    // sheet's only TextField is the pinned search box.
    final searchField = find.descendant(
      of: find.byType(PlannedItemsSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'nap');
    await tester.pump();
    expect(find.text('Napkins'), findsOneWidget);
    expect(find.text('Lemonade'), findsNothing);
    expect(find.textContaining('Drinks ·'), findsNothing);
    expect(find.text('Disposables · 0 of 1'), findsOneWidget);

    await tester.tap(find.text('Napkins'));
    await tester.pump();
    expect(find.text('3 items picked · Done'), findsOneWidget);

    // Clearing the search brings the sections back with the ticks kept.
    await tester.enterText(searchField, '');
    await tester.pump();
    expect(find.text('Drinks · 2 of 2'), findsOneWidget);
    expect(find.text('Disposables · 1 of 1'), findsOneWidget);

    // One exception: untick Cola.
    await tester.tap(find.text('Cola'));
    await tester.pump();
    expect(find.text('Drinks · 1 of 2'), findsOneWidget);

    await tester.tap(find.text('2 items picked · Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Lemonade'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Napkins'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Cola'), findsNothing);
    await h.flushTimers(tester);
  });
}
