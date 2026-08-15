import '../../../core/errors.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/unit_ratio.dart';
import '../../catalog/domain/demand_basis.dart';
import '../../events/domain/event.dart';
import '../../forecasting/domain/forecast_engine.dart';
import '../../forecasting/domain/snapshot.dart';
import '../../forecasting/domain/snapshot_inputs.dart';
import '../../inventory/domain/inventory_ledger.dart';
import '../../inventory/domain/movement.dart';
import '../../recipes/domain/recipe_drafts.dart';
import '../../recipes/domain/recipe_graph.dart';
import 'commands.dart';
import 'workspace_read_model.dart';

/// Exposure cap (design §3): `[1, 1_000_000]`.
const int maxExposure = 1000000;

/// Closeout depletion cap (design §3): 1e12 micros — the frozen engine's
/// safe envelope.
const int maxDepletionMicros = 1000000000000;

/// Cap for `items.serves_per_unit_micros`: 10 000 people served by one unit.
/// Mirrors `servesPerUnitCapMicros` in the §4 schema exactly as
/// [maxExposure] and [maxDepletionMicros] mirror their CHECKs — SQL stays
/// authoritative, this is the Dart-side message.
const int maxServesPerUnitMicros = 10000000000;

/// Cap for `items.per_event_baseline_micros` (v3): the 1e12-micros closeout
/// depletion envelope. Mirrors `perEventBaselineCapMicros` in the schema.
const int maxPerEventBaselineMicros = 1000000000000;

/// Cap for each part of the flipped "N per person" ratio (v3). Mirrors
/// `perPersonRatioPartCap` in the schema.
const int maxPerPersonRatioPart = 10000;

/// Proof token: only [CommandValidator] can construct one, so a
/// CommandApplier can require validated input by type.
final class ValidatedCommand {
  const ValidatedCommand._(this.command);

  final WorkspaceCommand command;
}

/// Pure invariant checker for the single write path (design §6.4). SQL
/// enforces shape; this class enforces semantics — including the Dart-side
/// `withLength` constraints SQLite never sees.
final class CommandValidator {
  const CommandValidator();

  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _hashPattern = RegExp(r'^[0-9a-f]{64}$');

  Result<ValidatedCommand> validate(
    WorkspaceCommand command,
    WorkspaceReadModel state,
  ) {
    final error = switch (command) {
      CreateItem() => _createItem(command, state),
      UpdateItem() => _updateItem(command, state),
      SetItemArchived() => _setItemArchived(command, state),
      CreateFolder() => _createFolder(command, state),
      RenameFolder() => _renameFolder(command, state),
      ReorderFolders() => _reorderFolders(command, state),
      ArchiveFolder() => _archiveFolder(command, state),
      SetFolderBasis() => _setFolderBasis(command, state),
      MoveItemToFolder() => _moveItemToFolder(command, state),
      MoveItemsToFolder() => _moveItemsToFolder(command, state),
      CreateEvent() => _createEvent(command, state),
      UpdateEvent() => _updateEvent(command, state),
      ActivateEvent() => _activateEvent(command, state),
      CancelEvent() => _cancelEvent(command, state),
      AppendMovement() => _appendMovement(command, state),
      CorrectMovement() => _correctMovement(command, state),
      RecordCloseout() => _recordCloseout(command, state),
      ReviseCloseout() => _reviseCloseout(command, state),
      CreateRecipe() => _createRecipe(command, state),
      AddRecipeRevision() => _addRecipeRevision(command, state),
      SetRecipeArchived() => _setRecipeArchived(command, state),
      SaveForecastSnapshot() => _saveForecastSnapshot(command, state),
      OverrideForecastLine() => _overrideForecastLine(command, state),
    };
    if (error != null) return Err(error);
    return Ok(ValidatedCommand._(command));
  }

  // ------------------------------------------------------------ catalog

