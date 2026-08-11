import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'command_dao.g.dart';

/// Commands audit table access. Mutation stays with the CommandApplier
/// (design §6.4); Gate 2 domain services add methods here.
@DriftAccessor(tables: [Commands])
class CommandDao extends DatabaseAccessor<AppDatabase> with _$CommandDaoMixin {
  CommandDao(super.db);
}
