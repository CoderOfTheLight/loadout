import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'recipe_dao.g.dart';

/// Recipe reads. Mutation stays with the CommandApplier (design §6.4);
/// this DAO exposes none.
@DriftAccessor(tables: [Recipes, RecipeRevisions, RecipeLines])
class RecipeDao extends DatabaseAccessor<AppDatabase> with _$RecipeDaoMixin {
  RecipeDao(super.db);

  Future<Recipe?> byId(String id) =>
      (select(recipes)..where((r) => r.id.equals(id))).getSingleOrNull();

  Stream<Recipe?> watchById(String id) =>
      (select(recipes)..where((r) => r.id.equals(id))).watchSingleOrNull();

  /// Every recipe, live first, then case-insensitively by name.
  Stream<List<Recipe>> watchAll() =>
      (select(recipes)..orderBy([
            (r) => OrderingTerm.asc(r.archivedAtMicros.isNotNull()),
            (r) => OrderingTerm.asc(r.name.lower()),
          ]))
          .watch();

  /// All revisions of one recipe, newest first (current = first row).
  Future<List<RecipeRevision>> revisionsFor(String recipeId) =>
      (select(recipeRevisions)
            ..where((r) => r.recipeId.equals(recipeId))
            ..orderBy([(r) => OrderingTerm.desc(r.revision)]))
          .get();

  Stream<List<RecipeRevision>> watchRevisionsFor(String recipeId) =>
      (select(recipeRevisions)
            ..where((r) => r.recipeId.equals(recipeId))
            ..orderBy([(r) => OrderingTerm.desc(r.revision)]))
          .watch();

  Future<RecipeRevision?> latestRevisionFor(String recipeId) =>
      (select(recipeRevisions)
            ..where((r) => r.recipeId.equals(recipeId))
            ..orderBy([(r) => OrderingTerm.desc(r.revision)])
            ..limit(1))
          .getSingleOrNull();

  /// Lines of one revision, in entry order.
  Future<List<RecipeLine>> linesForRevision(String revisionId) =>
      (select(recipeLines)
            ..where((l) => l.revisionId.equals(revisionId))
            ..orderBy([(l) => OrderingTerm.asc(l.lineIndex)]))
          .get();
}