  DomainError? _createItem(CreateItem c, WorkspaceReadModel state) {
    final fields = _itemFields(
      name: c.name,
      packSize: c.packSize,
      servesPerUnit: c.servesPerUnit,
      perPersonRatio: c.perPersonRatio,
      perEventBaseline: c.perEventBaseline,
      category: c.category,
    );
    if (fields != null) return fields;
    if (c.servesPerUnit != null && c.perPersonRatio != null) {
      return const ValidationError(
        'answer either "1 serves N" or "N per person", not both',
      );
    }
    final folder = _liveFolderRef(c.folderId as String?, state);
    if (folder != null) return folder;
    if (state.isItemNameTakenLive(c.name.trim())) {
      return const ValidationError('a live item with this name already exists');
    }
    // The opening count rides along as one `adjust` movement in the same
    // transaction, so it answers to the same envelope the ledger does.
    final opening = c.openingCount;
    if (opening != null && opening.micros > Quantity.maxMicros) {
      return const DomainOverflowError('opening count exceeds the cap');
    }
    return null;
  }

  DomainError? _updateItem(UpdateItem c, WorkspaceReadModel state) {
    final item = state.item(c.itemId as String);
    if (item == null) return const NotFoundError('item not found');
    if (item.archived) {
      return const ValidationError('item is archived; unarchive it first');
    }
    final fields = _itemFields(
      name: c.name,
      packSize: c.packSize,
      servesPerUnit: c.servesPerUnit,
      perPersonRatio: c.perPersonRatio,
      perEventBaseline: c.perEventBaseline,
      category: c.category,
    );
    if (fields != null) return fields;
    // The POST state may never carry both cold-start phrasings at once —
    // checked against the stored values, not just this command's fields.
    final servesAfter =
        c.servesPerUnit?.micros ??
        (c.clearServesPerUnit ? null : item.servesPerUnitMicros);
    final ratioAfter =
        c.perPersonRatio?.numerator ??
        (c.clearPerPersonRatio ? null : item.perPersonNumerator);
    if (servesAfter != null && ratioAfter != null) {
      return const ValidationError(
        'answer either "1 serves N" or "N per person", not both',
      );
    }
    final folder = _liveFolderRef(c.folderId as String?, state);
    if (folder != null) return folder;
    if (c.name != null &&
        state.isItemNameTakenLive(c.name!.trim(), excludingItemId: item.id)) {
      return const ValidationError('a live item with this name already exists');
    }
    if (c.unit != null && c.unit != item.unit && item.hasMovements) {
      return const ImmutableRecordError(
        'unit is locked after the first movement; archive and recreate '
        'the item to change it',
      );
    }
    return null;
  }

  DomainError? _setItemArchived(SetItemArchived c, WorkspaceReadModel state) {
    final item = state.item(c.itemId as String);
    if (item == null) return const NotFoundError('item not found');
    if (!c.archived &&
        item.archived &&
        state.isItemNameTakenLive(item.name, excludingItemId: item.id)) {
      return const ValidationError(
        'a live item with this name already exists; rename it first',
      );
    }
    return null;
  }

