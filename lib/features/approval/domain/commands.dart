import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
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
    this.servesPerUnit,
    this.openingCount,
    this.category,
    this.notes = '',
  });

  final String name;

  /// Defaulted, not asked: units left the product surface in v2.
  final ItemUnit unit;

  /// Defaulted to one whole unit — "round to whole things".
  final Quantity packSize;

  /// How many people one unit serves; null when unknown.
  final Quantity? servesPerUnit;

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
    this.servesPerUnit,
    this.clearServesPerUnit = false,
    this.category,
    this.notes,
  });

  final ItemId itemId;
  final String? name;

  /// Unit is changeable ONLY while the item has no movements — the
  /// validator enforces the §4 unit lock (escape hatch: archive+recreate).
  final ItemUnit? unit;
  final Quantity? packSize;

  /// Null means "leave alone"; use [clearServesPerUnit] to erase it.
  final Quantity? servesPerUnit;

  /// Erases `serves_per_unit_micros`. Ignored when [servesPerUnit] is set.
  final bool clearServesPerUnit;
  final String? category;
  final String? notes;
}

final class SetItemArchived extends WorkspaceCommand {
  const SetItemArchived({required this.itemId, required this.archived});

  final ItemId itemId;
  final bool archived;
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
    required this.outputItemId,
    required this.name,
    required this.firstRevision,
  });

  final ItemId outputItemId;
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
