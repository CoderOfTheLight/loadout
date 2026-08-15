/// FolderManagementScreen widget tests: the owner's short managed list —
/// rename, add, drag-reorder, archive (one-way, items to Unfiled), the
/// folder's default answer to the one question, and the "comes along to
/// every event" flag. Every write goes through `CatalogService`; the
/// assertions read the service streams back, never the widgets alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/catalog/domain/folder.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/folder_management_screen.dart';

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
    // Counts and default answers read from the workspace.
    expect(
      find.text('More people, more of it · 1 item'),
      findsOneWidget, // Bakery
    );
    expect(find.text('More people, more of it · 0 items'), findsWidgets);
    // Only Cleaning & setup starts as per-event.
    expect(find.text('About the same every event · 0 items'), findsOneWidget);
  });

  testWidgets('rename writes through the service and refuses a duplicate '
      'name inline', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const FolderManagementScreen());
    await openEditor(tester, 'Bakery');
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

  testWidgets('adding a folder appends it to the end of the order', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const FolderManagementScreen());
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Folder name'),
      'Van gear',
    );
    await tester.tap(find.text('About the same every event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();

    final folders = await tester.runAsync(() => readFolders(h));
    expect(folders!.last.name, 'Van gear');
    expect(folders.last.position, 8);
    expect(folders.last.demandBasis, DemandBasis.perEvent);
    expect(folders.last.alwaysPlanned, isFalse);
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

    // Flip the folder's default answer to the one question.
    await tester.ensureVisible(find.text('About the same every event'));
    await tester.tap(find.text('About the same every event'));
    await tester.pumpAndSettle();

    // And mark it as coming along to every event.
    await tester.ensureVisible(find.text('Comes along to every event'));
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
}