  DomainError? _itemFields({
    String? name,
    Quantity? packSize,
    Quantity? servesPerUnit,
    UnitRatio? perPersonRatio,
    Quantity? perEventBaseline,
    String? category,
  }) {
    if (name != null && (name.trim().isEmpty || name.trim().length > 120)) {
      return const ValidationError('item name must be 1-120 characters');
    }
    if (packSize != null && packSize.micros <= 0) {
      return const ValidationError('pack size must be positive');
    }
    if (servesPerUnit != null) {
      if (servesPerUnit.micros <= 0) {
        return const ValidationError(
          'how many people one serves must be greater than zero',
        );
      }
      if (servesPerUnit.micros > maxServesPerUnitMicros) {
        return const ValidationError(
          'how many people one serves must be at most '
          '${maxServesPerUnitMicros ~/ Quantity.scale}',
        );
      }
    }
    if (perPersonRatio != null &&
        (perPersonRatio.numerator > maxPerPersonRatioPart ||
            perPersonRatio.denominator > maxPerPersonRatioPart)) {
      // UnitRatio construction already refuses non-positive parts.
      return const ValidationError(
        '"N per person" parts must be at most $maxPerPersonRatioPart',
      );
    }
    if (perEventBaseline != null) {
      if (perEventBaseline.micros <= 0) {
        return const ValidationError(
          'how many you usually bring must be greater than zero',
        );
      }
      if (perEventBaseline.micros > maxPerEventBaselineMicros) {
        return const ValidationError(
          'how many you usually bring exceeds the 1e12-micros envelope cap',
        );
      }
    }
    if (category != null &&
        (category.trim().isEmpty || category.trim().length > 60)) {
      return const ValidationError('category must be 1-60 characters');
    }
    return null;
  }

  /// Null is legal (Unfiled); a non-null folder must exist and be live.
  DomainError? _liveFolderRef(String? folderId, WorkspaceReadModel state) {
    if (folderId == null) return null;
    final folder = state.folder(folderId);
    if (folder == null) return const NotFoundError('folder not found');
    if (folder.archived) {
      return const ValidationError('folder is archived');
    }
    return null;
  }

  // ------------------------------------------------------------ folders

  DomainError? _createFolder(CreateFolder c, WorkspaceReadModel state) {
    final name = _folderName(c.name);
    if (name != null) return name;
    if (state.isFolderNameTakenLive(c.name.trim())) {
      return const ValidationError(
        'a live folder with this name already exists',
      );
    }
    return null;
  }

  DomainError? _renameFolder(RenameFolder c, WorkspaceReadModel state) {
    final folder = state.folder(c.folderId as String);
    if (folder == null) return const NotFoundError('folder not found');
    if (folder.archived) {
      return const ValidationError('folder is archived');
    }
    final name = _folderName(c.name);
    if (name != null) return name;
    if (state.isFolderNameTakenLive(
      c.name.trim(),
      excludingFolderId: folder.id,
    )) {
      return const ValidationError(
        'a live folder with this name already exists',
      );
    }
    return null;
  }

  DomainError? _reorderFolders(ReorderFolders c, WorkspaceReadModel state) {
    final ids = [for (final id in c.orderedFolderIds) id as String];
    if (ids.toSet().length != ids.length) {
      return const ValidationError('reordered folders must be distinct');
    }
    final live = {for (final folder in state.liveFolders()) folder.id};
    if (ids.toSet().length != live.length || !live.containsAll(ids)) {
      return const ValidationError(
        'a reorder must list every live folder exactly once',
      );
    }
    return null;
  }

  DomainError? _archiveFolder(ArchiveFolder c, WorkspaceReadModel state) {
    final folder = state.folder(c.folderId as String);
    if (folder == null) return const NotFoundError('folder not found');
    if (folder.archived) {
      return const ValidationError('folder is already archived');
    }
    return null;
  }

  DomainError? _setFolderBasis(SetFolderBasis c, WorkspaceReadModel state) {
    final folder = state.folder(c.folderId as String);
    if (folder == null) return const NotFoundError('folder not found');
    if (folder.archived) {
      return const ValidationError('folder is archived');
    }
    if (c.demandBasis == null && c.alwaysPlanned == null) {
      return const ValidationError(
        'set the demand basis, the always-planned flag, or both',
      );
    }
    return null;
  }

  DomainError? _moveItemToFolder(MoveItemToFolder c, WorkspaceReadModel state) {
    final item = state.item(c.itemId as String);
    if (item == null) return const NotFoundError('item not found');
    if (item.archived) {
      return const ValidationError('item is archived; unarchive it first');
    }
    return _liveFolderRef(c.folderId as String?, state);
  }

