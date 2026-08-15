import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/time.dart';
import '../../../core/unit_ratio.dart';
import '../../../core/units.dart';
import 'demand_basis.dart';

/// Immutable catalog item (design §6.2, mirrors §4 `items`).
///
/// The owner's model of an item is NAME + HOW MANY YOU HAVE + optionally HOW
/// MANY PEOPLE ONE SERVES. [unit] and [packSize] survive from schema v1 for
/// the frozen engine's packSize parameter and for rows created before v2;
/// nothing asks the owner about them any more. New items are always
/// [ItemUnit.each] with a pack size of [Quantity.one].
final class Item {
  const Item({
    required this.id,
    required this.name,
    this.unit = ItemUnit.each,
    this.packSize = Quantity.one,
    this.servesPerUnit,
    this.perPersonRatio,
    this.folderId,
    this.demandBasis,
    this.perEventBaseline,
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
  /// packSize. One unit = "round to whole things".
  final Quantity packSize;

  /// How many people ONE of this item serves ("1 pizza serves 4"). Null when
  /// the owner never said — then a first-ever event simply gets no estimate.
  /// A planning assumption, never a forecasting label.
  final Quantity? servesPerUnit;

  /// The flipped phrasing: "N per person" ("3 napkins per person"), exact
  /// integer ratio so 200 people × 3/person is exactly 600. Mutually
  /// exclusive with [servesPerUnit] — two phrasings of one question.
  final UnitRatio? perPersonRatio;

  /// The folder this item lives in; null = "Unfiled" (shown last, never
  /// hidden).
  final FolderId? folderId;

  /// Per-item override of the folder's demand basis; null inherits. Resolve
  /// ONLY via [effectiveDemandBasis].
  final DemandBasis? demandBasis;

  /// "How many do you usually bring?" — the per-event cold-start baseline.
  /// A planning assumption, never a forecasting label.
  final Quantity? perEventBaseline;
  final String? category;
  final String notes;
  final Instant? archivedAt;
  final Instant createdAt;
  final Instant updatedAt;

  bool get isArchived => archivedAt != null;
}

/// Screen-facing item form draft (design §6.5). Carries every editable
/// field; the service maps it onto CreateItem/UpdateItem commands.
///
/// The form asks for [name], [servesPerUnit] (optional) and — on create only,
/// via `CatalogService.createItem(draft, openingCount: …)` — how many the
/// owner has right now. [unit] and [packSize] are defaulted, not asked.
final class ItemDraft {
  const ItemDraft({
    required this.name,
    this.servesPerUnit,
    this.perPersonRatio,
    this.folderId,
    this.demandBasis,
    this.perEventBaseline,
    this.unit = ItemUnit.each,
    this.packSize = Quantity.one,
    this.category,
    this.notes = '',
  });

  final String name;

  /// Null clears the stored value on update ("I don't know" is a legal
  /// answer, and the form always submits its whole state).
  final Quantity? servesPerUnit;

  /// The flipped "N per person" phrasing; null clears on update. At most one
  /// of this and [servesPerUnit] may be set.
  final UnitRatio? perPersonRatio;

  /// Null files the item under "Unfiled" (and clears on update).
  final String? folderId;

  /// Null inherits the folder's basis (and clears the override on update).
  final DemandBasis? demandBasis;

  /// "How many do you usually bring?"; null clears on update.
  final Quantity? perEventBaseline;
  final ItemUnit unit;
  final Quantity packSize;
  final String? category;
  final String notes;
}
