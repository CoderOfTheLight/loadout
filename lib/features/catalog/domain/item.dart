import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';

/// Immutable catalog item (design §6.2, mirrors §4 `items`).
final class Item {
  const Item({
    required this.id,
    required this.name,
    required this.unit,
    required this.packSize,
    this.category,
    this.notes = '',
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final ItemId id;
  final String name;
  final ItemUnit unit;

  /// Purchase/load rounding increment in the item's own unit. Engine
  /// packSize.
  final Quantity packSize;
  final String? category;
  final String notes;
  final Instant? archivedAt;
  final Instant createdAt;
  final Instant updatedAt;

  bool get isArchived => archivedAt != null;
}

/// Screen-facing item form draft (design §6.5). Carries every editable
/// field; the service maps it onto CreateItem/UpdateItem commands.
final class ItemDraft {
  const ItemDraft({
    required this.name,
    required this.unit,
    required this.packSize,
    this.category,
    this.notes = '',
  });

  final String name;
  final ItemUnit unit;
  final Quantity packSize;
  final String? category;
  final String notes;
}
