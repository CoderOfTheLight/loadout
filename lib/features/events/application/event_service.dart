import '../../../core/ids.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../../../data/db/app_database.dart' as db;
import '../../approval/domain/approval_service.dart';
import '../../approval/domain/commands.dart';
import '../../approval/domain/proposal.dart';
import '../domain/event.dart';
import '../../../data/db/table_watch.dart';

/// List filter (design §9 EventListScreen: Upcoming / Active / Closed /
/// All). Upcoming = planned; cancelled events appear under All only.
enum EventStatusFilter { upcoming, active, closed, all }

final class EventSummary {
  const EventSummary({
    required this.id,
    required this.name,
    required this.scheduledDate,
    required this.status,
    this.plannedExposure,
    this.venue,
  });

  final String id;
  final String name;
  final String scheduledDate;
  final EventStatus status;
  final int? plannedExposure;
  final String? venue;
}

final class EventPlannedItem {
  const EventPlannedItem({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.position,
  });

  final String itemId;
  final String name;
  final ItemUnit unit;
  final int position;
}

final class EventDetail {
  const EventDetail({required this.event, required this.plannedItems});

  final Event event;
  final List<EventPlannedItem> plannedItems;
}

/// Screen-facing event surface (design §6.5). Events are mutable until
/// closed; closing happens only through CloseoutService.
abstract interface class EventService {
  /// Creates the event. The planned list is the draft's items PLUS the live
  /// items of every live `always_planned` folder (folder order, then name)
  /// that the draft did not already include — "the standing stuff is a
  /// review, not forty taps". The stored CreateEvent command carries the
  /// full final list, so the audit row says exactly what was planned.
  Future<Result<String>> createEvent(EventDraft draft);
  Future<Result<void>> updateEvent({
    required String eventId,
    required EventDraft draft,
  });
  Future<Result<void>> activate(String eventId);
  Future<Result<void>> cancel(String eventId, {required String reason});

  /// "Copy items from a previous event": [eventId]'s planned items that are
  /// still live, in position order — a prefill for the picker, not a write.
  Future<List<String>> clonePlannedItemsFrom(String eventId);
  Stream<List<EventSummary>> watchEvents({required EventStatusFilter filter});
  Stream<EventDetail> watchEvent(String eventId);
}

final class DriftEventService implements EventService {
  DriftEventService(
    db.AppDatabase database,
    ApprovalService approval, {
    IdGenerator idGenerator = const UlidIdGenerator(),
    this._clock = const SystemClock(),
  }) : _db = database,
       _approval = approval,
       _ids = idGenerator;

  final db.AppDatabase _db;
  final ApprovalService _approval;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<String>> createEvent(EventDraft draft) async {
    // Auto-add the always-planned folders' live items (folder position,
    // then name) after the owner's own picks. Composed HERE, before the
    // command is built, so the single write path stores the real list.
    final autoAdded = await _alwaysPlannedItemIds(
      excluding: draft.plannedItemIds.toSet(),
    );
    final result = await _submit(
      CreateEvent(
        name: draft.name,
        scheduledDate: draft.scheduledDate,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        plannedExposure: draft.plannedExposure,
        venue: draft.venue,
        notes: draft.notes,
        plannedItemIds: [
          for (final id in draft.plannedItemIds) ItemId(id),
          for (final id in autoAdded) ItemId(id),
        ],
      ),
    );
    return result.fold(
      (receipt) => Ok(receipt.createdRecordIds.first),
      Err.new,
    );
  }

  /// Live items of live always-planned folders, in folder order then
  /// case-insensitive name order, minus [excluding].
  Future<List<String>> _alwaysPlannedItemIds({
    required Set<String> excluding,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT i.id AS id FROM items i '
          'JOIN folders f ON f.id = i.folder_id '
          'WHERE f.always_planned = 1 '
          'AND f.archived_at_micros IS NULL '
          'AND i.archived_at_micros IS NULL '
          'ORDER BY f.position, lower(i.name), i.id',
          readsFrom: {_db.items, _db.folders},
        )
        .get();
    return [
      for (final row in rows)
        if (!excluding.contains(row.read<String>('id'))) row.read<String>('id'),
    ];
  }

