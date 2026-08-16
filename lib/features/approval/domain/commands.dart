import '../../../core/folder_appearance.dart';
import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/time.dart';
import '../../../core/unit_ratio.dart';
import '../../../core/units.dart';
import '../../catalog/domain/demand_basis.dart';
import '../../forecasting/domain/snapshot.dart';
import '../../inventory/domain/inventory_ledger.dart';
import '../../recipes/domain/recipe_drafts.dart';

/// The single write path (design §6.4). Every record mutation is one of
/// these sealed commands, validated by CommandValidator and applied by
/// CommandApplier in one transaction with a `commands` audit row. Forms
/// build commands today; FunctionGemma (Gate 4) will emit proposals of the
/// same types.
sealed class WorkspaceCommand {
  const WorkspaceCommand();
}

// -------------------------------------------------------------- catalog
// Master data: plain in-place updates; no revision log in v1.

final class CreateItem extends WorkspaceCommand {
  const CreateItem({
    required this.name,
    this.unit = ItemUnit.each,
    this.packSize = Quantity.one,
    this.unitLabel,
    this.servesPerUnit,
    this.perPersonRatio,
    this.folderId,
    this.demandBasis,
    this.perEventBaseline,
    this.openingCount,
    this.category,
    this.notes = '',
  });

  final String name;

  /// v5: optional DISPLAY label for the amount ("tsp", "cup", "lbs";
  /// 1–24 chars). Never converted, never computed with.
  final String? unitLabel;

  /// Defaulted, not asked: units left the product surface in v2.
  final ItemUnit unit;

  /// Defaulted to one whole unit — "round to whole things".
  final Quantity packSize;

  /// How many people one unit serves; null when unknown. At most one of
  /// this and [perPersonRatio] may be set (two phrasings of one question).
  final Quantity? servesPerUnit;

  /// The flipped "N per person" exact ratio; null when unknown.
  final UnitRatio? perPersonRatio;

  /// v3: the folder to file the item under; null = Unfiled.
  final FolderId? folderId;

  /// v3: per-item override of the folder's demand basis; null inherits.
  final DemandBasis? demandBasis;

  /// v3: "how many do you usually bring?" — per-event cold-start baseline.
  final Quantity? perEventBaseline;

  /// How many the owner has right now. Written as an `adjust` movement in
  /// the SAME transaction as the item row, so an item can never exist
  /// without its opening movement nor a movement without its item. Null or
  /// zero records nothing (on-hand stays the ledger's derived 0).
  final Quantity? openingCount;
  final String? category;
  final String notes;
}

final class UpdateItem extends WorkspaceCommand {
  const UpdateItem({
    required this.itemId,
    this.name,
    this.unit,
    this.packSize,
    this.unitLabel,
    this.clearUnitLabel = false,
    this.servesPerUnit,
    this.clearServesPerUnit = false,
    this.perPersonRatio,
    this.clearPerPersonRatio = false,
    this.folderId,
    this.clearFolder = false,
    this.demandBasis,
    this.clearDemandBasis = false,
    this.perEventBaseline,
    this.clearPerEventBaseline = false,
    this.category,
    this.notes,
  });

  final ItemId itemId;
  final String? name;

  /// Unit is changeable ONLY while the item has no movements — the
  /// validator enforces the §4 unit lock (escape hatch: archive+recreate).
  final ItemUnit? unit;
  final Quantity? packSize;

  /// v5: null means "leave alone"; use [clearUnitLabel] to erase it. A
  /// display label only — freely changeable, no lock.
  final String? unitLabel;

  /// Erases `unit_label`. Ignored when [unitLabel] is set.
  final bool clearUnitLabel;

  /// Null means "leave alone"; use [clearServesPerUnit] to erase it.
  final Quantity? servesPerUnit;

  /// Erases `serves_per_unit_micros`. Ignored when [servesPerUnit] is set.
  final bool clearServesPerUnit;

  /// Null means "leave alone"; use [clearPerPersonRatio] to erase it. The
  /// validator rejects a post-state carrying both a ratio and a serves.
  final UnitRatio? perPersonRatio;
  final bool clearPerPersonRatio;

  /// Null means "leave alone"; [clearFolder] moves the item to Unfiled.
  final FolderId? folderId;
  final bool clearFolder;

  /// Null means "leave alone"; [clearDemandBasis] reverts to inheriting.
  final DemandBasis? demandBasis;
  final bool clearDemandBasis;

  /// Null means "leave alone"; use [clearPerEventBaseline] to erase it.
  final Quantity? perEventBaseline;
  final bool clearPerEventBaseline;
  final String? category;
  final String? notes;
}

final class SetItemArchived extends WorkspaceCommand {
  const SetItemArchived({required this.itemId, required this.archived});

  final ItemId itemId;
  final bool archived;
}

// -------------------------------------------------------------- folders
// Master data like items: plain in-place updates through the single write
// path. Renames can never orphan an item (items reference folders by FK,
// not by text); archiving moves a folder's items to Unfiled, never deletes.