  DomainError? _moveItemsToFolder(
    MoveItemsToFolder c,
    WorkspaceReadModel state,
  ) {
    if (c.itemIds.isEmpty) {
      return const ValidationError('a batch move needs at least one item');
    }
    final ids = [for (final id in c.itemIds) id as String];
    if (ids.toSet().length != ids.length) {
      return const ValidationError('moved items must be distinct');
    }
    for (final id in ids) {
      final item = state.item(id);
      if (item == null) return const NotFoundError('item not found');
      if (item.archived) {
        return const ValidationError('item is archived; unarchive it first');
      }
    }
    return _liveFolderRef(c.folderId as String?, state);
  }

  DomainError? _folderName(String name) =>
      name.trim().isEmpty || name.trim().length > 60
      ? const ValidationError('folder name must be 1-60 characters')
      : null;

  // ------------------------------------------------------------- events

  DomainError? _createEvent(CreateEvent c, WorkspaceReadModel state) =>
      _eventFields(
        state,
        name: c.name,
        scheduledDate: c.scheduledDate,
        startsAtMicros: c.startsAt?.epochMicrosUtc,
        endsAtMicros: c.endsAt?.epochMicrosUtc,
        plannedExposure: c.plannedExposure,
        plannedItemIds: [for (final id in c.plannedItemIds) id as String],
      );

  DomainError? _updateEvent(UpdateEvent c, WorkspaceReadModel state) {
    final event = state.event(c.eventId as String);
    if (event == null) return const NotFoundError('event not found');
    if (event.status == EventStatus.closed) {
      return const ImmutableRecordError(
        'closed events are permanently locked; use a closeout revision',
      );
    }
    if (event.status == EventStatus.cancelled) {
      return const ValidationError('cancelled events cannot be edited');
    }
    return _eventFields(
      state,
      name: c.name,
      scheduledDate: c.scheduledDate,
      startsAtMicros: c.startsAt?.epochMicrosUtc ?? event.startsAtMicros,
      endsAtMicros: c.endsAt?.epochMicrosUtc ?? event.endsAtMicros,
      plannedExposure: c.plannedExposure,
      plannedItemIds: c.plannedItemIds == null
          ? null
          : [for (final id in c.plannedItemIds!) id as String],
    );
  }

  DomainError? _activateEvent(ActivateEvent c, WorkspaceReadModel state) {
    final event = state.event(c.eventId as String);
    if (event == null) return const NotFoundError('event not found');
    if (event.status != EventStatus.planned) {
      return const ValidationError('only planned events can be activated');
    }
    return null;
  }

  DomainError? _cancelEvent(CancelEvent c, WorkspaceReadModel state) {
    final event = state.event(c.eventId as String);
    if (event == null) return const NotFoundError('event not found');
    if (event.status != EventStatus.planned) {
      return const ValidationError(
        'only planned events can be cancelled; an activated event must be '
        'closed out',
      );
    }
    if (c.reason.trim().isEmpty) {
      return const ValidationError('a cancellation reason is required');
    }
    return null;
  }

  DomainError? _eventFields(
    WorkspaceReadModel state, {
    String? name,
    String? scheduledDate,
    int? startsAtMicros,
    int? endsAtMicros,
    int? plannedExposure,
    List<String>? plannedItemIds,
  }) {
    if (name != null && (name.trim().isEmpty || name.trim().length > 120)) {
      return const ValidationError('event name must be 1-120 characters');
    }
    if (scheduledDate != null && !_datePattern.hasMatch(scheduledDate)) {
      return const ValidationError('scheduled date must be YYYY-MM-DD');
    }
    if (startsAtMicros != null &&
        endsAtMicros != null &&
        endsAtMicros < startsAtMicros) {
      return const ValidationError('event end must not precede its start');
    }
    if (plannedExposure != null &&
        (plannedExposure < 1 || plannedExposure > maxExposure)) {
      return const ValidationError(
        'planned exposure must be between 1 and $maxExposure',
      );
    }
    if (plannedItemIds != null) {
      if (plannedItemIds.toSet().length != plannedItemIds.length) {
        return const ValidationError('planned items must be distinct');
      }
      for (final id in plannedItemIds) {
        final item = state.item(id);
        if (item == null) return const NotFoundError('planned item not found');
        if (item.archived) {
          return const ValidationError('planned item is archived');
        }
      }
    }
    return null;
  }

