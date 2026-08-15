import '../../../core/units.dart';
import '../../catalog/domain/demand_basis.dart';
import '../../events/domain/event.dart';
import '../../inventory/domain/movement.dart';
import '../../recipes/domain/recipe_graph.dart';

/// Read-only state projection the pure [CommandValidator] checks invariants
/// against (design §6.4). Implementations prefetch whatever the command
/// under validation can reference; lookups are synchronous.
abstract interface class WorkspaceReadModel {
  /// Item by id, or null when unknown.
  ItemState? item(String id);

  /// True when a LIVE item other than [excludingItemId] already uses
  /// [name] case-insensitively (partial index uidx_items_name_live).
  bool isItemNameTakenLive(String name, {String? excludingItemId});

  /// Folder by id, or null when unknown.
  FolderState? folder(String id);

  /// Every live folder in position order (id as tiebreak).
  List<FolderState> liveFolders();

  /// True when a LIVE folder other than [excludingFolderId] already uses
  /// [name] case-insensitively (partial index uidx_folders_name_live).
  bool isFolderNameTakenLive(String name, {String? excludingFolderId});

  /// Event by id, or null when unknown.
  EventState? event(String id);

  /// Movement by id, or null when unknown.
  MovementState? movement(String id);

  /// Latest closeout revision for [eventId], or null when never closed out.
  CloseoutState? latestCloseout(String eventId);

  /// Recipe by id, or null when unknown.
  RecipeState? recipe(String id);

  /// The live recipe producing [outputItemId], or null.
  RecipeState? liveRecipeForOutput(String outputItemId);

  /// Every live recipe's latest revision as graph nodes.
  List<RecipeNode> liveRecipeNodes();

  /// Snapshot header by id, or null when unknown.
  SnapshotState? snapshot(String id);

  /// True when the snapshot has a line for [itemId].
  bool snapshotLineExists(String snapshotId, String itemId);

  /// True when a closeout header with [closeoutId] exists (evidence refs).
  bool closeoutExists(String closeoutId);
}

final class ItemState {
  const ItemState({
    required this.id,
    required this.name,
    required this.unit,
    required this.packSizeMicros,
    required this.archived,
    required this.hasMovements,
    this.servesPerUnitMicros,
    this.perPersonNumerator,
    this.perPersonDenominator,
  });

  final String id;
  final String name;
  final ItemUnit unit;
  final int packSizeMicros;
  final bool archived;

  /// True once the item has any movement — locks the unit (§4).
  final bool hasMovements;

  /// Stored cold-start answers, loaded so UpdateItem can validate the
  /// POST state: an item may never end up with both "1 serves N" and
  /// "N per person" at once.
  final int? servesPerUnitMicros;
  final int? perPersonNumerator;
  final int? perPersonDenominator;
}

/// One folder as the validator and applier see it.
final class FolderState {
  const FolderState({
    required this.id,
    required this.name,
    required this.position,
    required this.demandBasis,
    required this.alwaysPlanned,
    required this.archived,
  });

  final String id;
  final String name;
  final int position;
  final DemandBasis demandBasis;
  final bool alwaysPlanned;
  final bool archived;
}

final class EventState {
  const EventState({
    required this.id,
    required this.status,
    required this.scheduledDate,
    this.startsAtMicros,
    this.endsAtMicros,
    this.plannedExposure,
    required this.plannedItemIds,
  });

  final String id;
  final EventStatus status;
  final String scheduledDate;
  final int? startsAtMicros;
  final int? endsAtMicros;
  final int? plannedExposure;
  final Set<String> plannedItemIds;
}

final class MovementState {
  const MovementState({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.deltaMicros,
    this.eventId,
    required this.isReversed,
    required this.isCloseoutLinked,
  });

  final String id;
  final String itemId;
  final MovementKind kind;
  final int deltaMicros;
  final String? eventId;

  /// True when a reversal already targets this movement
  /// (UNIQUE(reverses_movement_id): at most once).
  final bool isReversed;

  /// True when a closeout line links this movement as its consumption or
  /// waste evidence — such rows are corrected via closeout revisions only,
  /// never via CorrectMovement (protects the §5 mirroring contract).
  final bool isCloseoutLinked;
}

final class CloseoutState {
  const CloseoutState({
    required this.id,
    required this.eventId,
    required this.revision,
    required this.eventLinkedMovementIds,
  });

  final String id;
  final String eventId;
  final int revision;

  /// The consume/waste movements this revision's lines link to — the exact
  /// rows a revision N+1 must mirror-reverse (§5).
  final List<String> eventLinkedMovementIds;
}

final class RecipeState {
  const RecipeState({
    required this.id,
    required this.outputItemId,
    required this.archived,
    required this.latestRevision,
  });

  final String id;
  final String outputItemId;
  final bool archived;

  /// 0 when the recipe has no revisions yet (never true for stored rows).
  final int latestRevision;
}

final class SnapshotState {
  const SnapshotState({required this.id, required this.eventId});

  final String id;
  final String eventId;
}
