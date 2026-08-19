/// ItemListScreen widget tests, rebuilt around folder sections (folders
/// proposal §3): the catalog reads in the owner's packing order under
/// pinned, collapsible headers; the chip row jumps to a folder; search on
/// top searches everything; Unfiled renders last; Archived only via the
/// toggle; and the whole thing stays lazy at 150 items across 8 folders.
///
/// Deliberately superseded pins from the flat-list era (the §12.8 free-text
/// category chips): chips no longer FILTER by category text — they JUMP to
/// folder sections. The category-chip filter test is replaced by the
/// jump-to-folder test below.
///
/// v5 (owner's rulings) — pinned below: table-like rows (amount+unit as
/// the LEADING column, aligned per section; the per-row FolderChip dropped
/// inside folder sections, a neutral UnfiledChip kept on Unfiled rows);
/// the first-class per-row "Move to folder…" overflow (a folder's ONLY
/// item included); and recipe-output rows expanding into their lines
/// (linked lines as real item rows, unlinked dimmed with "Add to items").
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/theme.dart';
import 'package:loadout/app/widgets/empty_state.dart';
import 'package:loadout/app/widgets/folder_chip.dart';
import 'package:loadout/core/folder_appearance.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/folder_management_screen.dart';
import 'package:loadout/features/catalog/presentation/item_list_screen.dart';
import 'package:loadout/features/catalog/presentation/unfiled_chip.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';
import 'package:loadout/features/recipes/presentation/recipe_detail_screen.dart';

import '../../support/app_harness.dart';

Future<String> seedItem(
  AppHarness h, {
  required String name,
  String? folderId,
  String? category,
  String? unitLabel,
  Quantity? servesPerUnit,
  Money? unitPrice,
  // Legacy schema-v1 shape; nothing asks for these any more.
  ItemUnit unit = ItemUnit.each,
  int packWhole = 1,
}) async {
  final result = await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(
          name: name,
          unitLabel: unitLabel,
          servesPerUnit: servesPerUnit,
          unitPrice: unitPrice,
          folderId: folderId,
          unit: unit,
          packSize: Quantity.whole(packWhole),
          category: category,
        ),
      );
  return (result as Ok<String>).value;
}

/// WCAG 2.2 contrast ratio between two opaque colours — the same formula
/// the theme builds its pairs with, measured here on what actually painted.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The effective hue of the starter folder called [name].
Future<FolderHue> folderHue(AppHarness h, String name) async {
  final folders = await h.read(catalogServiceProvider).watchFolders().first;
  return folders.firstWhere((folder) => folder.name == name).effectiveHue;
}

Future<void> seedMovement(
  AppHarness h,
  String itemId, {
  MovementKind kind = MovementKind.receive,
  int whole = 5,
}) async {
  final result = await h
      .read(inventoryServiceProvider)
      .record(
        MovementFormDraft(
          itemId: itemId,
          kind: kind,
          quantity: Quantity.whole(whole),
        ),
      );
  expect(result, isA<Ok<Object?>>());
}

/// Fresh workspaces seed the eight starter folders; this maps their names
/// (and any added later) to ids.
Future<Map<String, String>> folderIdsByName(AppHarness h) async {
  final folders = await h.read(catalogServiceProvider).watchFolders().first;
  return {for (final folder in folders) folder.name: folder.id.value};
}

Future<AppHarness> startWorkspace(WidgetTester tester) async => (await tester
    .runAsync(() => AppHarness.start(state: AppHarnessState.workspace)))!;

/// A text inside the sectioned list itself (headers + rows live inside
/// SliverMainAxisGroups) — never the identically-labeled jump chip in the
/// floating search region.
Finder inList(String text) => find.descendant(
  of: find.byType(SliverMainAxisGroup),
  matching: find.text(text),
);

