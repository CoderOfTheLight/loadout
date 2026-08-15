import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'folder_dao.g.dart';

/// Folder reads. Mutation stays with the CommandApplier (design §6.4);
/// this DAO exposes none.
@DriftAccessor(tables: [Folders])
class FolderDao extends DatabaseAccessor<AppDatabase> with _$FolderDaoMixin {
  FolderDao(super.db);

  Future<Folder?> byId(String id) =>
      (select(folders)..where((f) => f.id.equals(id))).getSingleOrNull();

  /// Live folders in the owner's order (position, id as tiebreak).
  Future<List<Folder>> live() =>
      (select(folders)
            ..where((f) => f.archivedAtMicros.isNull())
            ..orderBy([
              (f) => OrderingTerm.asc(f.position),
              (f) => OrderingTerm.asc(f.id),
            ]))
          .get();

  Stream<List<Folder>> watchLive() =>
      (select(folders)
            ..where((f) => f.archivedAtMicros.isNull())
            ..orderBy([
              (f) => OrderingTerm.asc(f.position),
              (f) => OrderingTerm.asc(f.id),
            ]))
          .watch();
}
