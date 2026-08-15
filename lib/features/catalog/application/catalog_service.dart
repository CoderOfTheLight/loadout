import 'package:drift/drift.dart';

import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../core/unit_ratio.dart';
import '../../../core/units.dart';
import '../../../data/db/app_database.dart' as db;
import '../../../data/db/table_watch.dart';
import '../../approval/domain/approval_service.dart';
import '../../approval/domain/commands.dart';
import '../../approval/domain/proposal.dart';
import '../domain/demand_basis.dart';
import '../domain/folder.dart';
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

/// One section of a folder-ordered list: the folder (or null for the
/// "Unfiled" section, always last) and its live items, case-insensitively
/// by name.
final class FolderWithItems {
  const FolderWithItems({this.folder, required this.items});

  /// Null = the Unfiled section — items whose `folder_id` is NULL. Present
  /// only when it has items; unfiled items are never hidden.
  final Folder? folder;
  final List<ItemSummary> items;

  bool get isUnfiled => folder == null;
}

/// Screen-facing catalog surface (design §6.5). Master data updates are
/// plain in-place updates through the command path; no revision log in v1.
abstract interface class CatalogService {
  /// Creates the item and, when [openingCount] is greater than zero, its
  /// opening `adjust` movement — ONE command, ONE transaction, so the new
  /// item can never exist without the count the owner just typed. Returns
  /// the created itemId.
  Future<Result<String>> createItem(
    ItemDraft draft, {
    Quantity openingCount = Quantity.zero,
  });

  /// Applies the whole draft. A null `draft.servesPerUnit` CLEARS the stored
  /// value — the form always submits its complete state.
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

  // ------------------------------------------------------------- folders
  // The short managed list every screen sections by. All writes go through
  // the command path; renames can never orphan items (FK, not text) and
  // archiving moves a folder's items to Unfiled in the same transaction.

  /// Creates a folder at the end of the owner's order. Returns the folderId.
  Future<Result<String>> createFolder({
    required String name,
    required DemandBasis demandBasis,
    bool alwaysPlanned = false,
  });

  Future<Result<void>> renameFolder({
    required String folderId,
    required String name,
  });

  /// [orderedFolderIds] must list every live folder exactly once — the new
  /// positions are the list indices.
  Future<Result<void>> reorderFolders(List<String> orderedFolderIds);

  /// Archives the folder and moves its items to Unfiled. One-way; nothing
  /// is deleted.
  Future<Result<void>> archiveFolder(String folderId);

  /// Updates the folder's answer to the one question and/or its
  /// always-planned flag; at least one must be given.
  Future<Result<void>> setFolderBasis({
    required String folderId,
    DemandBasis? demandBasis,
    bool? alwaysPlanned,
  });

  /// Null [folderId] = move to Unfiled.
  Future<Result<void>> moveItemToFolder({
    required String itemId,
    String? folderId,
  });

  /// Batch move for the tidy-up screen; null [folderId] = Unfiled.
  Future<Result<void>> moveItemsToFolder({
    required List<String> itemIds,
    String? folderId,
  });

  /// Live folders in the owner's order (position, id tiebreak).
  Stream<List<Folder>> watchFolders();