  // ------------------------------------------------------------- ledger

  DomainError? _appendMovement(AppendMovement c, WorkspaceReadModel state) =>
      _movementDraft(c.draft, state);

  DomainError? _correctMovement(CorrectMovement c, WorkspaceReadModel state) {
    final target = state.movement(c.target as String);
    if (target == null) return const NotFoundError('movement not found');
    if (target.kind == MovementKind.reversal) {
      return const ValidationError(
        'a reversal cannot be reversed; record a fresh original instead',
      );
    }
    if (target.kind == MovementKind.consume || target.isCloseoutLinked) {
      return const ValidationError(
        'closeout-written movements are corrected by closeout revisions',
      );
    }
    if (target.isReversed) {
      return const AlreadyReversedError('this movement was already corrected');
    }
    if (c.reason.trim().isEmpty) {
      return const ValidationError('a correction reason is required');
    }
    if (c.replacement != null) {
      return _movementDraft(c.replacement!, state);
    }
    return null;
  }

  DomainError? _movementDraft(MovementDraft draft, WorkspaceReadModel state) {
    switch (draft.kind) {
      case MovementKind.consume:
        return const ValidationError(
          'consume movements are written only by closeout application',
        );
      case MovementKind.reversal:
        return const ValidationError('reversal is not a legal draft kind');
      case MovementKind.receive:
      case MovementKind.waste:
      case MovementKind.adjust:
        break;
    }
    final item = state.item(draft.itemId as String);
    if (item == null) return const NotFoundError('item not found');
    if (item.archived) {
      return const ValidationError('item is archived; unarchive it first');
    }
    if (draft.deltaMicros == 0) {
      return const ValidationError('movement delta must not be zero');
    }
    if (draft.deltaMicros.abs() > Quantity.maxMicros) {
      return const DomainOverflowError('movement delta exceeds the cap');
    }
    if (draft.kind == MovementKind.receive && draft.deltaMicros <= 0) {
      return const ValidationError('receive movements must be positive');
    }
    if (draft.kind == MovementKind.waste && draft.deltaMicros >= 0) {
      return const ValidationError('waste movements must be negative');
    }
    if (draft.eventId != null) {
      if (draft.kind != MovementKind.waste) {
        return const ValidationError(
          'only waste movements may be linked to an event',
        );
      }
      final event = state.event(draft.eventId! as String);
      if (event == null) return const NotFoundError('event not found');
      if (event.status == EventStatus.closed ||
          event.status == EventStatus.cancelled) {
        return const ValidationError(
          'movements cannot be linked to a closed or cancelled event',
        );
      }
    }
    return null;
  }

  // ------------------------------------------------------------ closeout

  DomainError? _recordCloseout(RecordCloseout c, WorkspaceReadModel state) {
    final event = state.event(c.eventId as String);
    if (event == null) return const NotFoundError('event not found');
    if (event.status != EventStatus.active) {
      return const ValidationError(
        'closeout confirm is valid only for active events',
      );
    }
    if (state.latestCloseout(event.id) != null) {
      return const ValidationError('this event already has a closeout');
    }
    return _closeoutShared(c.confirmedExposure, c.lines, event, state);
  }