final class CreateFolder extends WorkspaceCommand {
  const CreateFolder({
    required this.name,
    required this.demandBasis,
    this.alwaysPlanned = false,
    this.hue,
    this.iconName,
  });

  final String name;

  /// The folder's default answer to the one question.
  final DemandBasis demandBasis;

  /// "Comes along to every event": live items pre-added on event creation.
  final bool alwaysPlanned;

  /// v4: the chosen hue from the eight-name palette; null = never chose
  /// (effective hue is assigned by position order at display time).
  final FolderHue? hue;

  /// v4: the chosen icon from the curated grid (validator-enforced
  /// membership); null = never chose (effective icon by starter name).
  final String? iconName;
}

final class RenameFolder extends WorkspaceCommand {
  const RenameFolder({required this.folderId, required this.name});

  final FolderId folderId;
  final String name;
}

final class ReorderFolders extends WorkspaceCommand {
  const ReorderFolders(this.orderedFolderIds);

  /// EVERY live folder exactly once, in the owner's new packing order —
  /// positions become the list indices. A partial list is rejected: a
  /// reorder that silently forgets folders would scramble the sections.
  final List<FolderId> orderedFolderIds;
}

final class ArchiveFolder extends WorkspaceCommand {
  const ArchiveFolder(this.folderId);

  /// One-way: archiving stamps the folder and moves its items to Unfiled in
  /// the same transaction. Nothing is deleted; wanting it back means
  /// creating a folder with the same name (the live-name index frees it).
  final FolderId folderId;
}

/// v4: sets a folder's hue and/or icon (the folder-editor sheet's swatch row
/// and icon grid). Appearance is identity, not state — it never touches
/// numbers, and like [SetFolderBasis] it is a plain in-place update.
final class SetFolderAppearance extends WorkspaceCommand {
  const SetFolderAppearance({required this.folderId, this.hue, this.iconName});

  final FolderId folderId;

  /// Null leaves the hue alone. At least one field must be set.
  final FolderHue? hue;

  /// Null leaves the icon alone.
  final String? iconName;
}

final class SetFolderBasis extends WorkspaceCommand {
  const SetFolderBasis({
    required this.folderId,
    this.demandBasis,
    this.alwaysPlanned,
  });

  final FolderId folderId;

  /// Null leaves the basis alone. At least one field must be set.
  final DemandBasis? demandBasis;

  /// Null leaves the flag alone.
  final bool? alwaysPlanned;
}

final class MoveItemToFolder extends WorkspaceCommand {
  const MoveItemToFolder({required this.itemId, this.folderId});

  final ItemId itemId;

  /// Null = move to Unfiled.
  final FolderId? folderId;
}

/// Batch move for the tidy-up screen: one command, one transaction, one
/// audit row for "file these 12 under Drinks".
final class MoveItemsToFolder extends WorkspaceCommand {
  const MoveItemsToFolder({required this.itemIds, this.folderId});

  final List<ItemId> itemIds;

  /// Null = move to Unfiled.
  final FolderId? folderId;
}

// -------------------------------------------------------------- events
// Predictions: mutable until closed.

final class CreateEvent extends WorkspaceCommand {
  const CreateEvent({
    required this.name,
    required this.scheduledDate,
    this.startsAt,
    this.endsAt,
    this.plannedExposure,
    this.venue,
    this.notes,
    this.plannedItemIds = const [],
  });

  final String name;
  final String scheduledDate;
  final Instant? startsAt;
  final Instant? endsAt;
  final int? plannedExposure;
  final String? venue;
  final String? notes;
  final List<ItemId> plannedItemIds;
}

final class UpdateEvent extends WorkspaceCommand {
  const UpdateEvent({
    required this.eventId,
    this.name,
    this.scheduledDate,
    this.startsAt,
    this.endsAt,
    this.plannedExposure,
    this.venue,
    this.notes,
    this.plannedItemIds,
  });

  final EventId eventId;
  final String? name;
  final String? scheduledDate;
  final Instant? startsAt;
  final Instant? endsAt;
  final int? plannedExposure;
  final String? venue;
  final String? notes;
  final List<ItemId>? plannedItemIds;
}

final class ActivateEvent extends WorkspaceCommand {
  const ActivateEvent(this.eventId);

  final EventId eventId;
}

final class CancelEvent extends WorkspaceCommand {
  const CancelEvent({required this.eventId, required this.reason});

  final EventId eventId;

  /// Valid only while 'planned'.
  final String reason;
}

// -------------------------------------------------------------- ledger

final class AppendMovement extends WorkspaceCommand {
  const AppendMovement(this.draft);

  /// Kinds receive|waste|adjust only from forms.
  final MovementDraft draft;
}

final class CorrectMovement extends WorkspaceCommand {
  const CorrectMovement({
    required this.target,
    this.replacement,
    required this.reason,
  });

  final MovementId target;
  final MovementDraft? replacement;

  /// Reversal + optional replacement, one transaction.
  final String reason;
}

