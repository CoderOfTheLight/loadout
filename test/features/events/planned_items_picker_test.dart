/// The rebuilt planned-items picker (design-spec §6): a full-height sheet
/// with search pinned top; §4 folder section headers — 24 dp chip, name,
/// live "3 of 12" fraction, and the labeled "Add all (9)" / "Remove all"
/// bulk action with the consequence count in the label; 56 dp checkbox rows
/// whose selected state is checkbox + folder-tint fill + name at w700; and
/// the docked tally bar — "12 items · 4 folders" with Done as a real
/// button. Sixty items across six folders must be six decisions plus a
/// handful of exceptions — that exact flow is pinned here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/widgets/folder_chip.dart';
import 'package:loadout/features/events/presentation/planned_items_picker.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

/// The picker body's scrollable: the sheet holds the search field's
/// editable text and the sectioned CustomScrollView — the list is the last.
Finder pickerList() => find
    .descendant(
      of: find.byType(PlannedItemsSheet),
      matching: find.byType(Scrollable),
    )
    .last;

/// The §4 section header row for [folderName]: chip, name, fraction, bulk
/// action all live on one Row.
Finder sectionHeader(String folderName) =>
    find.ancestor(of: find.text(folderName), matching: find.byType(Row));

/// A widget inside [folderName]'s section header row.
Finder inHeader(String folderName, Finder matching) =>
    find.descendant(of: sectionHeader(folderName), matching: matching);

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

    // Six decisions: one labeled Add-all per folder section, its count
    // stating the consequence before the tap. scrollUntilVisible can leave
    // the header half-clipped at the sheet's bottom edge (where a tap would
    // hit the docked tally bar instead) — ensureVisible squares it up.
    for (final folder in folders) {
      await tester.scrollUntilVisible(
        find.text(folder),
        200,
        scrollable: pickerList(),
      );
      await tester.ensureVisible(find.text(folder));
      await tester.pump();
      expect(inHeader(folder, find.text('0 of 10')), findsOneWidget);
      await tester.tap(
        inHeader(folder, find.widgetWithText(TextButton, 'Add all (10)')),
      );
      await tester.pump();
      // The header now reports the section fully picked, and the action
      // flips to the way back out.
      expect(inHeader(folder, find.text('10 of 10')), findsOneWidget);
      expect(
        inHeader(folder, find.widgetWithText(TextButton, 'Remove all')),
        findsOneWidget,
      );
    }
    // The docked tally: items and the folders they span, Done as a button.
    expect(find.text('60 items · 6 folders'), findsOneWidget);

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
    expect(find.text('58 items · 6 folders'), findsOneWidget);
    expect(inHeader('Disposables', find.text('8 of 10')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
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

    // Empty folders never show — only sections with something to pick —
    // and every section header carries its folder's identity chip.
    expect(inHeader('Drinks', find.text('0 of 2')), findsOneWidget);
    expect(inHeader('Disposables', find.text('0 of 1')), findsOneWidget);
    expect(find.textContaining('Bakery'), findsNothing);
    expect(inHeader('Drinks', find.byType(FolderChip)), findsOneWidget);
    // Quantity-free: rows are checkboxes, no quantity fields in the sheet.
    expect(
      find.descendant(
        of: find.byType(PlannedItemsSheet),
        matching: find.byType(TextFormField),
      ),
      findsNothing,
    );

    await tester.tap(
      inHeader('Drinks', find.widgetWithText(TextButton, 'Add all (2)')),
    );
    await tester.pump();
    expect(inHeader('Drinks', find.text('2 of 2')), findsOneWidget);
    expect(find.text('2 items · 1 folder'), findsOneWidget);
    // Selected rows carry the checkbox-plus-weight treatment (spec §6):
    // never the checkbox alone at arm's length.
    expect(
      tester.widget<Text>(find.text('Lemonade')).style?.fontWeight,
      FontWeight.w700,
    );

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
    expect(find.text('Drinks'), findsNothing);
    expect(inHeader('Disposables', find.text('0 of 1')), findsOneWidget);

    await tester.tap(find.text('Napkins'));
    await tester.pump();
    expect(find.text('3 items · 2 folders'), findsOneWidget);

    // Clearing the search brings the sections back with the ticks kept.
    await tester.enterText(searchField, '');
    await tester.pump();
    expect(inHeader('Drinks', find.text('2 of 2')), findsOneWidget);
    expect(inHeader('Disposables', find.text('1 of 1')), findsOneWidget);

    // One exception: untick Cola.
    await tester.tap(find.text('Cola'));
    await tester.pump();
    expect(inHeader('Drinks', find.text('1 of 2')), findsOneWidget);

    expect(find.text('2 items · 2 folders'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Lemonade'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Napkins'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Cola'), findsNothing);
    await h.flushTimers(tester);
  });
}
