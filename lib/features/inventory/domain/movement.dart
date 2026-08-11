import '../../../core/ids.dart';
import '../../../core/time.dart';

/// Ledger movement kinds (design §5, normative). [dbValue] is the exact
/// string stored in `inventory_movements.kind` and CHECK-enforced there.
enum MovementKind {
  /// Purchase arrives. Sign +, written by forms, never event-linked.
  receive('receive'),

  /// Confirmed event depletion. Sign −, written ONLY by closeout
  /// application, `event_id` required.
  consume('consume'),

  /// Spoilage/damage. Sign −, written by forms and closeout application,
  /// event link optional.
  waste('waste'),

  /// Count reconciliation. Sign ±, computed by the service, never
  /// event-linked.
  adjust('adjust'),

  /// Exact negation of a prior row; copies the target's item and event.
  reversal('reversal');

  const MovementKind(this.dbValue);

  /// Stored/CHECK-enforced database value.
  final String dbValue;

  static MovementKind fromDb(String value) => values.firstWhere(
    (kind) => kind.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'not a movement kind'),
  );
}

/// Immutable ledger row (design §6.2).
final class Movement {
  const Movement({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.deltaMicros,
    this.eventId,
    this.reverses,
    required this.occurredAt,
    required this.recordedAt,
    required this.sourceCommandId,
    this.note = '',
  });

  final MovementId id;
  final ItemId itemId;
  final MovementKind kind;

  /// Signed micros; never zero.
  final int deltaMicros;
  final EventId? eventId;
  final MovementId? reverses;

  /// Business time (backdatable).
  final Instant occurredAt;

  /// Applier clock, monotonic.
  final Instant recordedAt;
  final CommandId sourceCommandId;
  final String note;
}
