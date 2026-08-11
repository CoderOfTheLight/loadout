import '../../../core/ids.dart';
import '../../../core/time.dart';
import 'ledger_math.dart';
import 'movement.dart';

/// Draft of a to-be-appended movement (design §6.3). `reversal` is NOT a
/// legal draft kind — reversals are only produced by [InventoryLedger
/// .reverseMovement] under a `CorrectMovement`/closeout-revision command.
final class MovementDraft {
  const MovementDraft({
    required this.itemId,
    required this.kind,
    required this.deltaMicros,
    this.eventId,
    this.occurredAt,
    this.note = '',
  });

  final ItemId itemId;
  final MovementKind kind;

  /// Signed; validator enforces sign-per-kind.
  final int deltaMicros;
  final EventId? eventId;

  /// null => recordedAt.
  final Instant? occurredAt;
  final String note;
}

/// The architecture seam over the append-only movements ledger (design §6.3).
abstract interface class InventoryLedger {
  // queries (open read path)
  Future<StockPosition> position(ItemId item, {Instant? asOf});
  Future<Map<ItemId, StockPosition>> positions({Instant? asOf});
  Future<List<Movement>> movements({
    ItemId? item,
    EventId? event,
    Instant? from,
    Instant? to,
  });
  Future<Movement?> movement(MovementId id);
  Stream<StockPosition> watchPosition(ItemId item);

  /// Max rowid; cheap recompute trigger.
  Stream<int> watchVersion();

  // writes: called ONLY by CommandApplier inside its transaction
  Future<Movement> appendMovement(
    MovementDraft draft, {
    required CommandId sourceCommandId,
    required Instant recordedAt,
  });
  Future<Movement> reverseMovement({
    required MovementId target,
    required String reason,
    required Instant occurredAt,
    required CommandId sourceCommandId,
    required Instant recordedAt,
  });
}
