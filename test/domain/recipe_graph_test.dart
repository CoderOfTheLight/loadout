/// §11.1 family D: recipe guards. `assertFlat` rejects live-recipe-output
/// ingredients and self-output ingredients with a narrated path; archived
/// recipes never participate. `detectCycles` finds self/2/3-cycles with a
/// deterministic path; flat graphs pass.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/recipes/domain/recipe_graph.dart';

RecipeNode node(String recipeId, String output, List<String> ingredients) =>
    RecipeNode(
      recipeId: recipeId,
      outputItemId: output,
      ingredientItemIds: ingredients,
    );

DomainError errOf(Result<void> result) => switch (result) {
  Err<void>(:final error) => error,
  Ok<void>() => fail('expected Err, got Ok'),
};

void main() {
  group('RecipeGraph.assertFlat', () {
    test('ingredient that is a live recipe output is rejected with path', () {
      final graph = RecipeGraph([
        node('R-SALSA', 'ITEM-SALSA', ['ITEM-TOMATO']),
      ]);
      final result = graph.assertFlat(
        node('R-TACO', 'ITEM-TACO', ['ITEM-TORTILLA', 'ITEM-SALSA']),
      );
      final error = errOf(result);
      expect(error, isA<RecipeNestingError>());
      expect(error.code, 'RECIPE_NESTING');
      expect((error as RecipeNestingError).path, [
        'ITEM-TACO',
        'ITEM-SALSA',
        'R-SALSA',
      ]);
    });

    test('archived recipe output is allowed (not in the live graph)', () {
      // The salsa recipe is archived, so the caller builds the graph
      // without it — its output is a plain item again.
      final graph = RecipeGraph([
        node('R-BEANS', 'ITEM-BEANS', ['ITEM-PINTO']),
      ]);
      final result = graph.assertFlat(
        node('R-TACO', 'ITEM-TACO', ['ITEM-SALSA']),
      );
      expect(result, isA<Ok<void>>());
    });

    test('output item among its own ingredients is rejected', () {
      final graph = RecipeGraph(const []);
      final error = errOf(
        graph.assertFlat(node('R-TACO', 'ITEM-TACO', ['ITEM-TACO'])),
      );
      expect(error, isA<RecipeNestingError>());
      expect((error as RecipeNestingError).path, ['ITEM-TACO']);
    });

    test('revising a recipe does not collide with its own stored node', () {
      final graph = RecipeGraph([
        node('R-TACO', 'ITEM-TACO', ['ITEM-TORTILLA']),
      ]);
      final result = graph.assertFlat(
        node('R-TACO', 'ITEM-TACO', ['ITEM-CHEESE']),
      );
      expect(result, isA<Ok<void>>());
    });
  });

  group('RecipeGraph.detectCycles', () {
    test('flat graph passes', () {
      final graph = RecipeGraph([
        node('R1', 'A', ['X', 'Y']),
        node('R2', 'B', ['X', 'Z']),
      ]);
      expect(graph.detectCycles(), isA<Ok<void>>());
    });

    test('self-cycle detected with deterministic path', () {
      final graph = RecipeGraph([
        node('R1', 'A', ['A']),
      ]);
      final error = errOf(graph.detectCycles());
      expect(error, isA<RecipeCycleError>());
      expect((error as RecipeCycleError).path, ['A', 'A']);
    });

    test('2-cycle detected with deterministic path', () {
      final error = errOf(
        RecipeGraph([
          node('R1', 'B', ['A']),
          node('R2', 'A', ['B']),
        ]).detectCycles(),
      );
      expect((error as RecipeCycleError).path, ['A', 'B', 'A']);
    });

    test('3-cycle detected; path starts at smallest node regardless of '
        'construction order', () {
      final orderings = [
        [
          node('R1', 'A', ['B']),
          node('R2', 'B', ['C']),
          node('R3', 'C', ['A']),
        ],
        [
          node('R3', 'C', ['A']),
          node('R1', 'A', ['B']),
          node('R2', 'B', ['C']),
        ],
        [
          node('R2', 'B', ['C']),
          node('R3', 'C', ['A']),
          node('R1', 'A', ['B']),
        ],
      ];
      for (final nodes in orderings) {
        final error = errOf(RecipeGraph(nodes).detectCycles());
        expect((error as RecipeCycleError).path, ['A', 'B', 'C', 'A']);
      }
    });
  });
}
