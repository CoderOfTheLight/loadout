import '../../../core/errors.dart';
import '../../../core/result.dart';

/// One live recipe reduced to its graph shape.
final class RecipeNode {
  const RecipeNode({
    required this.recipeId,
    required this.outputItemId,
    required this.ingredientItemIds,
  });

  final String recipeId;
  final String outputItemId;
  final List<String> ingredientItemIds;
}

/// Recipe guards (design §11.1 D). v1 recipes are strictly flat: no
/// ingredient may itself be the output of a live recipe, and the graph over
/// live recipes must be acyclic. Archived recipes never participate.
final class RecipeGraph {
  /// [liveRecipes]: every live (non-archived) recipe's latest revision.
  RecipeGraph(List<RecipeNode> liveRecipes)
    : _byOutput = {for (final node in liveRecipes) node.outputItemId: node};

  final Map<String, RecipeNode> _byOutput;

  /// Flatness guard for a new or revised recipe. Rejects when the output
  /// item appears among its own ingredients, or when any ingredient is the
  /// output of a live recipe other than [candidate] itself. The candidate's
  /// stored predecessor (same `recipeId`) is ignored so revising in place
  /// stays legal.
  Result<void> assertFlat(RecipeNode candidate) {
    for (final ingredient in candidate.ingredientItemIds) {
      if (ingredient == candidate.outputItemId) {
        return Err(
          RecipeNestingError(
            'recipe output item cannot be one of its own ingredients',
            path: [candidate.outputItemId],
          ),
        );
      }
      final producer = _byOutput[ingredient];
      if (producer != null && producer.recipeId != candidate.recipeId) {
        return Err(
          RecipeNestingError(
            'ingredient is the output of a live recipe',
            path: [candidate.outputItemId, ingredient, producer.recipeId],
          ),
        );
      }
    }
    return const Ok(null);
  }

  /// Cycle guard over the whole live graph (also run on restore validation,
  /// design §8.2). Edges go from a recipe's output item to each ingredient
  /// that is itself the output of a live recipe. Nodes and neighbors are
  /// visited in sorted order so a detected cycle path is deterministic; the
  /// reported path starts at its smallest item id and ends where it started.
  Result<void> detectCycles() {
    final outputs = _byOutput.keys.toList()..sort();
    const white = 0, grey = 1, black = 2;
    final color = <String, int>{for (final o in outputs) o: white};
    final stack = <String>[];

    List<String>? visit(String node) {
      color[node] = grey;
      stack.add(node);
      final neighbors =
          _byOutput[node]!.ingredientItemIds
              .where(_byOutput.containsKey)
              .toList()
            ..sort();
      for (final next in neighbors) {
        if (color[next] == grey) {
          final start = stack.indexOf(next);
          return [...stack.sublist(start), next];
        }
        if (color[next] == white) {
          final cycle = visit(next);
          if (cycle != null) return cycle;
        }
      }
      stack.removeLast();
      color[node] = black;
      return null;
    }

    for (final output in outputs) {
      if (color[output] != white) continue;
      final cycle = visit(output);
      if (cycle != null) {
        return Err(
          RecipeCycleError(
            'live recipes form a cycle',
            path: _canonicalCycle(cycle),
          ),
        );
      }
    }
    return const Ok(null);
  }

  /// Rotates a closed cycle path (`[a, b, c, a]`) so it starts at its
  /// smallest member — the same cycle always reports the same path.
  static List<String> _canonicalCycle(List<String> closed) {
    final cycle = closed.sublist(0, closed.length - 1);
    var smallest = 0;
    for (var i = 1; i < cycle.length; i++) {
      if (cycle[i].compareTo(cycle[smallest]) < 0) smallest = i;
    }
    final rotated = [...cycle.sublist(smallest), ...cycle.sublist(0, smallest)];
    return [...rotated, rotated.first];
  }
}
