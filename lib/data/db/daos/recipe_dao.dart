import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'recipe_dao.g.dart';

/// Recipe reads. Mutation stays with the CommandApplier (design §6.4);
/// this DAO exposes none.
@DriftAccessor(tables: [Recipes, RecipeRevisions, RecipeLinesV2])
class RecipeDao extends DatabaseAccessor<AppDatabase> with _$RecipeDaoMixin {
  RecipeDao(super.db);

  Future<Recipe?> byId(String id) =>
      (select(recipes)..where((r) => r.id.equals(id))).getSingleOrNull();

  Stream<Recipe?> watchById(String id) =>
      (select(recipes)..where((r) => r.id.equals(id))).watchSingleOrNull();

  /// Every recipe, live first, then case-insensitively by name.
  Stream<List<Recipe>> watchAll() => _allQuery().watch();

  /// One-shot [watchAll]. Callers assembling a summary inside a stream
  /// transform must use this: awaiting `watchAll().first` there opens a
  /// second query stream that never delivers.
  Future<List<Recipe>> all() => _allQuery().get();

  MultiSelectable<Recipe> _allQuery() => select(recipes)
    ..orderBy([
      (r) => OrderingTerm.asc(r.archivedAtMicros.isNotNull()),
      (r) => OrderingTerm.asc(r.name.lower()),
    ]);

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

  /// Lines of one revision, in entry order. v5: reads `recipe_lines_v2` —
  /// the legacy `recipe_lines` table is frozen history (see tables.dart).
  Future<List<RecipeLineV2>> linesForRevision(String revisionId) =>
      (select(recipeLinesV2)
            ..where((l) => l.revisionId.equals(revisionId))
            ..orderBy([(l) => OrderingTerm.asc(l.lineIndex)]))
          .get();
}
