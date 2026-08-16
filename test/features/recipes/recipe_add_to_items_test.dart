/// "Add to my items" end-to-end (v5 recipe decoupling): the labeled action
/// on the recipe detail opens a sheet that picks the recipe's folder and an
/// opt-in checklist of unlinked ingredient lines; confirm submits ONE
/// AddRecipeToItems command — output item + chosen ingredient items (created
/// AND linked) + recipe binding in one transaction. Skipped lines stay
/// recipe text. Afterwards the detail shows WHERE the recipe lives instead
/// of the action, and "Scale to event" appears. Validator refusals surface
/// as plain text inside the sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  testWidgets(
    'end-to-end: folder chosen, two ingredients added (one into its own '
    'folder), one skipped — one command, links written, detail flips',
    (tester) async {
      final h = (await tester.runAsync(
        () => AppHarness.start(state: AppHarnessState.workspace),
      ))!;
      addTearDown(h.dispose);
      late String onions, recipeId;
      await tester.runAsync(() async {
        unwrap(
          await h
              .read(catalogServiceProvider)
              .createFolder(name: 'Prep', demandBasis: DemandBasis.perPerson),
        );
        onions = await seedItem(h, 'Onions');
        recipeId = await seedStandaloneRecipe(
          h,
          name: 'Chilli batch',
          lines: [
            RecipeFormLine(itemId: onions, quantityPerBatch: Quantity.whole(2)),
            RecipeFormLine(
              name: 'Flour',
              unitLabel: 'cup',
              quantityPerBatch: Quantity.fromMicros(1500000), // 1.5
            ),
            RecipeFormLine(name: 'Beans', quantityPerBatch: Quantity.whole(3)),
            RecipeFormLine(
              name: 'Salt',
              unitLabel: 'tsp',
              quantityPerBatch: Quantity.fromMicros(500000), // 0.5
            ),
          ],
        );
      });

      await h.pumpApp(tester);
      await h.go(tester, '/recipes/$recipeId');

      await tapVisible(tester, find.byKey(const Key('add-to-items')));
      // Drift delivers the folder stream on a zero-duration timer.
      await h.flushTimers(tester);
      await tester.pumpAndSettle();

      // The sheet: recipe folder defaults to Unfiled; only the UNLINKED
      // lines are offered (Onions is already an item — nothing to create).
      expect(find.text('Add to my items'), findsWidgets);
      expect(find.byKey(const ValueKey('add-line-0')), findsNothing);
      expect(find.byKey(const ValueKey('add-line-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-line-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-line-3')), findsOneWidget);
      expect(find.text('1.5 cup per batch'), findsOneWidget);

      // Pick the recipe's folder: Unfiled → Prep.
      await tapVisible(tester, find.byKey(const Key('add-folder-picker')));
      await h.flushTimers(tester);
      await tester.pumpAndSettle();
      expect(find.text('Choose a folder'), findsOneWidget);
      await tapFolderPickerEntry(tester, 'Prep');

      // Tick Flour — its folder follows the recipe's (Prep) by default.
      await tapVisible(tester, find.byKey(const ValueKey('add-line-1')));
      expect(find.text('Into Prep'), findsOneWidget);

      // Tick Beans and send it somewhere of its own: Unfiled.
      await tapVisible(tester, find.byKey(const ValueKey('add-line-2')));
      await tapVisible(tester, find.byKey(const ValueKey('line-folder-2')));
      await h.flushTimers(tester);
      await tester.pumpAndSettle();
      await tapFolderPickerEntry(tester, 'Unfiled');
      expect(find.text('Into Unfiled'), findsOneWidget);

      // Salt stays unticked — skipped on purpose.
      expect(find.text('Add to items (+2 ingredients)'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('confirm-add-to-items')));
      await h.flushTimers(tester);
      await tester.pumpAndSettle();

      // The sheet closed and said so.
      expect(find.byKey(const Key('confirm-add-to-items')), findsNothing);
      expect(find.text('Added to your items'), findsOneWidget);

      // ONE transaction's worth of items: the recipe in Prep, Flour in
      // Prep (followed the recipe), Beans in Unfiled (its own pick), the
      // unit labels carried — and NO Salt.
      final items = (await tester.runAsync(
        () =>
            h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
      ))!;
      final byName = {
        for (final summary in items) summary.item.name: summary.item,
      };
      expect(
        byName.keys,
        unorderedEquals(['Onions', 'Chilli batch', 'Flour', 'Beans']),
      );
      final folders = (await tester.runAsync(
        () => h.read(catalogServiceProvider).watchFolders().first,
      ))!;
      final prepId = folders.firstWhere((f) => f.name == 'Prep').id.value;
      expect(byName['Chilli batch']!.folderId?.value, prepId);
      expect(byName['Flour']!.folderId?.value, prepId);
      expect(byName['Flour']!.unitLabel, 'cup');
      expect(byName['Beans']!.folderId, isNull);

      // The recipe is bound to its output item, and the chosen lines are
      // now LINKED to the created items; Salt stays a free line.
      final detail = (await tester.runAsync(
        () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
      ))!;
      expect(detail.recipe.isInItems, isTrue);
      expect(
        detail.recipe.outputItemId?.value,
        byName['Chilli batch']!.id.value,
      );
      final lines = detail.revisions.first.lines;
      expect(lines[0].ingredientItemId?.value, onions);
      expect(lines[1].ingredientItemId?.value, byName['Flour']!.id.value);
      expect(lines[2].ingredientItemId?.value, byName['Beans']!.id.value);
      expect(lines[3].ingredientItemId, isNull); // skipped, still free

      // The detail now says where the recipe lives instead of the action,
      // and scaling is available.
      expect(find.byKey(const Key('add-to-items')), findsNothing);
      expect(find.byKey(const Key('in-items-location')), findsOneWidget);
      expect(find.text('In your items · Prep'), findsOneWidget);
      expect(find.byKey(const Key('scale-to-event')), findsOneWidget);
    },
  );

  testWidgets('a refused add stays in the sheet with the plain error said', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      await seedItem(h, 'Flour'); // the name the chosen line collides with
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Bread',
        lines: [
          RecipeFormLine(name: 'Flour', quantityPerBatch: Quantity.whole(1)),
        ],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');
    await tapVisible(tester, find.byKey(const Key('add-to-items')));
    await tapVisible(tester, find.byKey(const ValueKey('add-line-0')));
    await tapVisible(tester, find.byKey(const Key('confirm-add-to-items')));
    await h.flushTimers(tester);
    await tester.pumpAndSettle();

    // Refused in plain words, inside the sheet; nothing was added.
    expect(find.byKey(const Key('add-to-items-error')), findsOneWidget);
    expect(
      find.textContaining("a live item already has an ingredient line's"),
      findsOneWidget,
    );
    expect(find.byKey(const Key('confirm-add-to-items')), findsOneWidget);
    final detail = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(detail.recipe.isInItems, isFalse);
    final items = (await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    ))!;
    expect(items, hasLength(1)); // just the seeded Flour

    // Untick the colliding line and the add goes through.
    await tapVisible(tester, find.byKey(const ValueKey('add-line-0')));
    await tapVisible(tester, find.byKey(const Key('confirm-add-to-items')));
    await h.flushTimers(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-add-to-items')), findsNothing);
    final after = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(after.recipe.isInItems, isTrue);
  });
}
