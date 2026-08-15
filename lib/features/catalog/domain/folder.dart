import '../../../core/ids.dart';
import '../../../core/time.dart';
import 'demand_basis.dart';

/// Immutable folder (v3 `folders`). One folder per item, from a short
/// managed list the owner renames, adds to, and reorders — no nesting.
/// Every list in the app reads in folder order with a header per folder;
/// NULL `items.folder_id` is the "Unfiled" section at the end.
final class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.position,
    required this.demandBasis,
    this.alwaysPlanned = false,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final FolderId id;
  final String name;

  /// The owner's packing order; lists read ascending.
  final int position;

  /// The folder's default answer to the one question; items may override.
  final DemandBasis demandBasis;

  /// True when this folder's live items are pre-added to every new event
  /// ("comes along to every event").
  final bool alwaysPlanned;
  final Instant? archivedAt;
  final Instant createdAt;
  final Instant updatedAt;

  bool get isArchived => archivedAt != null;
}
