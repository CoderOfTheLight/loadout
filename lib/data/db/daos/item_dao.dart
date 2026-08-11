import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'item_dao.g.dart';

/// Catalog reads. Mutation stays with the CommandApplier (design §6.4);
/// this DAO exposes none.
@DriftAccessor(tables: [Items])
class ItemDao extends DatabaseAccessor<AppDatabase> with _$ItemDaoMixin {
  ItemDao(super.db);

  Future<Item?> byId(String id) =>
      (select(items)..where((i) => i.id.equals(id))).getSingleOrNull();

  Stream<Item?> watchById(String id) =>
      (select(items)..where((i) => i.id.equals(id))).watchSingleOrNull();

  /// Every item, live first, then case-insensitively by name.
  Stream<List<Item>> watchAll() =>
      (select(items)..orderBy([
            (i) => OrderingTerm.asc(i.archivedAtMicros.isNotNull()),
            (i) => OrderingTerm.asc(i.name.lower()),
          ]))
          .watch();

  Future<List<Item>> byIds(Iterable<String> ids) =>
      (select(items)..where((i) => i.id.isIn(ids))).get();

  /// `SELECT DISTINCT category` over live items (design §6.5).
  Future<List<String>> categorySuggestions() async {
    final rows = await customSelect(
      'SELECT DISTINCT category AS category FROM items '
      'WHERE category IS NOT NULL AND archived_at_micros IS NULL '
      'ORDER BY category',
      readsFrom: {items},
    ).get();
    return [for (final row in rows) row.read<String>('category')];
  }
}