  DomainError? _reviseCloseout(ReviseCloseout c, WorkspaceReadModel state) {
    final event = state.event(c.eventId as String);
    if (event == null) return const NotFoundError('event not found');
    if (event.status != EventStatus.closed) {
      return const ValidationError(
        'closeout revision is valid only for closed events',
      );
    }
    if (state.latestCloseout(event.id) == null) {
      return const ValidationError('this event has no closeout to revise');
    }
    return _closeoutShared(c.confirmedExposure, c.lines, event, state);
  }

  DomainError? _closeoutShared(
    int confirmedExposure,
    List<CloseoutLineDraft> lines,
    EventState event,
    WorkspaceReadModel state,
  ) {
    if (confirmedExposure < 1 || confirmedExposure > maxExposure) {
      return const ValidationError(
        'confirmed exposure must be between 1 and $maxExposure',
      );
    }
    final seen = <String>{};
    for (final line in lines) {
      final itemId = line.itemId as String;
      if (!seen.add(itemId)) {
        return const ValidationError('closeout lines must be distinct items');
      }
      final item = state.item(itemId);
      if (item == null) return const NotFoundError('closeout item not found');
      if (item.archived) {
        return const ValidationError(
          'closeout item is archived; unarchive it first',
        );
      }
      if (!event.plannedItemIds.contains(itemId)) {
        return const ValidationError(
          'closeout lines must reference the event\'s planned items',
        );
      }
      if (line.depletion.micros > maxDepletionMicros) {
        return const ValidationError(
          'depletion exceeds the 1e12-micros envelope cap',
        );
      }
      if (line.loaded != null && line.returned != null && line.waste != null) {
        final derived =
            line.loaded!.micros - line.returned!.micros - line.waste!.micros;
        if (line.depletion.micros != derived) {
          return const ValidationError(
            'worksheet mismatch: depletion must equal '
            'loaded - returned - waste',
          );
        }
      }
    }
    return null;
  }

  // ------------------------------------------------------------- recipes

  DomainError? _createRecipe(CreateRecipe c, WorkspaceReadModel state) {
    final output = state.item(c.outputItemId as String);
    if (output == null) return const NotFoundError('output item not found');
    if (output.archived) {
      return const ValidationError('output item is archived');
    }
    if (c.name.trim().isEmpty || c.name.trim().length > 120) {
      return const ValidationError('recipe name must be 1-120 characters');
    }
    if (state.liveRecipeForOutput(output.id) != null) {
      return const ValidationError(
        'a live recipe for this output item already exists',
      );
    }
    return _revisionDraft(
      c.firstRevision,
      recipeId: '',
      outputItemId: output.id,
      state: state,
    );
  }

  DomainError? _addRecipeRevision(
    AddRecipeRevision c,
    WorkspaceReadModel state,
  ) {
    final recipe = state.recipe(c.recipeId as String);
    if (recipe == null) return const NotFoundError('recipe not found');
    if (recipe.archived) {
      return const ValidationError('recipe is archived; unarchive it first');
    }
    return _revisionDraft(
      c.revision,
      recipeId: recipe.id,
      outputItemId: recipe.outputItemId,
      state: state,
    );
  }

  DomainError? _setRecipeArchived(
    SetRecipeArchived c,
    WorkspaceReadModel state,
  ) {
    final recipe = state.recipe(c.recipeId as String);
    if (recipe == null) return const NotFoundError('recipe not found');
    if (!c.archived && recipe.archived) {
      final live = state.liveRecipeForOutput(recipe.outputItemId);
      if (live != null && live.id != recipe.id) {
        return const ValidationError(
          'another live recipe for this output item already exists',
        );
      }
    }
    return null;
  }

