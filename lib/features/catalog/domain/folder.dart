import '../../../core/folder_appearance.dart';
import '../../../core/ids.dart';
import '../../../core/time.dart';
import 'demand_basis.dart';

/// Immutable folder (v3 `folders`, appearance columns v4). One folder per
/// item, from a short managed list the owner renames, adds to, and reorders
/// — no nesting. Every list in the app reads in folder order with a header
/// per folder; NULL `items.folder_id` is the "Unfiled" section at the end.
final class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.position,
    required this.demandBasis,
    this.alwaysPlanned = false,
    this.hue,
    this.iconName,
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

  /// The owner's chosen hue (v4 `hue_name`); null = never chose, display
  /// [effectiveHue].
  final FolderHue? hue;

  /// The owner's chosen icon (v4 `icon_name`); null = never chose, display
  /// [effectiveIconName].
  final String? iconName;
  final Instant? archivedAt;
  final Instant createdAt;
  final Instant updatedAt;

  bool get isArchived => archivedAt != null;

  /// The hue every screen paints: the stored choice, else by position order
  /// — THE effective-hue rule, called, never re-derived.
  FolderHue get effectiveHue => hue ?? FolderHue.byPosition(position);

  /// The icon every screen draws: the stored choice, else the starter
  /// default for this name, else `inventory_2` — THE effective-icon rule.
  String get effectiveIconName => iconName ?? defaultFolderIconName(name);
}