// -------------------------------------------------------------- closeout
// Writes header+lines+movements atomically (design §5).

final class RecordCloseout extends WorkspaceCommand {
  const RecordCloseout({
    required this.eventId,
    required this.confirmedExposure,
    required this.lines,
    this.note = '',
  });

  final EventId eventId;
  final int confirmedExposure;
  final List<CloseoutLineDraft> lines;
  final String note;
}

final class ReviseCloseout extends WorkspaceCommand {
  const ReviseCloseout({
    required this.eventId,
    required this.confirmedExposure,
    required this.lines,
    this.note = '',
  });

  final EventId eventId;
  final int confirmedExposure;
  final List<CloseoutLineDraft> lines;
  final String note;
}

final class CloseoutLineDraft {
  const CloseoutLineDraft({
    required this.itemId,
    this.loaded,
    this.returned,
    this.waste,
    required this.depletion,
    this.stockout = false,
    this.approximate = false,
  });

  final ItemId itemId;
  final Quantity? loaded;
  final Quantity? returned;
  final Quantity? waste;
  final Quantity depletion;
  final bool stockout;
  final bool approximate;
}

// -------------------------------------------------------------- recipes

final class CreateRecipe extends WorkspaceCommand {
  const CreateRecipe({
    this.outputItemId,
    required this.name,
    required this.firstRevision,
  });

  /// v5: OPTIONAL — a recipe exists on its own; null means "not added to
  /// the item list" (the normal decoupled case; [AddRecipeToItems] creates
  /// and binds the output item later). A non-null id binds an existing
  /// live item at creation, exactly as before v5.
  final ItemId? outputItemId;
  final String name;
  final RecipeRevisionDraft firstRevision;
}

final class AddRecipeRevision extends WorkspaceCommand {
  const AddRecipeRevision({required this.recipeId, required this.revision});

  final RecipeId recipeId;
  final RecipeRevisionDraft revision;
}

final class SetRecipeArchived extends WorkspaceCommand {
  const SetRecipeArchived({required this.recipeId, required this.archived});

  final RecipeId recipeId;
  final bool archived;
}

/// v5: puts the RECIPE itself on the item list — creates its output item in
/// [folderId] (named after the recipe), binds `recipes.output_item_id`, and
/// optionally creates + links items for chosen free ingredient lines, all in
/// ONE transaction through this single command. Idempotent-guarded: a recipe
/// that is already in the items list is rejected with a plain error.
final class AddRecipeToItems extends WorkspaceCommand {
  const AddRecipeToItems({
    required this.recipeId,
    this.folderId,
    this.ingredients = const [],
  });

  final RecipeId recipeId;

  /// The folder the output item goes into; null = Unfiled. One folder per
  /// item, folders never nest — the "group" the items list shows for this
  /// item is a VIEW over the recipe's lines, not data nesting.
  final FolderId? folderId;

  /// Free (unlinked) lines of the CURRENT revision to also create items
  /// for, each filed independently.
  final List<AddRecipeIngredient> ingredients;
}

/// One "also create an item for this free line" choice.
final class AddRecipeIngredient {
  const AddRecipeIngredient({required this.lineIndex, this.folderId});

  /// Index of the free line within the recipe's CURRENT revision.
  final int lineIndex;

  /// Null = Unfiled.
  final FolderId? folderId;
}

/// v5: links a free line of the recipe's CURRENT revision to a live catalog
/// item. The line's content (name, amount, unit label) is frozen with its
/// revision; the link is mutable metadata (see recipe_lines_v2 triggers).
final class LinkRecipeLineToItem extends WorkspaceCommand {
  const LinkRecipeLineToItem({
    required this.recipeId,
    required this.lineIndex,
    required this.itemId,
  });

  final RecipeId recipeId;
  final int lineIndex;
  final ItemId itemId;
}

/// v5: removes the catalog link from a line of the recipe's CURRENT
/// revision. The line keeps its own name and renders as a free line again.
final class UnlinkRecipeLine extends WorkspaceCommand {
  const UnlinkRecipeLine({required this.recipeId, required this.lineIndex});

  final RecipeId recipeId;
  final int lineIndex;
}

// -------------------------------------------------------------- forecasting

final class SaveForecastSnapshot extends WorkspaceCommand {
  const SaveForecastSnapshot(this.snapshot);

  /// Fully-computed snapshot (header, lines, evidence, inputsHash). The
  /// applier recomputes inputsHash from the embedded inputs and rejects on
  /// mismatch (tamper/staleness check). Valid while event is
  /// planned|active.
  final ForecastSnapshotDraft snapshot;
}

final class OverrideForecastLine extends WorkspaceCommand {
  const OverrideForecastLine({
    required this.snapshotId,
    required this.itemId,
    this.overrideLoad,
    required this.reason,
  });

  final ForecastSnapshotId snapshotId;
  final ItemId itemId;

  /// null = revert to engine value (clear).
  final Quantity? overrideLoad;

  /// Mandatory, >= 3 chars.
  final String reason;
}
