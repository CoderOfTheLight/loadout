import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'command_dao.g.dart';

/// Commands audit table reads. Mutation stays with the CommandApplier
/// (design §6.4); this DAO exposes none.
@DriftAccessor(tables: [Commands])
class CommandDao extends DatabaseAccessor<AppDatabase> with _$CommandDaoMixin {
  CommandDao(super.db);

  Future<Command?> byId(String id) =>
      (select(commands)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Newest-first audit trail (ULIDs sort chronologically).
  Stream<List<Command>> watchRecent({int limit = 50}) =>
      (select(commands)
            ..orderBy([(c) => OrderingTerm.desc(c.id)])
            ..limit(limit))
          .watch();
}
