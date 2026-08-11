import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'closeout_dao.g.dart';

/// Closeout header/line/draft reads. Mutation stays with the CommandApplier
/// (design §6.4) — except `closeout_drafts` autosave upserts, which the
/// CloseoutService owns (§6.4). Gate 2 domain services add methods here.
@DriftAccessor(tables: [EventCloseouts, CloseoutLines, CloseoutDrafts])
class CloseoutDao extends DatabaseAccessor<AppDatabase>
    with _$CloseoutDaoMixin {
  CloseoutDao(super.db);
}
