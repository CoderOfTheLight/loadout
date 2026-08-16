/// One name (owner request): the recipe and its output item share a single
/// name, kept in sync in BOTH directions through the real write path — an
/// AddRecipeRevision rename updates `recipes.name` and the output item's
/// row together, and an item-side UpdateItem rename pulls the recipe along.
/// A recipe outside the items list answers to no uniqueness constraint.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;

  setUp(() => h = WritePathHarness());

  tearDown(() => h.close());

  RecipeRevisionDraft revision({int whole = 1}) => RecipeRevisionDraft(
    yieldQuantity: Quantity.whole(10),
    lines: [
      RecipeLineDraft(name: 'Cumin', quantityPerBatch: Quantity.whole(whole)),
    ],
  );

  Future<String> createRecipe(String name) async {
    final receipt = await h.ok(
      CreateRecipe(name: name, firstRevision: revision()),
    );
    return receipt.createdRecordIds.first;
  }

  Future<String> recipeName(String recipeId) async => (await (h.db.select(
    h.db.recipes,
  )..where((r) => r.id.equals(recipeId))).getSingle()).name;

  group('rename riding AddRecipeRevision', () {
    test('a new name updates recipes.name AND the output item, in one '
        'transaction with the appended revision', () async {
      final recipeId = await createRecipe('Chilli batch');
      final added = await h.ok(AddRecipeToItems(recipeId: RecipeId(recipeId)));
      final outputId = added.createdRecordIds.first;
      final before = await h.itemRow(outputId);
      h.clock.advanceMicros(1000);

      await h.ok(
        AddRecipeRevision(
          recipeId: RecipeId(recipeId),
          revision: revision(whole: 2),
          name: '  Chilli supreme  ',
        ),
      );
      expect(await recipeName(recipeId), 'Chilli supreme', reason: 'trimmed');
      final output = await h.itemRow(outputId);
      expect(output.name, 'Chilli supreme');
      expect(output.updatedAtMicros, greaterThan(before.updatedAtMicros));
      expect(await h.count('recipe_revisions'), 2);
    });

    test('without an output item only recipes.name changes', () async {
      final recipeId = await createRecipe('Soup');
      await h.ok(
        AddRecipeRevision(
          recipeId: RecipeId(recipeId),
          revision: revision(),
          name: 'Broth',
        ),
      );
      expect(await recipeName(recipeId), 'Broth');
      expect(await h.count('items'), 0, reason: 'no item was ever created');
    });

    test('a name colliding with another live item is rejected; the recipe '
        'and its revisions are untouched', () async {
      await h.createItem(name: 'Napkins');
      final recipeId = await createRecipe('Chilli batch');
      await h.ok(AddRecipeToItems(recipeId: RecipeId(recipeId)));
      final before = await h.effectCounts();

      final error = await h.err(
        AddRecipeRevision(
          recipeId: RecipeId(recipeId),
          revision: revision(whole: 2),
          name: 'napkins', // the live-name index is case-insensitive
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, 'a live item with this name already exists');
      expect(await recipeName(recipeId), 'Chilli batch');
      expect(await h.effectCounts(), before, reason: 'nothing written');
    });

    test('bounds: a blank or over-long name is rejected', () async {
      final recipeId = await createRecipe('Soup');
      for (final bad in ['   ', 'x' * 121]) {
        final error = await h.err(
          AddRecipeRevision(
            recipeId: RecipeId(recipeId),
            revision: revision(),
            name: bad,
          ),
        );
        expect(error, isA<ValidationError>());
        expect(error.message, 'recipe name must be 1-120 characters');
      }
      expect(await recipeName(recipeId), 'Soup');
    });

    test('a recipe outside the items list may share a live item\'s name — '
        'recipes have no uniqueness constraint', () async {
      await h.createItem(name: 'Napkins');
      final recipeId = await createRecipe('Soup');
      await h.ok(
        AddRecipeRevision(
          recipeId: RecipeId(recipeId),
          revision: revision(),
          name: 'Napkins',
        ),
      );
      expect(await recipeName(recipeId), 'Napkins');
    });

    test('name equal to the current one, or null, is a no-op on names: the '
        'output item\'s updated_at does not move', () async {
      final recipeId = await createRecipe('Chilli batch');
      final added = await h.ok(AddRecipeToItems(recipeId: RecipeId(recipeId)));
      final outputId = added.createdRecordIds.first;
      final before = await h.itemRow(outputId);
      h.clock.advanceMicros(1000);

      await h.ok(
        AddRecipeRevision(
          recipeId: RecipeId(recipeId),
          revision: revision(whole: 2),
          name: 'Chilli batch',
        ),
      );
      h.clock.advanceMicros(1000);
      await h.ok(
        AddRecipeRevision(
          recipeId: RecipeId(recipeId),
          revision: revision(whole: 3),
        ),
      );
      expect(await recipeName(recipeId), 'Chilli batch');
      final output = await h.itemRow(outputId);
      expect(output.name, 'Chilli batch');
      expect(
        output.updatedAtMicros,
        before.updatedAtMicros,
        reason: 'neither revise touched the item row',
      );
      expect(await h.count('recipe_revisions'), 3);
    });
  });

  group('rename from the item side (UpdateItem)', () {
    test('renaming a recipe-output item pulls recipes.name along', () async {
      final recipeId = await createRecipe('Chilli batch');
      final added = await h.ok(AddRecipeToItems(recipeId: RecipeId(recipeId)));
      final outputId = added.createdRecordIds.first;

      await h.ok(
        UpdateItem(itemId: ItemId(outputId), name: '  Chilli supreme  '),
      );
      expect((await h.itemRow(outputId)).name, 'Chilli supreme');
      expect(await recipeName(recipeId), 'Chilli supreme', reason: 'trimmed');
    });

    test('renaming a plain item leaves every recipe alone', () async {
      final recipeId = await createRecipe('Chilli batch');
      final napkins = await h.createItem(name: 'Napkins');
      await h.ok(UpdateItem(itemId: ItemId(napkins), name: 'Serviettes'));
      expect(await recipeName(recipeId), 'Chilli batch');
    });
  });
}