void main() {
  testWidgets('sections render in the owner\'s folder order, items under '
      'their own folder', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
      await seedItem(h, name: 'Water', folderId: folders['Drinks']);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    // Starter order: … Fresh produce (2) · Bakery (3) · Drinks (4) …
    final bakeryY = tester.getTopLeft(inList('Bakery')).dy;
    final croissantsY = tester.getTopLeft(inList('Croissants')).dy;
    final drinksY = tester.getTopLeft(inList('Drinks')).dy;
    final waterY = tester.getTopLeft(inList('Water')).dy;
    expect(bakeryY, lessThan(croissantsY));
    expect(croissantsY, lessThan(drinksY));
    expect(drinksY, lessThan(waterY));

    // Folder order is the owner's, not the alphabet: swap Bakery and
    // Drinks through the service and the sections follow.
    await tester.runAsync(() async {
      final folders = await h.read(catalogServiceProvider).watchFolders().first;
      final ids = [for (final folder in folders) folder.id.value];
      final byName = {
        for (final folder in folders) folder.name: folder.id.value,
      };
      final bakeryIndex = ids.indexOf(byName['Bakery']!);
      final drinksIndex = ids.indexOf(byName['Drinks']!);
      ids[bakeryIndex] = byName['Drinks']!;
      ids[drinksIndex] = byName['Bakery']!;
      final result = await h.read(catalogServiceProvider).reorderFolders(ids);
      expect(result, isA<Ok<void>>());
    });
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(inList('Drinks')).dy,
      lessThan(tester.getTopLeft(inList('Bakery')).dy),
    );
    expect(
      tester.getTopLeft(inList('Water')).dy,
      lessThan(tester.getTopLeft(inList('Croissants')).dy),
    );
  });

  testWidgets('unfiled items sit in an Unfiled section at the end, with '
      'how-many-you-have and no unit caption', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final tortillas = await seedItem(
        h,
        name: 'Tortillas',
        category: 'Bread',
        servesPerUnit: Quantity.whole(4),
      );
      // A migrated schema-v1 row that really is measured.
      await seedItem(h, name: 'Salsa', unit: ItemUnit.litre);
      await seedMovement(h, tortillas, whole: 5);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    // Reveal the Unfiled section (it renders after the 8 starter folders).
    await tester.dragUntilVisible(
      inList('Tortillas'),
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(inList('Unfiled')).dy,
      lessThan(tester.getTopLeft(inList('Tortillas')).dy),
    );
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Bread · One serves 4'), findsOneWidget);
    expect(find.textContaining('Pack of'), findsNothing);
    expect(find.text('5 each'), findsNothing);
    // The legacy row keeps its unit, so 0 litres is never read as 0 things.
    expect(inList('Salsa'), findsOneWidget);
    expect(find.text('0 L'), findsOneWidget);
  });

  testWidgets('negative on-hand is shown signed with a warning', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final id = await seedItem(h, name: 'Tortillas');
      await seedMovement(h, id, kind: MovementKind.waste, whole: 2);
    });

    await h.pumpScreen(tester, const ItemListScreen());
    await tester.dragUntilVisible(
      inList('Tortillas'),
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    expect(find.text('−2'), findsOneWidget);
    expect(find.text('Negative'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  testWidgets('search searches everything and hides sections with no '
      'matches', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
      await seedItem(h, name: 'Tortillas'); // unfiled
    });

    await h.pumpScreen(tester, const ItemListScreen());

    await tester.enterText(find.byType(SearchBar), 'tor');
    await tester.pumpAndSettle();

    // The unfiled match surfaces under its header; folders with no match
    // (and every empty starter folder) disappear while searching.
    expect(inList('Tortillas'), findsOneWidget);
    expect(inList('Unfiled'), findsOneWidget);
    expect(inList('Croissants'), findsNothing);
    expect(inList('Bakery'), findsNothing);
    expect(inList('Cooked on site'), findsNothing);

    await tester.enterText(find.byType(SearchBar), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No items match your search.'), findsOneWidget);
  });

  testWidgets('archived items appear only via the Show archived toggle, in '
      'an Archived section after everything', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, name: 'Tortillas');
      final retired = await seedItem(h, name: 'Old cups');
      final result = await h
          .read(catalogServiceProvider)
          .setArchived(itemId: retired, archived: true);
      expect(result, isA<Ok<void>>());
    });

    await h.pumpScreen(tester, const ItemListScreen());
    expect(inList('Old cups'), findsNothing);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckedPopupMenuItem<String>));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      inList('Old cups'),
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(inList('Old cups'), findsOneWidget);
    // The Archived section renders after Unfiled — never mixed into live
    // folders.
    expect(
      tester.getTopLeft(inList('Unfiled')).dy,
      lessThan(tester.getTopLeft(inList('Archived').first).dy),
    );
  });

  testWidgets('a collapsed section keeps its count and stays collapsed for '
      'the session', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(
        h,
        name: 'Minestrone (batch)',
        folderId: folders['Cooked on site'],
      );
    });

    await h.pumpScreen(tester, const ItemListScreen());
    expect(inList('Minestrone (batch)'), findsOneWidget);

    // The header chevron is a single rotating glyph (spec §4:
    // AnimatedRotation), pointing down while expanded.
    AnimatedRotation chevron() => tester.widget<AnimatedRotation>(
      find.descendant(
        of: find.ancestor(
          of: inList('Cooked on site'),
          matching: find.byType(Row),
        ),
        matching: find.byType(AnimatedRotation),
      ),
    );
    expect(chevron().turns, 0);

    await tester.tap(inList('Cooked on site'));
    await tester.pumpAndSettle();

    // Collapsed: rows gone, chevron rotated to point right, count still on
    // the header.
    expect(inList('Minestrone (batch)'), findsNothing);
    expect(chevron().turns, -0.25);
    expect(inList('1'), findsOneWidget);

    // Leaving the list and coming back keeps the collapse (same session).
    await h.pumpScreen(tester, const ItemListScreen());
    expect(inList('Minestrone (batch)'), findsNothing);
    expect(chevron().turns, -0.25);

    // Tapping again expands.
    await tester.tap(inList('Cooked on site'));
    await tester.pumpAndSettle();
    expect(inList('Minestrone (batch)'), findsOneWidget);
  });

  testWidgets('section headers are semantic headers', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(
        h,
        name: 'Minestrone (batch)',
        folderId: folders['Cooked on site'],
      );
    });
    final handle = tester.ensureSemantics();

    await h.pumpScreen(tester, const ItemListScreen());

    expect(
      tester.getSemantics(inList('Cooked on site')),
      matchesSemantics(
        isHeader: true,
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        label: 'Cooked on site, 1 item',
      ),
    );
    handle.dispose();
  });

  testWidgets('150 items across 8 folders build lazily, and the chip row '
      'jumps straight to a folder', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await h.read(catalogServiceProvider).watchFolders().first;
      expect(folders, hasLength(8));
      for (var i = 0; i < 150; i++) {
        final name = 'Item ${'${i + 1}'.padLeft(3, '0')}';
        await seedItem(h, name: name, folderId: folders[i % 8].id.value);
      }
    });

    await h.pumpScreen(tester, const ItemListScreen());

    // Lazy slivers: nowhere near all 150 rows exist after the first frame.
    expect(tester.widgetList(find.byType(ListTile)).length, lessThan(60));
    // All eight sections are reachable, but only the top ones are built.
    expect(inList('Cooked on site'), findsOneWidget);
    expect(inList('Sales table'), findsNothing);

    // The chip row jumps to the last folder. Its chip sits past the right
    // edge of the horizontal jump row, so bring it into view first.
    expect(find.byKey(itemListJumpRowKey), findsOneWidget);
    await tester.ensureVisible(find.text('Sales table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales table'));
    await tester.pumpAndSettle();

    // Landed: the Sales table header is pinned on screen with its items
    // (i % 8 == 7 → Item 008, 016, …).
    expect(inList('Sales table'), findsOneWidget);
    expect(inList('Item 008'), findsOneWidget);
    expect(tester.widgetList(find.byType(ListTile)).length, lessThan(60));

    // And the very end of the catalog is reachable by scrolling.
    await tester.dragUntilVisible(
      inList('Item 144'),
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(inList('Item 144'), findsOneWidget);
  });

  testWidgets('empty catalog shows the §9 empty state, folders or not', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing in your list yet'), findsOneWidget);
    // Says what an item IS, not just that there are none.
    expect(
      find.textContaining('Items are the things you bring and sell'),
      findsOneWidget,
    );
    expect(find.text('Add your first item'), findsOneWidget);
    // The 8 starter folders exist, but an empty catalog never renders as
    // eight empty headers.
    expect(find.text('Cooked on site'), findsNothing);
  });

  testWidgets('rows are table-like: amount+unit leads, names align per '
      'section, and the folder chip is gone inside folder sections', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      final packs = await seedItem(
        h,
        name: 'Snack packs',
        folderId: folders['Bakery'],
        unitLabel: 'packages',
      );
      await seedItem(h, name: 'Rolls', folderId: folders['Bakery']);
      await seedMovement(h, packs, whole: 12);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    // Amount + label render as one cell ("12 packages"), bare "0" without
    // a label — and the amount column LEADS the name.
    expect(inList('12 packages'), findsOneWidget);
    expect(
      tester.getTopLeft(inList('12 packages')).dx,
      lessThan(tester.getTopLeft(inList('Snack packs')).dx),
    );
    // One consistent column width per section: both names start at the
    // same x although the amounts differ in width.
    expect(
      tester.getTopLeft(inList('Snack packs')).dx,
      tester.getTopLeft(inList('Rolls')).dx,
    );
    // The per-row 40 dp chip is dropped inside folder sections — the only
    // FolderChips left are the 24 dp section-header ones.
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(FolderChip),
      ),
      findsNothing,
    );
  });

  testWidgets('Unfiled rows keep a neutral chip', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() => seedItem(h, name: 'Tortillas'));

    await h.pumpScreen(tester, const ItemListScreen());
    await tester.dragUntilVisible(
      inList('Tortillas'),
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Tortillas'),
        matching: find.byType(UnfiledChip),
      ),
      findsOneWidget,
    );
  });

  testWidgets("Move to folder… on a row moves a folder's ONLY item out — "
      'the first-class move the owner asked for', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      return seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
    }))!;

    await h.pumpScreen(tester, const ItemListScreen());

    await tester.tap(find.byTooltip('Options for Croissants'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder…'));
    await tester.pumpAndSettle();

    // The shared folder picker; choose Drinks.
    expect(find.text('Choose a folder'), findsOneWidget);
    await tester.tap(find.text('Drinks').last);
    await tester.pumpAndSettle();
    // Closing the sheet disposes its folder-list provider; drift closes
    // the stream behind it on a zero-duration timer — flush it.
    await h.flushTimers(tester);

    final detail = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItem(id).first,
    );
    final folders = await tester.runAsync(() => folderIdsByName(h));
    expect(detail!.item.folderId?.value, folders!['Drinks']);
    expect(find.text('Moved to Drinks.'), findsOneWidget);
    // The row now sits under the Drinks header.
    expect(
      tester.getTopLeft(inList('Drinks')).dy,
      lessThan(tester.getTopLeft(inList('Croissants')).dy),
    );
    expect(
      tester.getTopLeft(inList('Croissants')).dy,
      lessThan(tester.getTopLeft(inList('Disposables')).dy),
    );
    await h.flushTimers(tester);
  });

  testWidgets('a recipe-output row expands into the recipe: linked lines '
      'as real item rows, free lines dimmed with Add to items', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      final flour = await seedItem(
        h,
        name: 'Flour',
        folderId: folders['Bakery'],
      );
      final recipeId =
          (await h
                  .read(recipeServiceProvider)
                  .createRecipe(
                    RecipeFormDraft(
                      name: 'Granola',
                      yieldQuantity: Quantity.whole(4),
                      lines: [
                        RecipeFormLine(
                          itemId: flour,
                          quantityPerBatch: Quantity.whole(2),
                        ),
                        RecipeFormLine(
                          name: 'Honey',
                          unitLabel: 'cup',
                          quantityPerBatch: Quantity.fromMicros(500000),
                        ),
                      ],
                    ),
                  )
              as Ok<String>);
      final added = await h
          .read(recipeServiceProvider)
          .addToItems(
            recipeId: recipeId.value,
            folderId: folders['Cooked on site'],
          );
      expect(added, isA<Ok<String>>());
    });

    await h.pumpScreen(tester, const ItemListScreen());

    // Folded: the group's lines are not rows yet.
    expect(inList('Granola'), findsOneWidget);
    expect(find.text('Honey'), findsNothing);

    await tester.tap(find.byTooltip('Show ingredients'));
    await tester.pumpAndSettle();

    // The linked line renders as the Flour item's own row INSIDE the
    // group — between the Granola row and the next section header — and
    // wears the chip of the folder it actually lives in (Bakery), the one
    // 40 dp FolderChip on any row. (Flour's own Bakery row still exists
    // further down; sliver laziness may not have built it yet.)
    final flourY = tester.getTopLeft(inList('Flour').first).dy;
    expect(flourY, greaterThan(tester.getTopLeft(inList('Granola')).dy));
    expect(
      flourY,
      lessThan(tester.getTopLeft(inList('Bought ready to serve')).dy),
    );
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(FolderChip),
      ),
      findsOneWidget,
    );
    // The free line renders quietly under its own text with its amount
    // ("0.5 cup") and the way into the recipe's add flow.
    expect(inList('Honey'), findsOneWidget);
    expect(inList('0.5 cup'), findsOneWidget);
    expect(find.text('Add to items'), findsOneWidget);

    // Collapsing folds the lines away again.
    await tester.tap(find.byTooltip('Hide ingredients'));
    await tester.pumpAndSettle();
    expect(find.text('Honey'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets("a free line's Add to items leads into the recipe screen", (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      final recipeId =
          (await h
                  .read(recipeServiceProvider)
                  .createRecipe(
                    RecipeFormDraft(
                      name: 'Granola',
                      yieldQuantity: Quantity.whole(4),
                      lines: [
                        RecipeFormLine(
                          name: 'Honey',
                          unitLabel: 'cup',
                          quantityPerBatch: Quantity.fromMicros(500000),
                        ),
                      ],
                    ),
                  )
              as Ok<String>);
      final added = await h
          .read(recipeServiceProvider)
          .addToItems(
            recipeId: recipeId.value,
            folderId: folders['Cooked on site'],
          );
      expect(added, isA<Ok<String>>());
    });

    await h.pumpApp(tester);
    await h.go(tester, '/items');
    await tester.tap(find.byTooltip('Show ingredients'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to items'));
    await tester.pumpAndSettle();

    // The add flow itself lives on the recipe's own screen.
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets("Delete… in a row's overflow confirms, removes the item from "
      'the list, and the snackbar names it', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    await tester.tap(find.byTooltip('Options for Croissants'));
    await tester.pumpAndSettle();
    // "Delete…" sits below "Move to folder…" in the same overflow.
    expect(find.text('Delete…'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Move to folder…')).dy,
      lessThan(tester.getTopLeft(find.text('Delete…')).dy),
    );
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();

    // The confirmation names the item and promises the history stays.
    expect(find.text('Delete "Croissants"?'), findsOneWidget);
    expect(
      find.text(
        'It comes off your items list. What happened at past events stays '
        'in your history.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(inList('Croissants'), findsNothing);
    expect(find.text('Deleted "Croissants"'), findsOneWidget);
    // No event history → truly removed, not archived out of sight.
    final all = await tester.runAsync(
      () => h
          .read(catalogServiceProvider)
          .watchItems(const ItemFilter(includeArchived: true))
          .first,
    );
    expect(all, isEmpty);
    await h.flushTimers(tester);
  });

  testWidgets('Cancel in the delete confirmation leaves the item in place', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    await tester.tap(find.byTooltip('Options for Croissants'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete "Croissants"?'), findsNothing);
    expect(inList('Croissants'), findsOneWidget);
    final all = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    expect(all, hasLength(1));
    await h.flushTimers(tester);
  });

  testWidgets('Delete all items… clears the whole list after its own '
      'confirmation', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
      await seedItem(h, name: 'Tortillas'); // unfiled
    });

    await h.pumpScreen(tester, const ItemListScreen());

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all items…'));
    await tester.pumpAndSettle();

    // The confirmation carries the live count.
    expect(find.text('Delete all items?'), findsOneWidget);
    expect(
      find.text(
        'Your whole items list is cleared (2 items). What happened at past '
        'events stays in your history.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();

    expect(find.text('All items deleted'), findsOneWidget);
    // Back to the §9 empty catalog — nothing left to section.
    expect(find.text('Nothing in your list yet'), findsOneWidget);
    final all = await tester.runAsync(
      () => h
          .read(catalogServiceProvider)
          .watchItems(const ItemFilter(includeArchived: true))
          .first,
    );
    expect(all, isEmpty);
    await h.flushTimers(tester);
  });

  testWidgets('Delete all items… is disabled while the list is empty', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemListScreen());

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    final entry = tester.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'Delete all items…'),
    );
    expect(entry.enabled, isFalse);

    // Dismiss the menu (a disabled entry ignores taps).
    await tester.tapAt(const Offset(4, 300));
    await tester.pumpAndSettle();
    expect(find.text('Delete all items…'), findsNothing);
  });

  testWidgets('Manage folders in the overflow menu opens the folder '
      'management screen', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemListScreen());
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage folders'));
    await tester.pumpAndSettle();

    expect(find.byType(FolderManagementScreen), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('pinned section headers follow the system brightness — they do '
      'not stay cream on a dark list', (tester) async {
    // Regression (design review): flipping the system to dark left every
    // pinned folder header painted in the LIGHT ramp, cream strips stranded
    // on a near-black list.
    //
    // Why it happened: `SliverPersistentHeader` caches the widget its
    // delegate built and re-runs `SliverPersistentHeaderDelegate.build` only
    // when `shouldRebuild` says so — and `shouldRebuild` compares title,
    // count and folder, because it cannot see a `ColorScheme`. The delegate
    // resolved `Theme.of(context)` itself, so the header froze whichever
    // brightness was live when the section first appeared. (Worse, the
    // header element's own theme dependency is cleared by
    // `RenderObjectElement.update`, so nothing else rescued it.) The colours
    // now live in an ordinary widget below the delegate, which rebuilds with
    // the theme like everything else on the screen.
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
    });
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await h.pumpScreen(tester, const ItemListScreen());

    // The header's own Material — the innermost one wrapping the title.
    Material header() => tester.widget<Material>(
      find
          .ancestor(of: inList('Bakery'), matching: find.byType(Material))
          .first,
    );
    final hue = (await tester.runAsync(() => folderHue(h, 'Bakery')))!;

    // A folder section's band is the folder's own tint, per brightness —
    // never a grey strip, and never the OTHER brightness's tint.
    expect(
      header().color,
      FolderPalette.derive(Brightness.light).pair(hue).tint,
    );

    // The flip the design review captured.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    final dark = header().color!;
    expect(
      dark,
      FolderPalette.derive(Brightness.dark).pair(hue).tint,
      reason: 'the header must resolve the DARK folder tint',
    );
    expect(
      dark.computeLuminance(),
      lessThan(0.1),
      reason:
          'a light strip on a dark list reads as a rendering bug, whatever '
          'token it came from',
    );
    // And back: the staleness cut both ways.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      header().color,
      FolderPalette.derive(Brightness.light).pair(hue).tint,
    );
  });

  testWidgets('the Add item button is a flat pill — no elevation shadow', (
    tester,
  ) async {
    // Regression (design review): the extended FAB rode Material's default
    // 6 dp elevation over an opaque black `ThemeData.shadowColor`, which
    // rendered as a heavy black ring around the button in both modes.
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemListScreen());

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    final theme = loadoutTheme(Brightness.light).floatingActionButtonTheme;
    expect(fab.elevation ?? theme.elevation, 0);
    expect(fab.highlightElevation ?? theme.highlightElevation, 0);
    expect(
      tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.text('Add item'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .elevation,
      0,
    );
  });
  testWidgets('jump chips paint the folder colour that is VISIBLE on the '
      'live brightness — the dark-mode dot regression', (tester) async {
    // Regression (design review): the jump chip drew its mark as an 8 dp
    // dot filled straight from `folderHueSeeds`. The seeds are DARK by
    // construction (fern is #356859) because they are seeds for a light
    // page — on the dark ramp's near-black surface every one of them scored
    // under the text floor, so the mark was simply not there. Folder colour
    // is only ever `FolderPalette.pair(hue)`, which is derived per
    // brightness, and the chip that draws it is the one every other folder
    // surface uses.
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
    });
    final hue = (await tester.runAsync(() => folderHue(h, 'Bakery')))!;

    await h.pumpScreen(tester, const ItemListScreen());
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    // The chip row's own chip for Bakery (never the section header's).
    final chips = tester.widgetList<FolderChip>(
      find.descendant(
        of: find.byKey(itemListJumpRowKey),
        matching: find.byType(FolderChip),
      ),
    );
    final chip = chips.firstWhere((candidate) => candidate.hue == hue);
    expect(chip.size, FolderChipSize.small);
    final chipFinder = find.byWidget(chip);
    final mark = tester.widget<Icon>(
      find.descendant(of: chipFinder, matching: find.byType(Icon)),
    );
    final box = tester.widget<Container>(
      find.descendant(of: chipFinder, matching: find.byType(Container)).first,
    );

    final dark = loadoutColorScheme(Brightness.dark);
    final pair = FolderPalette.derive(Brightness.dark).pair(hue);
    expect(mark.color, pair.ink, reason: 'the mark is the DARK ink');
    expect((box.decoration! as BoxDecoration).color, pair.tint);
    // What "visible" means, measured on the colours that painted.
    expect(
      contrastRatio(mark.color!, pair.tint),
      greaterThanOrEqualTo(4.5),
      reason: 'the mark must read on its own chip',
    );
    expect(
      contrastRatio(mark.color!, dark.surface),
      greaterThanOrEqualTo(4.5),
      reason: 'and on the near-black page the chip row sits on',
    );
    // And the colour the chip USED to paint would fail that on every one of
    // the eight hues — which is what made the old dot invisible.
    for (final seedHue in FolderHue.values) {
      expect(
        contrastRatio(folderHueSeeds[seedHue]!, dark.surface),
        lessThan(4.5),
        reason: '$seedHue: a raw seed is not a dark-mode mark colour',
      );
    }
    // The name is folder-coloured too, so identity never rides the mark
    // alone at either brightness.
    final label = tester.widget<Text>(
      find.descendant(
        of: find.byKey(itemListJumpRowKey),
        matching: find.text('Bakery'),
      ),
    );
    expect(label.style?.color, pair.ink);
  });

  testWidgets('a row shows its price as a caption figure, and shows nothing '
      'when the item was never priced', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(
        h,
        name: 'Croissants',
        folderId: folders['Bakery'],
        unitPrice: Money.fromCents(350),
      );
      await seedItem(h, name: 'Rolls', folderId: folders['Bakery']);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    // The list now opens with the "Stock value" summary, so a mid-list
    // folder starts below the fold.
    await tester.dragUntilVisible(
      inList('Croissants'),
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    expect(inList(r'$3.50'), findsOneWidget);
    // On the priced row itself, beside the amount and the name.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Croissants'),
        matching: find.text(r'$3.50'),
      ),
      findsOneWidget,
    );
    // Caption tier, not a second row quantity: the price never competes
    // with the count the row exists to show.
    final subtitle =
        tester.widget<Text>(inList(r'$3.50')).textSpan! as TextSpan;
    final priceStyle = (subtitle.children!.first as TextSpan).style!;
    final text = loadoutTheme(Brightness.light).textTheme;
    expect(priceStyle.fontSize, Numerals.caption(text)!.fontSize);
    expect(priceStyle.fontWeight, Numerals.caption(text)!.fontWeight);
    expect(priceStyle.fontFeatures, Numerals.tabular);

    // The unpriced item says nothing at all — never "$0".
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Rolls'),
        matching: find.textContaining(r'$'),
      ),
      findsNothing,
    );
  });

  testWidgets('the Add item button never sits on top of a row — mid-scroll '
      'or at the end of the list', (tester) async {
    // Regression (design review): the FAB floats over the body, and the
    // list only ended with an 88 dp spacer — so the spacer cleared the
    // button at FULL scroll and nowhere else. Mid-scroll the pill sat on
    // the last visible row's trailing area, over its overflow menu.
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      for (var i = 0; i < 30; i++) {
        await seedItem(
          h,
          name: 'Item ${'${i + 1}'.padLeft(2, '0')}',
          folderId: folders['Bakery'],
        );
      }
    });

    await h.pumpScreen(tester, const ItemListScreen());

    final fab = tester.getRect(find.byType(FloatingActionButton));
    void expectNothingUnderTheButton(String when) {
      for (final element in find.byType(ListTile).evaluate()) {
        final row = tester.getRect(
          find.byElementPredicate((e) => e == element),
        );
        expect(
          row.overlaps(fab),
          isFalse,
          reason: 'a row is under the Add item button $when',
        );
      }
    }

    expectNothingUnderTheButton('before scrolling');
    for (final offset in [-160.0, -240.0, -300.0]) {
      await tester.drag(find.byType(CustomScrollView), Offset(0, offset));
      await tester.pumpAndSettle();
      expectNothingUnderTheButton('after scrolling $offset');
    }
    await tester.dragUntilVisible(
      inList('Item 30'),
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expectNothingUnderTheButton('at the end of the list');
    expect(inList('Item 30'), findsOneWidget);
  });

  testWidgets('the sectioned list renders at 200% text scale on a 320 dp '
      'viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      await seedItem(
        h,
        name: 'Croissants',
        folderId: folders['Bakery'],
        unitLabel: 'packages',
        unitPrice: Money.fromCents(350),
      );
      await seedItem(h, name: 'Tortillas');
    });

    // An overflow at 200 % scale would throw and fail the test here.
    await h.pumpScreen(tester, const ItemListScreen());
    expect(find.byType(ItemListScreen), findsOneWidget);
    // The "Stock value" summary opens the list, so at this scale the first
    // folder sections start below the fold.
    await tester.dragUntilVisible(
      inList('Croissants'),
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(inList('Croissants'), findsOneWidget);

    // Dark too: the jump row and the headers are rebuilt per brightness.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(inList('Croissants'), findsOneWidget);
  });
}
