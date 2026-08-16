import 'package:drift/drift.dart';

import '../../../core/units.dart';
import '../../../data/db/app_database.dart';
import '../../catalog/domain/demand_basis.dart';
import '../../events/domain/event.dart' show EventStatus;
import '../../inventory/domain/movement.dart' show MovementKind;
import '../../recipes/domain/recipe_graph.dart';
import '../domain/commands.dart';
import '../domain/workspace_read_model.dart';

/// Immutable snapshot of exactly the state a command's validation and
/// application can reference, prefetched inside the applier's transaction.
final class PrefetchedState implements WorkspaceReadModel {
  const PrefetchedState({
    this.items = const {},
    this.folders = const {},
    this.events = const {},
    this.movements = const {},
    this.latestCloseouts = const {},
    this.recipes = const {},
    this.liveRecipesByOutput = const {},
    this.liveNodes = const [],
    this.snapshots = const {},
    this.snapshotLineKeys = const {},
    this.closeoutIds = const {},
  });

  final Map<String, ItemState> items;
  final Map<String, FolderState> folders;
  final Map<String, EventState> events;
  final Map<String, MovementState> movements;

  /// Latest closeout per event id.
  final Map<String, CloseoutState> latestCloseouts;
  final Map<String, RecipeState> recipes;
  final Map<String, RecipeState> liveRecipesByOutput;
  final List<RecipeNode> liveNodes;
  final Map<String, SnapshotState> snapshots;

  /// `'<snapshotId>|<itemId>'` keys.
  final Set<String> snapshotLineKeys;
  final Set<String> closeoutIds;

  @override
  ItemState? item(String id) => items[id];

  @override
  bool isItemNameTakenLive(String name, {String? excludingItemId}) {
    final lower = name.trim().toLowerCase();
    return items.values.any(
      (i) =>
          !i.archived &&
          i.id != excludingItemId &&
          i.name.toLowerCase() == lower,
    );
  }

  @override
  FolderState? folder(String id) => folders[id];

  @override
  List<FolderState> liveFolders() {
    final live = folders.values.where((f) => !f.archived).toList()
      ..sort(
        (a, b) => a.position != b.position
            ? a.position.compareTo(b.position)
            : a.id.compareTo(b.id),
      );
    return live;
  }

  @override
  bool isFolderNameTakenLive(String name, {String? excludingFolderId}) {
    final lower = name.trim().toLowerCase();
    return folders.values.any(
      (f) =>
          !f.archived &&
          f.id != excludingFolderId &&
          f.name.toLowerCase() == lower,
    );
  }

  @override
  EventState? event(String id) => events[id];

  @override
  MovementState? movement(String id) => movements[id];

  @override
  CloseoutState? latestCloseout(String eventId) => latestCloseouts[eventId];

  @override
  RecipeState? recipe(String id) => recipes[id];

  @override
  RecipeState? liveRecipeForOutput(String outputItemId) =>
      liveRecipesByOutput[outputItemId];

  @override
  List<RecipeNode> liveRecipeNodes() => liveNodes;

  @override
  SnapshotState? snapshot(String id) => snapshots[id];

  @override
  bool snapshotLineExists(String snapshotId, String itemId) =>
      snapshotLineKeys.contains('$snapshotId|$itemId');

  @override
  bool closeoutExists(String closeoutId) => closeoutIds.contains(closeoutId);
}

/// Builds the [PrefetchedState] for one command. Called by the applier
/// inside its transaction so validation sees the same state the effects
/// will.
final class DriftStateLoader {
  const DriftStateLoader(this._db);

  final AppDatabase _db;

