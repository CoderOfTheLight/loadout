/// §9 + §11.3 RecipeEditScreen (create mode) widget tests: create with
/// lines; duplicate ingredient rejected inline; one live recipe per output
/// item surfaced; nesting rejected with the RecipeNestingError path shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/recipes/domain/recipe.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  testWidgets('create writes recipe + revision 1 with its lines', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, 'Taco kit');
      await seedItem(h, 'Tortillas');
      await seedItem(h, 'Cheese', unit: ItemUnit.kg);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    await pickFromDropdown(
      tester,
      find.byKey(const Key('output-item-picker')),
      'Taco kit · each',
    );
    await tester.enterText(
      find.byKey(const Key('recipe-name')),
      'Taco kit build',
    );
    await tester.enterText(find.byKey(const Key('recipe-yield')), '10');
    await tester.enterText(
      find.byKey(const Key('recipe-yield-label')),
      '10 kits',
    );
    // First (pre-added) ingredient row.
    await pickFromDropdown(
      tester,
      find.byKey(const ValueKey('ingredient-item-0')),
      'Tortillas',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-qty-0')),
      '20',
    );
    // Second row.
    await tapVisible(tester, find.byKey(const Key('add-ingredient')));
    await pickFromDropdown(
      tester,
      find.byKey(const ValueKey('ingredient-item-1')),
      'Cheese',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-qty-1')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const Key('recipe-note')),
      'Fold, do not stir',
    );
    await tapVisible(tester, find.byKey(const Key('save-recipe')));

    // Popped back to the list showing the new live recipe.
    expect(find.text('Taco kit build'), findsOneWidget);
    expect(find.text('rev 1'), findsOneWidget);

    final detail = (await tester.runAsync(() async {
      final summaries = await h
          .read(recipeServiceProvider)
          .watchRecipes()
          .first;
      expect(summaries, hasLength(1));
      return h
          .read(recipeServiceProvider)
          .watchRecipe(summaries.first.id)
          .first;
    }))!;
    expect(detail.recipe.name, 'Taco kit build');
    expect(detail.revisions, hasLength(1));
    final revision = detail.revisions.first;
    expect(revision.revision, 1);
    expect(revision.yieldQuantity, Quantity.whole(10));
    expect(revision.yieldLabel, '10 kits');
    expect(revision.note, 'Fold, do not stir');
    expect(revision.sourceKind, RecipeSourceKind.form);
    expect(revision.lines, hasLength(2));
    expect(revision.lines[0].quantityPerBatch, Quantity.whole(20));
    expect(revision.lines[1].quantityPerBatch.micros, 1500000);
  });

  testWidgets('duplicate ingredient is rejected inline', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, 'Taco kit');
      await seedItem(h, 'Tortillas');
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    await pickFromDropdown(
      tester,
      find.byKey(const Key('output-item-picker')),
      'Taco kit · each',
    );
    await tester.enterText(find.byKey(const Key('recipe-name')), 'Build');
    await tester.enterText(find.byKey(const Key('recipe-yield')), '10');
    await pickFromDropdown(
      tester,
      find.byKey(const ValueKey('ingredient-item-0')),
      'Tortillas',
    );
    await tester.enterText(find.byKey(const ValueKey('ingredient-qty-0')), '1');
    await tapVisible(tester, find.byKey(const Key('add-ingredient')));
    await pickFromDropdown(
      tester,
      find.byKey(const ValueKey('ingredient-item-1')),
      'Tortillas',
    );
    await tester.enterText(find.byKey(const ValueKey('ingredient-qty-1')), '2');
    await tapVisible(tester, find.byKey(const Key('save-recipe')));

    expect(find.text('Already in this recipe'), findsOneWidget);
    // Nothing was written.
    final summaries = await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipes().first,
    );
    expect(summaries, isEmpty);
  });

  testWidgets('second live recipe for the same output item is rejected', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final salsa = await seedItem(h, 'Salsa');
      final tomato = await seedItem(h, 'Tomato');
      await seedRecipe(
        h,
        name: 'Salsa base',
        outputItemId: salsa,
        lines: {tomato: 3},
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    await pickFromDropdown(
      tester,
      find.byKey(const Key('output-item-picker')),
      'Salsa · each',
    );
    await tester.enterText(
      find.byKey(const Key('recipe-name')),
      'Second salsa',
    );
    await tester.enterText(find.byKey(const Key('recipe-yield')), '5');
    await pickFromDropdown(
      tester,
      find.byKey(const ValueKey('ingredient-item-0')),
      'Tomato',
    );
    await tester.enterText(find.byKey(const ValueKey('ingredient-qty-0')), '4');
    await tapVisible(tester, find.byKey(const Key('save-recipe')));

    // Validator error surfaced; still on the form; nothing extra written.
    expect(
      find.textContaining('a live recipe for this output item already exists'),
      findsOneWidget,
    );
    final summaries = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipes().first,
    ))!;
    expect(summaries, hasLength(1));
    expect(summaries.first.name, 'Salsa base');
  });

  testWidgets('nesting is rejected with the RecipeNestingError path shown', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final salsa = await seedItem(h, 'Salsa');
      final tomato = await seedItem(h, 'Tomato');
      await seedItem(h, 'Taco kit');
      await seedRecipe(
        h,
        name: 'Salsa base',
        outputItemId: salsa,
        lines: {tomato: 3},
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    await pickFromDropdown(
      tester,
      find.byKey(const Key('output-item-picker')),
      'Taco kit · each',
    );
    await tester.enterText(find.byKey(const Key('recipe-name')), 'Kit build');
    await tester.enterText(find.byKey(const Key('recipe-yield')), '1');
    await pickFromDropdown(
      tester,
      find.byKey(const ValueKey('ingredient-item-0')),
      'Salsa',
    );
    await tester.enterText(find.byKey(const ValueKey('ingredient-qty-0')), '2');
    await tapVisible(tester, find.byKey(const Key('save-recipe')));

    // The RecipeNestingError message and its resolved path are both shown.
    expect(
      find.textContaining('ingredient is the output of a live recipe'),
      findsOneWidget,
    );
    expect(
      find.textContaining("Taco kit → Salsa → recipe 'Salsa base'"),
      findsOneWidget,
    );
    final summaries = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipes().first,
    ))!;
    expect(summaries, hasLength(1)); // only the seeded recipe
  });
}
