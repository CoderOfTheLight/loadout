import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'recipe_dao.g.dart';

/// Recipe reads. Mutation stays with the CommandApplier (design §6.4);
/// Gate 2 domain services add methods here.
@DriftAccessor(tables: [Recipes, RecipeRevisions, RecipeLines])
class RecipeDao extends DatabaseAccessor<AppDatabase> with _$RecipeDaoMixin {
  RecipeDao(super.db);
}