  Future<PrefetchedState> load(WorkspaceCommand command) async {
    final eventIds = <String>{};
    final closeoutEventIds = <String>{};
    final movementIds = <String>{};
    final snapshotIds = <String>{};
    final evidenceCloseoutIds = <String>{};
    var needRecipes = false;

    switch (command) {
      case CreateItem() || UpdateItem() || SetItemArchived():
        break;
      case CreateFolder() ||
          RenameFolder() ||
          ReorderFolders() ||
          ArchiveFolder() ||
          SetFolderAppearance() ||
          SetFolderBasis() ||
          MoveItemToFolder() ||
          MoveItemsToFolder():
        // Folders (and items) are always prefetched below.
        break;
      case CreateEvent():
        break;
      case UpdateEvent():
        eventIds.add(command.eventId as String);
      case ActivateEvent():
        eventIds.add(command.eventId as String);
      case CancelEvent():
        eventIds.add(command.eventId as String);
      case AppendMovement():
        final eventId = command.draft.eventId;
        if (eventId != null) eventIds.add(eventId as String);
      case CorrectMovement():
        movementIds.add(command.target as String);
        final eventId = command.replacement?.eventId;
        if (eventId != null) eventIds.add(eventId as String);
      case RecordCloseout():
        eventIds.add(command.eventId as String);
        closeoutEventIds.add(command.eventId as String);
      case ReviseCloseout():
        eventIds.add(command.eventId as String);
        closeoutEventIds.add(command.eventId as String);
      case CreateRecipe() ||
          AddRecipeRevision() ||
          SetRecipeArchived() ||
          AddRecipeToItems() ||
          LinkRecipeLineToItem() ||
          UnlinkRecipeLine():
        needRecipes = true;
      case SaveForecastSnapshot():
        eventIds.add(command.snapshot.eventId as String);
        for (final line in command.snapshot.lines) {
          for (final evidence in line.evidence) {
            eventIds.add(evidence.sourceEventId);
            evidenceCloseoutIds.add(evidence.closeoutId);
          }
        }
      case OverrideForecastLine():
        snapshotIds.add(command.snapshotId as String);
    }

    return PrefetchedState(
      items: await _loadItems(),
      folders: await _loadFolders(),
      events: await _loadEvents(eventIds),
      movements: await _loadMovements(movementIds),
      latestCloseouts: await _loadLatestCloseouts(closeoutEventIds),
      recipes: needRecipes ? await _loadRecipes() : const {},
      liveRecipesByOutput: needRecipes ? await _loadLiveByOutput() : const {},
      liveNodes: needRecipes ? await _loadLiveNodes() : const [],
      snapshots: await _loadSnapshots(snapshotIds),
      snapshotLineKeys: await _loadSnapshotLineKeys(snapshotIds),
      closeoutIds: await _loadCloseoutIds(evidenceCloseoutIds),
    );
  }

  Future<Map<String, ItemState>> _loadItems() async {
    final rows = await _db.select(_db.items).get();
    final withMovements =
        (await _db
                .customSelect(
                  'SELECT DISTINCT item_id AS item_id FROM inventory_movements',
                )
                .get())
            .map((r) => r.read<String>('item_id'))
            .toSet();
    return {
      for (final row in rows)
        row.id: ItemState(
          id: row.id,
          name: row.name,
          unit: ItemUnit.fromDb(row.unit),
          packSizeMicros: row.packSizeMicros,
          archived: row.archivedAtMicros != null,
          hasMovements: withMovements.contains(row.id),
          servesPerUnitMicros: row.servesPerUnitMicros,
          perPersonNumerator: row.perPersonNumerator,
          perPersonDenominator: row.perPersonDenominator,
        ),
    };
  }

  /// Folders are a short managed list; loading them for every command is
  /// cheaper than deciding when they matter.
  Future<Map<String, FolderState>> _loadFolders() async {
    final rows = await _db.select(_db.folders).get();
    return {
      for (final row in rows)
        row.id: FolderState(
          id: row.id,
          name: row.name,
          position: row.position,
          demandBasis: DemandBasis.fromDb(row.demandBasis),
          alwaysPlanned: row.alwaysPlanned,
          archived: row.archivedAtMicros != null,
        ),
    };
  }

