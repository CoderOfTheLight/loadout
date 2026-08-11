import '../../../core/ids.dart';
import '../../../core/time.dart';

/// Event lifecycle (design §4 `events.status`).
enum EventStatus {
  planned('planned'),
  active('active'),
  closed('closed'),
  cancelled('cancelled');

  const EventStatus(this.dbValue);

  /// Stored/CHECK-enforced database value.
  final String dbValue;

  static EventStatus fromDb(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'not an event status'),
  );
}

/// Immutable event view (design §6.2). Mutable until closed;
/// [plannedExposure] is a PREDICTION and never a label.
final class Event {
  const Event({
    required this.id,
    required this.name,
    this.venue,
    required this.scheduledDate,
    this.startsAt,
    this.endsAt,
    required this.status,
    this.plannedExposure,
    this.closedAt,
    this.notes,
    this.plannedItemIds = const [],
  });

  final EventId id;
  final String name;
  final String? venue;

  /// 'YYYY-MM-DD' in the owner's local calendar.
  final String scheduledDate;
  final Instant? startsAt;
  final Instant? endsAt;
  final EventStatus status;
  final int? plannedExposure;
  final Instant? closedAt;
  final String? notes;

  /// Planned items in `event_items.position` order.
  final List<ItemId> plannedItemIds;
}

/// Screen-facing event form draft (design §6.5).
final class EventDraft {
  const EventDraft({
    required this.name,
    required this.scheduledDate,
    this.startsAt,
    this.endsAt,
    this.plannedExposure,
    this.venue,
    this.notes,
    this.plannedItemIds = const [],
  });

  final String name;

  /// 'YYYY-MM-DD'.
  final String scheduledDate;
  final Instant? startsAt;
  final Instant? endsAt;
  final int? plannedExposure;
  final String? venue;
  final String? notes;
  final List<String> plannedItemIds;
}
