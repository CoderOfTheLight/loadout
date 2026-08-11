import 'package:drift/drift.dart';

import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../../../data/db/app_database.dart' as db;
import '../../approval/domain/approval_service.dart';
import '../../approval/domain/commands.dart';
import '../../approval/domain/proposal.dart';
import '../domain/item.dart';

final class ItemFilter {
  const ItemFilter({this.search, this.category, this.includeArchived = false});

  final String? search;
  final String? category;
  final bool includeArchived;
}

/// One catalog list row with the derived signed on-hand (design §9
/// ItemListScreen: negatives shown signed, never clamped).
final class ItemSummary {
  const ItemSummary({required this.item, required this.onHandMicros});

  final Item item;
  final int onHandMicros;

  bool get isNegative => onHandMicros < 0;
}

final class ItemDetail {
  const ItemDetail({
    required this.item,
    required this.onHandMicros,
    required this.hasMovements,
  });

  final Item item;
  final int onHandMicros;

  /// True once any movement exists — the unit is locked (§4).
  final bool hasMovements;
}

/// Screen-facing catalog surface (design §6.5). Master data updates are
/// plain in-place updates through the command path; no revision log in v1.
abstract interface class CatalogService {
  /// Returns the created itemId.
  Future<Result<String>> createItem(ItemDraft draft);
  Future<Result<void>> updateItem({
    required String itemId,
    required ItemDraft draft,
  });
  Future<Result<void>> setArchived({
    required String itemId,
    required bool archived,
  });
  Stream<List<ItemSummary>> watchItems(ItemFilter filter);
  Stream<ItemDetail> watchItem(String itemId);
  Future<List<String>> categorySuggestions();
}

final class DriftCatalogService implements CatalogService {
  DriftCatalogService(
    db.AppDatabase database,
    ApprovalService approval, {
    IdGenerator idGenerator = const UlidIdGenerator(),
    this._clock = const SystemClock(),
  }) : _db = database,
       _approval = approval,
       _ids = idGenerator;

  final db.AppDatabase _db;
  final ApprovalService _approval;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<String>> createItem(ItemDraft draft) async {
    final result = await _submit(
      CreateItem(
        name: draft.name,
        unit: draft.unit,
        packSize: draft.packSize,
        category: draft.category,
        notes: draft.notes,
      ),
    );
    return result.fold(
      (receipt) => Ok(receipt.createdRecordIds.first),
      Err.new,
    );
  }

  @override
  Future<Result<void>> updateItem({
    required String itemId,
    required ItemDraft draft,
  }) async {
    final result = await _submit(
      UpdateItem(
        itemId: ItemId(itemId),
        name: draft.name,
        unit: draft.unit,
        packSize: draft.packSize,
        category: draft.category,
        notes: draft.notes,
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> setArchived({
    required String itemId,
    required bool archived,
  }) async {
    final result = await _submit(
      SetItemArchived(itemId: ItemId(itemId), archived: archived),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Stream<List<ItemSummary>> watchItems(ItemFilter filter) => _db
      .customSelect(
        'SELECT i.*, COALESCE(SUM(m.delta_micros), 0) AS on_hand '
        'FROM items i '
        'LEFT JOIN inventory_movements m ON m.item_id = i.id '
        'GROUP BY i.id '
        'ORDER BY (i.archived_at_micros IS NOT NULL), lower(i.name)',
        readsFrom: {_db.items, _db.inventoryMovements},
      )
      .watch()
      .map((rows) {
        final search = filter.search?.trim().toLowerCase();
        return [
          for (final row in rows)
            if (_matches(row, search, filter))
              ItemSummary(
                item: _toItem(row),
                onHandMicros: row.read<int>('on_hand'),
              ),
        ];
      });

  @override
  Stream<ItemDetail> watchItem(String itemId) => _db
      .customSelect(
        'SELECT i.*, COALESCE(SUM(m.delta_micros), 0) AS on_hand, '
        'COUNT(m.id) AS movement_count '
        'FROM items i '
        'LEFT JOIN inventory_movements m ON m.item_id = i.id '
        'WHERE i.id = ?1 GROUP BY i.id',
        variables: [Variable<String>(itemId)],
        readsFrom: {_db.items, _db.inventoryMovements},
      )
      .watchSingle()
      .map(
        (row) => ItemDetail(
          item: _toItem(row),
          onHandMicros: row.read<int>('on_hand'),
          hasMovements: row.read<int>('movement_count') > 0,
        ),
      );

  @override
  Future<List<String>> categorySuggestions() =>
      _db.itemDao.categorySuggestions();

  bool _matches(QueryRow row, String? search, ItemFilter filter) {
    if (!filter.includeArchived &&
        row.read<int?>('archived_at_micros') != null) {
      return false;
    }
    if (filter.category != null &&
        row.read<String?>('category') != filter.category) {
      return false;
    }
    if (search != null &&
        search.isNotEmpty &&
        !row.read<String>('name').toLowerCase().contains(search)) {
      return false;
    }
    return true;
  }

  Item _toItem(QueryRow row) => Item(
    id: ItemId(row.read<String>('id')),
    name: row.read<String>('name'),
    unit: ItemUnit.fromDb(row.read<String>('unit')),
    packSize: Quantity.fromMicros(row.read<int>('pack_size_micros')),
    category: row.read<String?>('category'),
    notes: row.read<String>('notes'),
    archivedAt: row.read<int?>('archived_at_micros') == null
        ? null
        : Instant(row.read<int>('archived_at_micros')),
    createdAt: Instant(row.read<int>('created_at_micros')),
    updatedAt: Instant(row.read<int>('updated_at_micros')),
  );

  Future<Result<CommandReceipt>> _submit(WorkspaceCommand command) =>
      _approval.submit(
        Proposal(
          commandId: CommandId(_ids.newId()),
          origin: ProposalOrigin.form,
          command: command,
          createdAt: _clock.now(),
        ),
      );
}
