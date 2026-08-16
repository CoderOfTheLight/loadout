import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/time.dart';

/// Recipe source kinds (design §4 `recipe_revisions.source_kind`). 'ocr' is
/// allowed in the CHECK now so Gate 5 needs no migration.
enum RecipeSourceKind {
  form('form'),
  ocr('ocr');

  const RecipeSourceKind(this.dbValue);

  final String dbValue;

  static RecipeSourceKind fromDb(String value) => values.firstWhere(
    (kind) => kind.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'not a recipe source kind'),
  );
}

/// Recipe identity + output binding (design §6.2). At most one live recipe
/// per output item.
///
/// v5: [outputItemId] is null until the recipe is added to the item list
/// (`AddRecipeToItems` creates the output item and binds it here).
final class Recipe {
  const Recipe({
    required this.id,
    this.outputItemId,
    required this.name,
    this.archivedAt,
    required this.createdAt,
  });

  final RecipeId id;
  final ItemId? outputItemId;
  final String name;
  final Instant? archivedAt;
  final Instant createdAt;

  bool get isArchived => archivedAt != null;

  /// True once `AddRecipeToItems` has created the output item.
  bool get isInItems => outputItemId != null;
}

/// One immutable recipe revision with its lines (design §6.2). Current =
/// MAX(revision).
final class RecipeRevisionView {
  const RecipeRevisionView({
    required this.id,
    required this.recipeId,
    required this.revision,
    required this.yieldQuantity,
    this.yieldLabel,
    required this.sourceKind,
    this.note = '',
    required this.createdAt,
    required this.lines,
  });

  final RecipeRevisionId id;
  final RecipeId recipeId;
  final int revision;
  final Quantity yieldQuantity;
  final String? yieldLabel;
  final RecipeSourceKind sourceKind;
  final String note;
  final Instant createdAt;
  final List<RecipeLine> lines;
}

/// One ingredient line: micros per batch, the line's own name, an optional
/// display-only unit label, and an optional catalog link (v5 decoupling).
final class RecipeLine {
  const RecipeLine({
    required this.name,
    this.unitLabel,
    this.ingredientItemId,
    required this.quantityPerBatch,
  });

  /// Always present: the typed/pasted text, or the linked item's name as
  /// snapshotted when the line was written. Linked lines display the live
  /// item name; this is what remains after an unlink.
  final String name;

  /// Display label for the amount; never converted, never computed with.
  final String? unitLabel;

  /// Null = free line ("Add to items" is offered on it).
  final ItemId? ingredientItemId;
  final Quantity quantityPerBatch;

  bool get isLinked => ingredientItemId != null;
}
