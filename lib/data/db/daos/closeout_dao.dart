import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'closeout_dao.g.dart';

/// Closeout header/line/draft access. Record mutation stays with the
/// CommandApplier (design §6.4) — except `closeout_drafts` autosave
/// upserts/deletes, an explicit §6.4 exception owned by CloseoutService and
/// exposed here. A draft is not a record; append-only does not apply to it.
@DriftAccessor(tables: [EventCloseouts, CloseoutLines, CloseoutDrafts])
class CloseoutDao extends DatabaseAccessor<AppDatabase>
    with _$CloseoutDaoMixin {
  CloseoutDao(super.db);

  /// Latest revision header for [eventId] (current outcome), or null.
  Future<EventCloseout?> latestHeaderForEvent(String eventId) =>
      (select(eventCloseouts)
            ..where((c) => c.eventId.equals(eventId))
            ..orderBy([(c) => OrderingTerm.desc(c.revision)])
            ..limit(1))
          .getSingleOrNull();

  /// Every revision header for [eventId], newest revision first.
  Stream<List<EventCloseout>> watchHeadersForEvent(String eventId) =>
      (select(eventCloseouts)
            ..where((c) => c.eventId.equals(eventId))
            ..orderBy([(c) => OrderingTerm.desc(c.revision)]))
          .watch();

  /// Lines for one header, in item-id order (deterministic).
  Future<List<CloseoutLine>> linesFor(String closeoutId) =>
      (select(closeoutLines)
            ..where((l) => l.closeoutId.equals(closeoutId))
            ..orderBy([(l) => OrderingTerm.asc(l.itemId)]))
          .get();

  // ------------------------------------------------ drafts (§6.4 exception)

  Future<CloseoutDraft?> draftFor(String eventId) => (select(
    closeoutDrafts,
  )..where((d) => d.eventId.equals(eventId))).getSingleOrNull();

  Future<void> upsertDraft({
    required String eventId,
    required String payloadJson,
    required int updatedAtMicros,
  }) => into(closeoutDrafts).insertOnConflictUpdate(
    CloseoutDraftsCompanion.insert(
      eventId: eventId,
      payloadJson: payloadJson,
      updatedAtMicros: updatedAtMicros,
    ),
  );

  Future<void> deleteDraft(String eventId) =>
      (delete(closeoutDrafts)..where((d) => d.eventId.equals(eventId))).go();
}
