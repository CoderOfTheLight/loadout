import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'ledger_dao.g.dart';

/// Read-side queries over the append-only movements ledger. On-hand is always
/// derived — `SUM(delta_micros)` — never a stored stock column (design §4.3).
/// Writes stay with the CommandApplier (§6.4); this DAO exposes none.
@DriftAccessor(tables: [InventoryMovements])
class LedgerDao extends DatabaseAccessor<AppDatabase> with _$LedgerDaoMixin {
  LedgerDao(super.db);

  /// Derived on-hand for one item, in signed micros. Zero for an unknown or
  /// movement-less item; negative sums are legal and surfaced upstream.
  Future<int> onHandMicros(String itemId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(delta_micros), 0) AS on_hand_micros '
      'FROM inventory_movements WHERE item_id = ?1',
      variables: [Variable<String>(itemId)],
      readsFrom: {inventoryMovements},
    ).getSingle();
    return row.read<int>('on_hand_micros');
  }

  /// Derived on-hand for every item that has at least one movement.
  Future<Map<String, int>> onHandByItem() async {
    final rows = await customSelect(
      'SELECT item_id, SUM(delta_micros) AS on_hand_micros '
      'FROM inventory_movements GROUP BY item_id',
      readsFrom: {inventoryMovements},
    ).get();
    return {
      for (final row in rows)
        row.read<String>('item_id'): row.read<int>('on_hand_micros'),
    };
  }
}
