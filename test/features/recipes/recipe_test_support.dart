/// Shared seeding + interaction helpers for the recipe screen widget tests.
///
/// Seeding goes through the REAL services (design §11.3) and must run
/// inside `tester.runAsync` — see `test/support/app_harness.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../../support/app_harness.dart';

/// Unwraps an [Ok] or fails the test with the error's code + message.
T unwrap<T>(Result<T> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => fail('expected Ok, got ${error.code}: ${error.message}'),
};

/// Creates a catalog item through the real [CatalogService]; returns its id.
/// Call inside `tester.runAsync`.
Future<String> seedItem(
  AppHarness h,
  String name, {
  ItemUnit unit = ItemUnit.each,
}) async => unwrap(
  await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(name: name, unit: unit, packSize: Quantity.whole(1)),
      ),
);

/// Creates a recipe (revision 1) through the real [RecipeService]; returns
/// its id. Call inside `tester.runAsync`. [lines] maps ingredient item id →
/// whole per-batch quantity.
Future<String> seedRecipe(
  AppHarness h, {
  required String name,
  required String outputItemId,
  required Map<String, int> lines,
  int yieldWhole = 10,
  String? yieldLabel,
  String note = '',
}) async => unwrap(
  await h
      .read(recipeServiceProvider)
      .createRecipe(
        RecipeFormDraft(
          name: name,
          outputItemId: outputItemId,
          yieldQuantity: Quantity.whole(yieldWhole),
          yieldLabel: yieldLabel,
          note: note,
          lines: [
            for (final entry in lines.entries)
              RecipeFormLine(
                itemId: entry.key,
                quantityPerBatch: Quantity.whole(entry.value),
              ),
          ],
        ),
      ),
);

/// Creates a v5 decoupled recipe (no output item; [lines] given verbatim,
/// so free and linked lines mix freely) through the real [RecipeService];
/// returns its id. Call inside `tester.runAsync`.
Future<String> seedStandaloneRecipe(
  AppHarness h, {
  required String name,
  required List<RecipeFormLine> lines,
  int yieldWhole = 10,
  String? yieldLabel,
  String note = '',
}) async => unwrap(
  await h
      .read(recipeServiceProvider)
      .createRecipe(
        RecipeFormDraft(
          name: name,
          yieldQuantity: Quantity.whole(yieldWhole),
          yieldLabel: yieldLabel,
          note: note,
          lines: lines,
        ),
      ),
);

/// Opens the dropdown found by [dropdown] and taps the option showing
/// [optionText] in the opened menu.
Future<void> pickFromDropdown(
  WidgetTester tester,
  Finder dropdown,
  String optionText,
) async {
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  // `.last` targets the open menu overlay (closed dropdowns keep their
  // option widgets in the tree for sizing).
  await tester.tap(find.text(optionText).last);
  await tester.pumpAndSettle();
}

/// Scrolls to and taps the widget found by [finder], then settles.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Opens RecipeDetailScreen's app-bar "More" menu and taps the entry keyed
/// [itemKey] ('archive-action', 'earlier-versions', 'revise-action').
Future<void> tapRecipeMenuItem(WidgetTester tester, String itemKey) async {
  await tapVisible(tester, find.byKey(const Key('recipe-menu')));
  await tester.tap(find.byKey(Key(itemKey)));
  await tester.pumpAndSettle();
}

/// Opens ingredient row [uid]'s overflow on RecipeEditScreen.
Future<void> openIngredientMenu(WidgetTester tester, int uid) =>
    tapVisible(tester, find.byKey(ValueKey('ingredient-menu-$uid')));

/// Opens ingredient row [uid]'s overflow and taps the entry keyed [itemKey]
/// ('link-line-N', 'unlink-line-N', 'remove-ingredient-N').
Future<void> tapIngredientMenuItem(
  WidgetTester tester,
  int uid,
  String itemKey,
) async {
  await openIngredientMenu(tester, uid);
  await tester.tap(find.byKey(ValueKey(itemKey)));
  await tester.pumpAndSettle();
}

/// Whether ingredient row [uid]'s overflow offers the entry keyed
/// [itemKey]. Leaves the menu closed again.
Future<bool> ingredientMenuOffers(
  WidgetTester tester,
  int uid,
  String itemKey,
) async {
  await openIngredientMenu(tester, uid);
  final offered = find.byKey(ValueKey(itemKey)).evaluate().isNotEmpty;
  await tester.tapAt(const Offset(2, 2)); // the menu's barrier
  await tester.pumpAndSettle();
  return offered;
}

/// Scrolls the OPEN folder-picker sheet until [label] is visible and taps
/// it. The picker's list is lazy and the eight starter folders push later
/// entries (a created folder, "Unfiled") below the sheet's fold, where a
/// plain finder sees nothing.
Future<void> tapFolderPickerEntry(WidgetTester tester, String label) async {
  // A plain finder: `.last` throws (instead of reporting empty) while the
  // lazy list has not built the entry yet, which breaks dragUntilVisible's
  // is-it-there-yet polling.
  final target = find.text(label);
  await tester.dragUntilVisible(
    target,
    // The picker's own list is the topmost ListView (screens behind the
    // modal may have their own).
    find.byType(ListView).last,
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}