  DomainError? _revisionDraft(
    RecipeRevisionDraft draft, {
    required String recipeId,
    required String outputItemId,
    required WorkspaceReadModel state,
  }) {
    if (draft.yieldQuantity.micros <= 0) {
      return const ValidationError('recipe yield must be positive');
    }
    if (draft.lines.isEmpty) {
      return const ValidationError(
        'a recipe revision needs at least one ingredient',
      );
    }
    final seen = <String>{};
    for (final line in draft.lines) {
      final ingredientId = line.ingredientItemId as String;
      if (!seen.add(ingredientId)) {
        return const ValidationError('recipe ingredients must be distinct');
      }
      final ingredient = state.item(ingredientId);
      if (ingredient == null) {
        return const NotFoundError('ingredient item not found');
      }
      if (ingredient.archived) {
        return const ValidationError('ingredient item is archived');
      }
      if (line.quantityPerBatch.micros <= 0) {
        return const ValidationError(
          'ingredient quantity per batch must be positive',
        );
      }
    }
    final candidate = RecipeNode(
      recipeId: recipeId,
      outputItemId: outputItemId,
      ingredientItemIds: seen.toList(),
    );
    final liveNodes = state.liveRecipeNodes();
    final flat = RecipeGraph(liveNodes).assertFlat(candidate);
    if (flat is Err<void>) return flat.error;
    final withCandidate = [
      for (final node in liveNodes)
        if (node.recipeId != recipeId) node,
      candidate,
    ];
    final cycles = RecipeGraph(withCandidate).detectCycles();
    if (cycles is Err<void>) return cycles.error;
    return null;
  }

  // ---------------------------------------------------------- forecasting

  DomainError? _saveForecastSnapshot(
    SaveForecastSnapshot c,
    WorkspaceReadModel state,
  ) {
    final draft = c.snapshot;
    final event = state.event(draft.eventId as String);
    if (event == null) return const NotFoundError('event not found');
    if (event.status != EventStatus.planned &&
        event.status != EventStatus.active) {
      return const ValidationError(
        'snapshots are valid only while the event is planned or active',
      );
    }
    if (draft.upcomingExposure < 1 || draft.upcomingExposure > maxExposure) {
      return const ValidationError(
        'upcoming exposure must be between 1 and $maxExposure',
      );
    }
    if (draft.historyWindow < 1) {
      return const ValidationError('history window must be positive');
    }
    if (!_hashPattern.hasMatch(draft.inputsHash)) {
      return const ValidationError(
        'inputs hash must be 64 lowercase hex characters',
      );
    }
    final seen = <String>{};
    for (final line in draft.lines) {
      final itemId = line.itemId as String;
      if (!seen.add(itemId)) {
        return const ValidationError('snapshot lines must be distinct items');
      }
      final item = state.item(itemId);
      if (item == null) return const NotFoundError('snapshot item not found');
      if (item.archived) {
        return const ValidationError('snapshot item is archived');
      }
      if (line.packSizeMicros <= 0) {
        return const ValidationError('snapshot pack size must be positive');
      }
      if (line.confirmedInboundMicros < 0) {
        return const ValidationError('confirmed inbound must be nonnegative');
      }
      for (final value in [
        line.expectedUseMicros,
        line.plannedMicros,
        line.loadMicros,
        line.acquireMicros,
      ]) {
        if (value != null && value < 0) {
          return const ValidationError('snapshot outputs must be nonnegative');
        }
      }
      final insufficient = line.evidenceGrade == EvidenceGrade.insufficientData;
      if (insufficient != (line.expectedUseMicros == null)) {
        return const ValidationError(
          'insufficient_data lines must have null outputs and vice versa',
        );
      }
      final baseline = _baselineFields(line, insufficient: insufficient);
      if (baseline != null) return baseline;
      for (final evidence in line.evidence) {
        if (!state.closeoutExists(evidence.closeoutId)) {
          return const NotFoundError('evidence closeout not found');
        }
        if (state.event(evidence.sourceEventId) == null) {
          return const NotFoundError('evidence source event not found');
        }
        if (evidence.exposure < 1 || evidence.exposure > maxExposure) {
          return const ValidationError('evidence exposure is out of range');
        }
        if (evidence.depletionMicros < 0 ||
            evidence.depletionMicros > maxDepletionMicros) {
          return const ValidationError('evidence depletion is out of range');
        }
      }
    }
    final recomputed = computeInputsHash(draft.inputs);
    if (recomputed != draft.inputsHash) {
      return const ValidationError(
        'inputs hash mismatch: snapshot inputs were tampered with or are '
        'stale',
      );
    }
    return null;
  }

