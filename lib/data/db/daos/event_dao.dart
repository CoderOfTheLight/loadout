import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'event_dao.g.dart';

/// Event reads. Mutation stays with the CommandApplier (design §6.4);
/// Gate 2 domain services add methods here.
@DriftAccessor(tables: [Events, EventItems])
class EventDao extends DatabaseAccessor<AppDatabase> with _$EventDaoMixin {
  EventDao(super.db);
}
