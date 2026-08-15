// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recipe_dao.dart';

// ignore_for_file: type=lint
mixin _$RecipeDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTable get folders => attachedDatabase.folders;
  $ItemsTable get items => attachedDatabase.items;
  $RecipesTable get recipes => attachedDatabase.recipes;
  $RecipeRevisionsTable get recipeRevisions => attachedDatabase.recipeRevisions;
  $RecipeLinesTable get recipeLines => attachedDatabase.recipeLines;
  RecipeDaoManager get managers => RecipeDaoManager(this);
}

class RecipeDaoManager {
  final _$RecipeDaoMixin _db;
  RecipeDaoManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db.attachedDatabase, _db.items);
  $$RecipesTableTableManager get recipes =>
      $$RecipesTableTableManager(_db.attachedDatabase, _db.recipes);
  $$RecipeRevisionsTableTableManager get recipeRevisions =>
      $$RecipeRevisionsTableTableManager(
        _db.attachedDatabase,
        _db.recipeRevisions,
      );
  $$RecipeLinesTableTableManager get recipeLines =>
      $$RecipeLinesTableTableManager(_db.attachedDatabase, _db.recipeLines);
}