  /// The no-history baseline is all-or-nothing, nonnegative, and legal ONLY
  /// on a line the engine could not forecast — a line with confirmed
  /// evidence must never carry a guess alongside it. v3: the four output
  /// fields travel with EXACTLY ONE source — serves-per-unit, the "N per
  /// person" ratio pair, or the per-event usual amount — and the source must
  /// match the line's demand basis.
  DomainError? _baselineFields(
    ForecastSnapshotLineDraft line, {
    required bool insufficient,
  }) {
    final ratioHalves = [
      line.baselinePerPersonNumerator,
      line.baselinePerPersonDenominator,
    ].where((v) => v != null).length;
    if (ratioHalves == 1) {
      return const ValidationError(
        'a baseline per-person ratio must set both parts or neither',
      );
    }
    final outputs = [
      line.baselineExpectedUseMicros,
      line.baselinePlannedMicros,
      line.baselineLoadMicros,
      line.baselineAcquireMicros,
    ];
    final outputsPresent = outputs.where((v) => v != null).length;
    final sources = [
      line.baselineServesPerUnitMicros,
      line.baselinePerPersonNumerator,
      line.baselinePerEventMicros,
    ];
    final sourcesPresent = sources.where((v) => v != null).length;
    if (outputsPresent == 0 && sourcesPresent == 0) return null;
    if (outputsPresent != outputs.length || sourcesPresent != 1) {
      return const ValidationError(
        'a baseline estimate must set every baseline field or none, with '
        'exactly one source',
      );
    }
    if (!insufficient) {
      return const ValidationError(
        'a baseline estimate is only legal on a line with no confirmed '
        'evidence',
      );
    }
    if (line.evidence.isNotEmpty) {
      return const ValidationError(
        'a baseline estimate cannot carry confirmed evidence',
      );
    }
    final perEventLine = line.demandBasis == DemandBasis.perEvent;
    final perEventSource = line.baselinePerEventMicros != null;
    if (perEventLine != perEventSource) {
      return const ValidationError(
        'a baseline source must match the line\'s demand basis',
      );
    }
    final serves = line.baselineServesPerUnitMicros;
    if (serves != null && (serves <= 0 || serves > maxServesPerUnitMicros)) {
      return const ValidationError('baseline serves-per-unit is out of range');
    }
    final perEvent = line.baselinePerEventMicros;
    if (perEvent != null &&
        (perEvent <= 0 || perEvent > maxPerEventBaselineMicros)) {
      return const ValidationError('baseline per-event amount is out of range');
    }
    for (final part in [
      line.baselinePerPersonNumerator,
      line.baselinePerPersonDenominator,
    ]) {
      if (part != null && (part <= 0 || part > maxPerPersonRatioPart)) {
        return const ValidationError(
          'baseline per-person ratio is out of range',
        );
      }
    }
    for (final value in outputs) {
      if (value! < 0) {
        return const ValidationError('baseline outputs must be nonnegative');
      }
    }
    return null;
  }

  DomainError? _overrideForecastLine(
    OverrideForecastLine c,
    WorkspaceReadModel state,
  ) {
    final snapshot = state.snapshot(c.snapshotId as String);
    if (snapshot == null) return const NotFoundError('snapshot not found');
    if (!state.snapshotLineExists(snapshot.id, c.itemId as String)) {
      return const NotFoundError('snapshot has no line for this item');
    }
    final reason = c.reason.trim();
    if (reason.length < 3 || reason.length > 500) {
      return const ValidationError(
        'an override reason of 3-500 characters is required',
      );
    }
    return null;
  }
}
