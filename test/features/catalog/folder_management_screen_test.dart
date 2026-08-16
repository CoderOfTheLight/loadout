/// FolderManagementScreen widget tests: the owner's short managed list —
/// rename, add, drag-reorder, archive (one-way, items to Unfiled), the
/// folder's default answer to the one question, and the "comes along to
/// every event" flag. Every write goes through `CatalogService`; the
/// assertions read the service streams back, never the widgets alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/folder_chip.dart';
import 'package:loadout/core/folder_appearance.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/catalog/domain/folder.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/folder_management_screen.dart';
import 'package:loadout/features/catalog/presentation/unfiled_chip.dart';

import '../../support/app_harness.dart';

Future<AppHarness> startWorkspace(WidgetTester tester) async => (await tester
    .runAsync(() => AppHarness.start(state: AppHarnessState.workspace)))!;

Future<List<Folder>> readFolders(AppHarness h) =>
    h.read(catalogServiceProvider).watchFolders().first;

Future<Map<String, String>> folderIdsByName(AppHarness h) async {
  final folders = await readFolders(h);
  return {for (final folder in folders) folder.name: folder.id.value};
}

/// Opens the per-folder editor sheet by tapping the folder's row.
Future<void> openEditor(WidgetTester tester, String folderName) async {
  final row = find.text(folderName);
  await tester.scrollUntilVisible(
    row,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the folders in the owner\'s order with counts and '
      'their default answers', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      final created = await h
          .read(catalogServiceProvider)
          .createItem(
            ItemDraft(name: 'Croissants', folderId: folders['Bakery']),
          );
      expect(created, isA<Ok<String>>());
    });

    await h.pumpScreen(tester, const FolderManagementScreen());

    // Starter order, not the alphabet.
    expect(
      tester.getTopLeft(find.text('Cooked on site')).dy,
      lessThan(tester.getTopLeft(find.text('Bought ready to serve')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Fresh produce')).dy,
      lessThan(tester.getTopLeft(find.text('Bakery')).dy),
    );
    // Every row carries the folder's identity chip (design-spec §3).
    expect(find.byType(FolderChip), findsNWidgets(8));
    // Counts (right-aligned per spec §3) and default answers read from the
    // workspace: Bakery holds the one item.
    Finder inRow(String folderName, Finder matching) => find.descendant(
      of: find.widgetWithText(ListTile, folderName),
      matching: matching,
    );
    expect(inRow('Bakery', find.text('1')), findsOneWidget);
    expect(inRow('Drinks', find.text('0')), findsOneWidget);
    expect(find.text('More people, more of it'), findsNWidgets(7));
    // Only Cleaning & setup starts as per-event.
    expect(find.text('About the same every event'), findsOneWidget);
    expect(
      inRow('Cleaning & setup', find.text('About the same every event')),
      findsOneWidget,
    );
  });

  testWidgets('rename writes through the service and refuses a duplicate '
      'name inline', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const FolderManagementScreen());
    await openEditor(tester, 'Bakery');
    // The identity controls sit above; bring the rename row into view.
    await tester.ensureVisible(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    // The live-name rule surfaces inline, in the dialog.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Folder name'),
      'Drinks',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(
      find.text('A folder with this name already exists.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Folder name'),
      'Breads & bakes',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    final folders = await tester.runAsync(() => readFolders(h));
    final names = [for (final folder in folders!) folder.name];
    expect(names, contains('Breads & bakes'));
    expect(names, isNot(contains('Bakery')));
    // The open editor sheet follows the stream.
    expect(find.text('Breads & bakes'), findsWidgets);
    await h.flushTimers(tester);
  });

  testWidgets('adding a folder appends it to the end of the order and '
      'auto-assigns the next hue', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const FolderManagementScreen());
    // The FAB carries a word, never an icon alone (spec §2).
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New folder'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Folder name'),
      'Van gear',
    );
    // Scoped to the dialog: the list behind it words a row subtitle the
    // same way.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('About the same every event'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();

    final folders = await tester.runAsync(() => readFolders(h));
    expect(folders!.last.name, 'Van gear');
    expect(folders.last.position, 8);
    expect(folders.last.demandBasis, DemandBasis.perEvent);
    expect(folders.last.alwaysPlanned, isFalse);
    // Spec §3 assignment: the eight starters use all eight hues, so the
    // ninth folder wraps to the top of the table order.
    expect(folders.last.hue, FolderHue.fern);
  });

  testWidgets('the editor sheet writes hue and icon through the service and '
      'previews them live', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const FolderManagementScreen());
    await openEditor(tester, 'Drinks');

    // The eight named swatches (spec §3), Lake preselected via the seeded
    // starter appearance.
    for (final hue in FolderHue.values) {
      expect(find.byKey(ValueKey('hue-${hue.dbValue}')), findsOneWidget);
    }

    // Pick Plum: an immediate service write, and the sheet's live preview
    // chip re-renders from the stream.
    await tester.tap(find.byKey(const ValueKey('hue-plum')));
    await tester.pumpAndSettle();
    var folders = await tester.runAsync(() => readFolders(h));
    var drinks = folders!.firstWhere((folder) => folder.name == 'Drinks');
    expect(drinks.hue, FolderHue.plum);
    // The seeded starter icon is untouched — hue-only write, not both.
    expect(drinks.iconName, 'local_drink');

    // Pick a new icon from the curated grid.
    await tester.ensureVisible(find.byKey(const ValueKey('icon-coffee')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('icon-coffee')));
    await tester.pumpAndSettle();
    folders = await tester.runAsync(() => readFolders(h));
    drinks = folders!.firstWhere((folder) => folder.name == 'Drinks');
    expect(drinks.iconName, 'coffee');
    expect(drinks.hue, FolderHue.plum);

    // The preview chip in the sheet now draws the chosen identity.
    final chips = tester.widgetList<FolderChip>(find.byType(FolderChip));
    expect(
      chips.any(
        (chip) => chip.hue == FolderHue.plum && chip.iconName == 'coffee',
      ),
      isTrue,
    );
    await h.flushTimers(tester);
  });

  testWidgets('archiving confirms in plain words, moves its items to '
      'Unfiled and never deletes them', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final itemId = (await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      final created = await h
          .read(catalogServiceProvider)
          .createItem(
            ItemDraft(name: 'Carrots', folderId: folders['Fresh produce']),
          );
      return (created as Ok<String>).value;
    }))!;

    await h.pumpScreen(tester, const FolderManagementScreen());
    await openEditor(tester, 'Fresh produce');
    await tester.ensureVisible(find.text('Archive folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive folder'));
    await tester.pumpAndSettle();

    expect(find.text("Archive 'Fresh produce'?"), findsOneWidget);
    expect(find.textContaining('Its items move to Unfiled'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();

    // Gone from the live list; the item survives, unfiled.
    final folders = await tester.runAsync(() => readFolders(h));
    expect([
      for (final folder in folders!) folder.name,
    ], isNot(contains('Fresh produce')));
    final detail = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItem(itemId).first,
    );
    expect(detail!.item.name, 'Carrots');
    expect(detail.item.folderId, isNull);
    await h.flushTimers(tester);
  });

  testWidgets('the default answer and the comes-along flag write through '
      'the service', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const FolderManagementScreen());
    await openEditor(tester, 'Drinks');

    // Flip the folder's default answer to the one question. Scoped to the
    // sheet: the list behind it words a row subtitle the same way.
    final inSheet = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('About the same every event'),
    );
    await tester.ensureVisible(inSheet);
    await tester.pumpAndSettle();
    await tester.tap(inSheet);
    await tester.pumpAndSettle();

    // And mark it as coming along to every event.
    await tester.ensureVisible(find.text('Comes along to every event'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final folders = await tester.runAsync(() => readFolders(h));
    final drinks = folders!.firstWhere((folder) => folder.name == 'Drinks');
    expect(drinks.demandBasis, DemandBasis.perEvent);
    expect(drinks.alwaysPlanned, isTrue);
    await h.flushTimers(tester);
  });

  testWidgets('dragging a row reorders through the service', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const FolderManagementScreen());

    // Drag the first folder's handle down past the second row.
    await tester.timedDrag(
      find.byIcon(Icons.drag_indicator).first,
      const Offset(0, 90),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    final folders = await tester.runAsync(() => readFolders(h));
    // It moved down through the service-backed order (the exact landing
    // slot depends on drag physics; what is pinned is that the write went
    // through and no folder was lost).
    expect(folders!.first.name, 'Bought ready to serve');
    expect(
      folders.indexWhere((folder) => folder.name == 'Cooked on site'),
      greaterThan(0),
    );
    // The reorder listed every live folder exactly once: all 8 survive.
    expect(folders, hasLength(8));
  });

  testWidgets('with every folder archived the screen explains itself and '
      'offers to add one', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      for (final folder in await readFolders(h)) {
        final result = await h
            .read(catalogServiceProvider)
            .archiveFolder(folder.id.value);
        expect(result, isA<Ok<void>>());
      }
    });

    await h.pumpScreen(tester, const FolderManagementScreen());

    expect(find.text('No folders yet'), findsOneWidget);
    expect(find.text('Add a folder'), findsOneWidget);

    await tester.tap(find.text('Add a folder'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Folder name'),
      'Sales table',
    );
    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();

    // The archived starter's name is free again — live-name uniqueness.
    final folders = await tester.runAsync(() => readFolders(h));
    expect(folders!.single.name, 'Sales table');
    // Let the stream event land in the widget tree before asserting on it.
    await tester.pumpAndSettle();
    expect(find.text('No folders yet'), findsNothing);
  });

  testWidgets('Unfiled is a fixed row after the folders: neutral chip, live '
      'count, caption — no drag handle, no editor, never hidden', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const FolderManagementScreen());

    // Present even at zero items, after the last draggable folder.
    final unfiledRow = find.widgetWithText(ListTile, 'Unfiled');
    await tester.scrollUntilVisible(
      unfiledRow,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(unfiledRow, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Sales table')).dy,
      lessThan(tester.getTopLeft(find.text('Unfiled')).dy),
    );
    // Identity: the neutral inbox chip, never a FolderChip; a one-line
    // caption says what it is; the count starts at zero.
    expect(
      find.descendant(of: unfiledRow, matching: find.byType(UnfiledChip)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: unfiledRow, matching: find.byType(FolderChip)),
      findsNothing,
    );
    expect(find.textContaining('Items not yet in a folder'), findsOneWidget);
    expect(
      find.descendant(of: unfiledRow, matching: find.text('0')),
      findsOneWidget,
    );
    // Not draggable: no drag handle on the fixed row (the 8 folder rows
    // keep theirs).
    expect(
      find.descendant(
        of: unfiledRow,
        matching: find.byIcon(Icons.drag_indicator),
      ),
      findsNothing,
    );
    // Not editable: tapping opens no editor sheet.
    await tester.tap(unfiledRow);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    // The count is live: unfile an item and the row says 1.
    await tester.runAsync(() async {
      final created = await h
          .read(catalogServiceProvider)
          .createItem(const ItemDraft(name: 'Tortillas'));
      expect(created, isA<Ok<String>>());
    });
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: unfiledRow, matching: find.text('1')),
      findsOneWidget,
    );
    await h.flushTimers(tester);
  });
}
