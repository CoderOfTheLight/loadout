import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'event_dao.g.dart';

/// Event reads. Mutation stays with the CommandApplier (design §6.4);
/// this DAO exposes none.
@DriftAccessor(tables: [Events, EventItems])
class EventDao extends DatabaseAccessor<AppDatabase> with _$EventDaoMixin {
  EventDao(super.db);

  Future<Event?> byId(String id) =>
      (select(events)..where((e) => e.id.equals(id))).getSingleOrNull();

  Stream<Event?> watchById(String id) =>
      (select(events)..where((e) => e.id.equals(id))).watchSingleOrNull();

  /// Every event, soonest scheduled date first, id as tiebreak.
  Stream<List<Event>> watchAll() =>
      (select(events)..orderBy([
            (e) => OrderingTerm.asc(e.scheduledDate),
            (e) => OrderingTerm.asc(e.id),
          ]))
          .watch();

  /// Planned items in position order.
  Future<List<EventItem>> plannedItems(String eventId) =>
      (select(eventItems)
            ..where((e) => e.eventId.equals(eventId))
            ..orderBy([(e) => OrderingTerm.asc(e.position)]))
          .get();

  Stream<List<EventItem>> watchPlannedItems(String eventId) =>
      (select(eventItems)
            ..where((e) => e.eventId.equals(eventId))
            ..orderBy([(e) => OrderingTerm.asc(e.position)]))
          .watch();
}