  @override
  Future<List<String>> clonePlannedItemsFrom(String eventId) async {
    final planned = await _db.eventDao.plannedItems(eventId);
    final items = await _db.itemDao.byIds([for (final p in planned) p.itemId]);
    final live = {
      for (final item in items)
        if (item.archivedAtMicros == null) item.id,
    };
    return [
      for (final p in planned)
        if (live.contains(p.itemId)) p.itemId,
    ];
  }

  @override
  Future<Result<void>> updateEvent({
    required String eventId,
    required EventDraft draft,
  }) async {
    final result = await _submit(
      UpdateEvent(
        eventId: EventId(eventId),
        name: draft.name,
        scheduledDate: draft.scheduledDate,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        plannedExposure: draft.plannedExposure,
        venue: draft.venue,
        notes: draft.notes,
        plannedItemIds: [for (final id in draft.plannedItemIds) ItemId(id)],
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> activate(String eventId) async {
    final result = await _submit(ActivateEvent(EventId(eventId)));
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> cancel(String eventId, {required String reason}) async {
    final result = await _submit(
      CancelEvent(eventId: EventId(eventId), reason: reason),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Stream<List<EventSummary>> watchEvents({required EventStatusFilter filter}) =>
      _db.eventDao.watchAll().map(
        (rows) => [
          for (final row in rows)
            if (_matches(EventStatus.fromDb(row.status), filter))
              EventSummary(
                id: row.id,
                name: row.name,
                scheduledDate: row.scheduledDate,
                status: EventStatus.fromDb(row.status),
                plannedExposure: row.plannedExposure,
                venue: row.venue,
              ),
        ],
      );

  @override
  Stream<EventDetail> watchEvent(String eventId) => _db
      .watchTables('events.detail', {_db.events, _db.eventItems, _db.items})
      .asyncMap((_) => _loadDetail(eventId));

  Future<EventDetail> _loadDetail(String eventId) async {
    final row = await _db.eventDao.byId(eventId);
    if (row == null) {
      throw StateError('event does not exist');
    }
    final planned = await _db.eventDao.plannedItems(eventId);
    final items = await _db.itemDao.byIds([for (final p in planned) p.itemId]);
    final itemsById = {for (final item in items) item.id: item};
    return EventDetail(
      event: Event(
        id: EventId(row.id),
        name: row.name,
        venue: row.venue,
        scheduledDate: row.scheduledDate,
        startsAt: row.startsAtMicros == null
            ? null
            : Instant(row.startsAtMicros!),
        endsAt: row.endsAtMicros == null ? null : Instant(row.endsAtMicros!),
        status: EventStatus.fromDb(row.status),
        plannedExposure: row.plannedExposure,
        closedAt: row.closedAtMicros == null
            ? null
            : Instant(row.closedAtMicros!),
        notes: row.notes,
        plannedItemIds: [for (final p in planned) ItemId(p.itemId)],
      ),
      plannedItems: [
        for (final p in planned)
          if (itemsById[p.itemId] != null)
            EventPlannedItem(
              itemId: p.itemId,
              name: itemsById[p.itemId]!.name,
              unit: ItemUnit.fromDb(itemsById[p.itemId]!.unit),
              position: p.position,
            ),
      ],
    );
  }

  bool _matches(EventStatus status, EventStatusFilter filter) =>
      switch (filter) {
        EventStatusFilter.upcoming => status == EventStatus.planned,
        EventStatusFilter.active => status == EventStatus.active,
        EventStatusFilter.closed => status == EventStatus.closed,
        EventStatusFilter.all => true,
      };

  Future<Result<CommandReceipt>> _submit(WorkspaceCommand command) =>
      _approval.submit(
        Proposal(
          commandId: CommandId(_ids.newId()),
          origin: ProposalOrigin.form,
          command: command,
          createdAt: _clock.now(),
        ),
      );
}
