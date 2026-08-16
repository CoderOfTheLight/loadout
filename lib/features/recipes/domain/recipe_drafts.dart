import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import 'recipe.dart';

/// One draft ingredient line for a to-be-appended revision.
///
/// v5 (recipe decoupling): a line is free text first — a [name], an amount,
/// and an optional display-only [unitLabel] — with an OPTIONAL catalog link.
/// At least one of [name] and [ingredientItemId] must be present (validator-
/// enforced); when only the link is given, the applier snapshots the linked
/// item's name into the stored line so unlinking never leaves it nameless.
final class RecipeLineDraft {
  const RecipeLineDraft({
    this.name,
    this.unitLabel,
    this.ingredientItemId,
    required this.quantityPerBatch,
  });

  /// The line's own ingredient name; null only when [ingredientItemId] is
  /// set (the item's name is snapshotted at write time).
  final String? name;

  /// Display label for the amount ("tsp", "cup", "lbs"); never converted,
  /// never computed with. 1–24 characters when present.
  final String? unitLabel;

  /// Optional catalog link; null = free line.
  final ItemId? ingredientItemId;
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
///
/// v5: [outputItemId] is optional — a recipe no longer needs a catalog item
/// to exist. Adding the recipe's output to the item list is a separate,
/// later act (`RecipeService.addToItems`).
final class RecipeFormDraft {
  const RecipeFormDraft({
    required this.name,
    this.outputItemId,
    required this.yieldQuantity,
    this.yieldLabel,
    this.note = '',
    this.sourceKind = RecipeSourceKind.form,
    required this.lines,
  });

  final String name;
  final String? outputItemId;
  final Quantity yieldQuantity;
  final String? yieldLabel;
  final String note;

  /// How the revision's content arrived: [RecipeSourceKind.ocr] when any
  /// scanned capture landed rows on the form, [RecipeSourceKind.form]
  /// otherwise (typed or pasted by hand).
  final RecipeSourceKind sourceKind;
  final List<RecipeFormLine> lines;
}

/// One form ingredient row: free text plus an optional catalog link,
/// mirroring [RecipeLineDraft].
final class RecipeFormLine {
  const RecipeFormLine({
    this.name,
    this.unitLabel,
    this.itemId,
    required this.quantityPerBatch,
  });

  final String? name;
  final String? unitLabel;
  final String? itemId;
  final Quantity quantityPerBatch;
}
