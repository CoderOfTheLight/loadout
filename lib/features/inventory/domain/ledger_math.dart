import '../../../core/quantity.dart';
import '../../../core/time.dart';
import 'movement.dart';

/// Derived stock position (design §6.3). On-hand is SIGNED and may
/// legitimately be negative; negative sums are surfaced, never clamped in
/// audit views.
final class StockPosition {
  const StockPosition({required this.onHandMicros});

  /// SIGNED micros.
  final int onHandMicros;

  bool get isNegative => onHandMicros < 0;

  /// Clamped display view.
  Quantity get onHand =>
      Quantity.fromMicros(onHandMicros < 0 ? 0 : onHandMicros);
}

/// Deterministic pure fold over movements (design §6.3).
final class LedgerMath {
  const LedgerMath._();

  /// Deterministic fold: movements sorted by
  /// `(occurredAt, recordedAt, id bytewise)` before summing `delta_micros`;
  /// [asOf] is INCLUSIVE on `occurredAt`. A reversal takes effect at ITS OWN
  /// `occurredAt`.
  static StockPosition position(Iterable<Movement> movements, {Instant? asOf}) {
    final sorted = movements.toList()
      ..sort((a, b) {
        final byOccurred = a.occurredAt.epochMicrosUtc.compareTo(
          b.occurredAt.epochMicrosUtc,
        );
        if (byOccurred != 0) return byOccurred;
        final byRecorded = a.recordedAt.epochMicrosUtc.compareTo(
          b.recordedAt.epochMicrosUtc,
        );
        if (byRecorded != 0) return byRecorded;
        return (a.id as String).compareTo(b.id as String);
      });
    var sum = 0;
    for (final movement in sorted) {
      if (asOf != null &&
          movement.occurredAt.epochMicrosUtc > asOf.epochMicrosUtc) {
        continue;
      }
      sum += movement.deltaMicros;
    }
    return StockPosition(onHandMicros: sum);
  }
}
