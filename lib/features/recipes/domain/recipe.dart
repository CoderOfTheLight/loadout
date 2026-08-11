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
final class Recipe {
  const Recipe({
    required this.id,
    required this.outputItemId,
    required this.name,
    this.archivedAt,
    required this.createdAt,
  });

  final RecipeId id;
  final ItemId outputItemId;
  final String name;
  final Instant? archivedAt;
  final Instant createdAt;

  bool get isArchived => archivedAt != null;
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

/// One ingredient line: micros of the ingredient's own base unit per batch.
final class RecipeLine {
  const RecipeLine({
    required this.ingredientItemId,
    required this.quantityPerBatch,
  });

  final ItemId ingredientItemId;
  final Quantity quantityPerBatch;
}
