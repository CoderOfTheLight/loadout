import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'item_dao.g.dart';

/// Catalog reads. Mutation stays with the CommandApplier (design §6.4);
/// Gate 2 domain services add methods here.
@DriftAccessor(tables: [Items])
class ItemDao extends DatabaseAccessor<AppDatabase> with _$ItemDaoMixin {
  ItemDao(super.db);
}
