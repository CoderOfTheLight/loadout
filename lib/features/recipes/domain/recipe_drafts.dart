import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import 'recipe.dart';

/// One draft ingredient line for a to-be-appended revision.
final class RecipeLineDraft {
  const RecipeLineDraft({
    required this.ingredientItemId,
    required this.quantityPerBatch,
  });

  final ItemId ingredientItemId;
  final Quantity quantityPerBatch;
}

/// Draft of one immutable recipe revision (design §6.4 CreateRecipe /
/// AddRecipeRevision).
final class RecipeRevisionDraft {
  const RecipeRevisionDraft({
    required this.yieldQuantity,
    this.yieldLabel,
    this.note = '',
    this.sourceKind = RecipeSourceKind.form,
    required this.lines,
  });

  final Quantity yieldQuantity;
  final String? yieldLabel;
  final String note;
  final RecipeSourceKind sourceKind;
  final List<RecipeLineDraft> lines;
}

/// Screen-facing recipe form draft (design §6.5, §9 RecipeEditScreen). This
/// form is also the Gate 5 OCR prefill target ([RecipeOcr] seam).
final class RecipeFormDraft {
  const RecipeFormDraft({
    required this.name,
    required this.outputItemId,
    required this.yieldQuantity,
    this.yieldLabel,
    this.note = '',
    required this.lines,
  });

  final String name;
  final String outputItemId;
  final Quantity yieldQuantity;
  final String? yieldLabel;
  final String note;
  final List<RecipeFormLine> lines;
}

/// One form ingredient row.
final class RecipeFormLine {
  const RecipeFormLine({required this.itemId, required this.quantityPerBatch});

  final String itemId;
  final Quantity quantityPerBatch;
}