  /// The sectioned catalog: live folders in order, each with its live items
  /// (case-insensitively by name), then an Unfiled section when any item has
  /// no folder. Empty folders are included — the owner must see where things
  /// can go.
  Stream<List<FolderWithItems>> watchFoldersWithItems();
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
  Future<Result<String>> createItem(
    ItemDraft draft, {
    Quantity openingCount = Quantity.zero,
  }) async {
    final result = await _submit(
      CreateItem(
        name: draft.name,
        unit: draft.unit,
        packSize: draft.packSize,
        servesPerUnit: draft.servesPerUnit,
        perPersonRatio: draft.perPersonRatio,
        folderId: draft.folderId == null ? null : FolderId(draft.folderId!),
        demandBasis: draft.demandBasis,
        perEventBaseline: draft.perEventBaseline,
        openingCount: openingCount.micros == 0 ? null : openingCount,
        category: draft.category,
        notes: draft.notes,
      ),
    );
    // createdRecordIds is [itemId] or [itemId, openingMovementId].
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
    // The form always submits its complete state: every null draft field
    // CLEARS the stored value, exactly as servesPerUnit always has.
    final result = await _submit(
      UpdateItem(
        itemId: ItemId(itemId),
        name: draft.name,
        unit: draft.unit,
        packSize: draft.packSize,
        servesPerUnit: draft.servesPerUnit,
        clearServesPerUnit: draft.servesPerUnit == null,
        perPersonRatio: draft.perPersonRatio,
        clearPerPersonRatio: draft.perPersonRatio == null,
        folderId: draft.folderId == null ? null : FolderId(draft.folderId!),
        clearFolder: draft.folderId == null,
        demandBasis: draft.demandBasis,
        clearDemandBasis: draft.demandBasis == null,
        perEventBaseline: draft.perEventBaseline,
        clearPerEventBaseline: draft.perEventBaseline == null,
        category: draft.category,
        notes: draft.notes,
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  // ------------------------------------------------------------- folders

  @override
  Future<Result<String>> createFolder({
    required String name,
    required DemandBasis demandBasis,
    bool alwaysPlanned = false,
  }) async {
    final result = await _submit(
      CreateFolder(
        name: name,
        demandBasis: demandBasis,
        alwaysPlanned: alwaysPlanned,
      ),
    );
    return result.fold(
      (receipt) => Ok(receipt.createdRecordIds.first),
      Err.new,
    );
  }

  @override
  Future<Result<void>> renameFolder({
    required String folderId,
    required String name,
  }) async {
    final result = await _submit(
      RenameFolder(folderId: FolderId(folderId), name: name),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> reorderFolders(List<String> orderedFolderIds) async {
    final result = await _submit(
      ReorderFolders([for (final id in orderedFolderIds) FolderId(id)]),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> archiveFolder(String folderId) async {
    final result = await _submit(ArchiveFolder(FolderId(folderId)));
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> setFolderBasis({
    required String folderId,
    DemandBasis? demandBasis,
    bool? alwaysPlanned,
  }) async {
    final result = await _submit(
      SetFolderBasis(
        folderId: FolderId(folderId),
        demandBasis: demandBasis,
        alwaysPlanned: alwaysPlanned,
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> moveItemToFolder({
    required String itemId,
    String? folderId,
  }) async {
    final result = await _submit(
      MoveItemToFolder(
        itemId: ItemId(itemId),
        folderId: folderId == null ? null : FolderId(folderId),
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> moveItemsToFolder({
    required List<String> itemIds,
    String? folderId,
  }) async {
    final result = await _submit(
      MoveItemsToFolder(
        itemIds: [for (final id in itemIds) ItemId(id)],
        folderId: folderId == null ? null : FolderId(folderId),
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Stream<List<Folder>> watchFolders() => _db.folderDao.watchLive().map(
    (rows) => [for (final row in rows) _toFolder(row)],
  );

  @override
  Stream<List<FolderWithItems>> watchFoldersWithItems() => _db
      .watchTables('catalog.foldersWithItems', {
        _db.folders,
        _db.items,
        _db.inventoryMovements,
      })
      .asyncMap((_) async {
        final folders = await _db.folderDao.live();
        final rows = await _db
            .customSelect(
              'SELECT i.*, COALESCE(SUM(m.delta_micros), 0) AS on_hand '
              'FROM items i '
              'LEFT JOIN inventory_movements m ON m.item_id = i.id '
              'WHERE i.archived_at_micros IS NULL '
              'GROUP BY i.id '
              'ORDER BY lower(i.name), i.id',
              readsFrom: {_db.items, _db.inventoryMovements},
            )
            .get();
        final byFolder = <String?, List<ItemSummary>>{};
        for (final row in rows) {
          byFolder
              .putIfAbsent(row.read<String?>('folder_id'), () => [])
              .add(
                ItemSummary(
                  item: _toItem(row),
                  onHandMicros: row.read<int>('on_hand'),
                ),
              );
        }
        return [
          for (final folder in folders)
            FolderWithItems(
              folder: _toFolder(folder),
              items: byFolder[folder.id] ?? const [],
            ),
          if (byFolder[null] case final unfiled?)
            FolderWithItems(folder: null, items: unfiled),
        ];
      });

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
    servesPerUnit: switch (row.read<int?>('serves_per_unit_micros')) {
      final micros? => Quantity.fromMicros(micros),
      null => null,
    },
    perPersonRatio: switch ((
      row.read<int?>('per_person_numerator'),
      row.read<int?>('per_person_denominator'),
    )) {
      (final numerator?, final denominator?) => UnitRatio(
        numerator,
        denominator,
      ),
      _ => null,
    },
    folderId: switch (row.read<String?>('folder_id')) {
      final id? => FolderId(id),
      null => null,
    },
    demandBasis: DemandBasis.fromDbNullable(row.read<String?>('demand_basis')),
    perEventBaseline: switch (row.read<int?>('per_event_baseline_micros')) {
      final micros? => Quantity.fromMicros(micros),
      null => null,
    },
    category: row.read<String?>('category'),
    notes: row.read<String>('notes'),
    archivedAt: row.read<int?>('archived_at_micros') == null
        ? null
        : Instant(row.read<int>('archived_at_micros')),
    createdAt: Instant(row.read<int>('created_at_micros')),
    updatedAt: Instant(row.read<int>('updated_at_micros')),
  );

  Folder _toFolder(db.Folder row) => Folder(
    id: FolderId(row.id),
    name: row.name,
    position: row.position,
    demandBasis: DemandBasis.fromDb(row.demandBasis),
    alwaysPlanned: row.alwaysPlanned,
    archivedAt: row.archivedAtMicros == null
        ? null
        : Instant(row.archivedAtMicros!),
    createdAt: Instant(row.createdAtMicros),
    updatedAt: Instant(row.updatedAtMicros),
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