  Future<Map<String, EventState>> _loadEvents(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(
      _db.events,
    )..where((e) => e.id.isIn(ids))).get();
    final planned = await (_db.select(
      _db.eventItems,
    )..where((e) => e.eventId.isIn(ids))).get();
    final byEvent = <String, Set<String>>{};
    for (final row in planned) {
      byEvent.putIfAbsent(row.eventId, () => {}).add(row.itemId);
    }
    return {
      for (final row in rows)
        row.id: EventState(
          id: row.id,
          status: EventStatus.fromDb(row.status),
          scheduledDate: row.scheduledDate,
          startsAtMicros: row.startsAtMicros,
          endsAtMicros: row.endsAtMicros,
          plannedExposure: row.plannedExposure,
          plannedItemIds: byEvent[row.id] ?? const {},
        ),
    };
  }

  Future<Map<String, MovementState>> _loadMovements(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(
      _db.inventoryMovements,
    )..where((m) => m.id.isIn(ids))).get();
    final result = <String, MovementState>{};
    for (final row in rows) {
      final reversed =
          await (_db.select(_db.inventoryMovements)
                ..where((m) => m.reversesMovementId.equals(row.id))
                ..limit(1))
              .getSingleOrNull() !=
          null;
      final linked =
          await (_db.select(_db.closeoutLines)
                ..where(
                  (l) =>
                      l.consumptionMovementId.equals(row.id) |
                      l.wasteMovementId.equals(row.id),
                )
                ..limit(1))
              .getSingleOrNull() !=
          null;
      result[row.id] = MovementState(
        id: row.id,
        itemId: row.itemId,
        kind: MovementKind.fromDb(row.kind),
        deltaMicros: row.deltaMicros,
        eventId: row.eventId,
        isReversed: reversed,
        isCloseoutLinked: linked,
      );
    }
    return result;
  }

  Future<Map<String, CloseoutState>> _loadLatestCloseouts(
    Set<String> eventIds,
  ) async {
    if (eventIds.isEmpty) return const {};
    final result = <String, CloseoutState>{};
    for (final eventId in eventIds) {
      final header =
          await (_db.select(_db.eventCloseouts)
                ..where((c) => c.eventId.equals(eventId))
                ..orderBy([(c) => OrderingTerm.desc(c.revision)])
                ..limit(1))
              .getSingleOrNull();
      if (header == null) continue;
      final lines = await (_db.select(
        _db.closeoutLines,
      )..where((l) => l.closeoutId.equals(header.id))).get();
      result[eventId] = CloseoutState(
        id: header.id,
        eventId: eventId,
        revision: header.revision,
        eventLinkedMovementIds: [
          for (final line in lines) ...[
            if (line.consumptionMovementId != null) line.consumptionMovementId!,
            if (line.wasteMovementId != null) line.wasteMovementId!,
          ],
        ],
      );
    }
    return result;
  }

  Future<Map<String, RecipeState>> _loadRecipes() async {
    final rows = await _db
        .customSelect(
          'SELECT r.id AS id, r.name AS name, '
          'r.output_item_id AS output_item_id, '
          'r.archived_at_micros AS archived_at_micros, '
          'rev.id AS latest_revision_id, '
          'COALESCE(rev.revision, 0) AS latest_revision '
          'FROM recipes r '
          'LEFT JOIN recipe_revisions rev ON rev.recipe_id = r.id '
          'AND rev.revision = (SELECT MAX(r2.revision) '
          'FROM recipe_revisions r2 WHERE r2.recipe_id = r.id)',
          readsFrom: {_db.recipes, _db.recipeRevisions},
        )
        .get();
    final revisionIds = [
      for (final row in rows) ?row.read<String?>('latest_revision_id'),
    ];
    final linesByRevision = <String, List<RecipeLineState>>{};
    if (revisionIds.isNotEmpty) {
      final lineRows =
          await (_db.select(_db.recipeLinesV2)
                ..where((l) => l.revisionId.isIn(revisionIds))
                ..orderBy([(l) => OrderingTerm.asc(l.lineIndex)]))
              .get();
      for (final line in lineRows) {
        linesByRevision
            .putIfAbsent(line.revisionId, () => [])
            .add(
              RecipeLineState(
                lineIndex: line.lineIndex,
                name: line.ingredientName,
                unitLabel: line.unitLabel,
                ingredientItemId: line.ingredientItemId,
              ),
            );
      }
    }
    return {
      for (final row in rows)
        row.read<String>('id'): RecipeState(
          id: row.read<String>('id'),
          name: row.read<String>('name'),
          outputItemId: row.read<String?>('output_item_id'),
          archived: row.read<int?>('archived_at_micros') != null,
          latestRevision: row.read<int>('latest_revision'),
          latestRevisionId: row.read<String?>('latest_revision_id'),
          currentLines: switch (row.read<String?>('latest_revision_id')) {
            final id? => linesByRevision[id] ?? const [],
            null => const [],
          },
        ),
    };
  }

  Future<Map<String, RecipeState>> _loadLiveByOutput() async {
    final recipes = await _loadRecipes();
    return {
      for (final recipe in recipes.values)
        // Not-yet-added recipes have no output item to collide on.
        if (!recipe.archived && recipe.outputItemId != null)
          recipe.outputItemId!: recipe,
    };
  }

  Future<List<RecipeNode>> _loadLiveNodes() async {
    // v5: reads recipe_lines_v2; only LINKED lines are graph EDGES, and only
    // recipes WITH an output item can be producers — a not-yet-added recipe
    // cannot be nested into. The line join is a LEFT join on purpose: a live
    // recipe whose lines are all free still OWNS its output item, and the
    // flatness guard must still find it as that item's producer.
    final rows = await _db
        .customSelect(
          'SELECT r.id AS recipe_id, r.output_item_id AS output_item_id, '
          'rl.ingredient_item_id AS ingredient_item_id '
          'FROM recipes r '
          'JOIN recipe_revisions rr ON rr.recipe_id = r.id '
          'AND rr.revision = (SELECT MAX(r2.revision) FROM recipe_revisions r2 '
          'WHERE r2.recipe_id = r.id) '
          'LEFT JOIN recipe_lines_v2 rl ON rl.revision_id = rr.id '
          'AND rl.ingredient_item_id IS NOT NULL '
          'WHERE r.archived_at_micros IS NULL '
          'AND r.output_item_id IS NOT NULL '
          'ORDER BY r.id, rl.line_index',
          readsFrom: {_db.recipes, _db.recipeRevisions, _db.recipeLinesV2},
        )
        .get();
    final ingredients = <String, List<String>>{};
    final outputs = <String, String>{};
    for (final row in rows) {
      final recipeId = row.read<String>('recipe_id');
      outputs[recipeId] = row.read<String>('output_item_id');
      final linked = row.read<String?>('ingredient_item_id');
      final list = ingredients.putIfAbsent(recipeId, () => []);
      if (linked != null) list.add(linked);
    }
    return [
      for (final recipeId in outputs.keys)
        RecipeNode(
          recipeId: recipeId,
          outputItemId: outputs[recipeId]!,
          ingredientItemIds: ingredients[recipeId]!,
        ),
    ];
  }

  Future<Map<String, SnapshotState>> _loadSnapshots(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(
      _db.forecastSnapshots,
    )..where((s) => s.id.isIn(ids))).get();
    return {
      for (final row in rows)
        row.id: SnapshotState(id: row.id, eventId: row.eventId),
    };
  }

  Future<Set<String>> _loadSnapshotLineKeys(Set<String> snapshotIds) async {
    if (snapshotIds.isEmpty) return const {};
    final rows = await (_db.select(
      _db.forecastLines,
    )..where((l) => l.snapshotId.isIn(snapshotIds))).get();
    return {for (final row in rows) '${row.snapshotId}|${row.itemId}'};
  }

  Future<Set<String>> _loadCloseoutIds(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(
      _db.eventCloseouts,
    )..where((c) => c.id.isIn(ids))).get();
    return {for (final row in rows) row.id};
  }
}
