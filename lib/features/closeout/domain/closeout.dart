import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/time.dart';

/// Immutable confirmed-outcome header + lines (design §6.2, mirrors §4).
/// Current outcome for an event = MAX(revision); confirmed exposure here is
/// the ONLY exposure ever used as a forecasting label.
final class EventCloseout {
  const EventCloseout({
    required this.id,
    required this.eventId,
    required this.revision,
    this.supersedes,
    required this.confirmedExposure,
    this.note = '',
    required this.confirmedAt,
    required this.lines,
  });

  final CloseoutId id;
  final EventId eventId;
  final int revision;
  final CloseoutId? supersedes;
  final int confirmedExposure;
  final String note;
  final Instant confirmedAt;
  final List<CloseoutLine> lines;
}

/// One confirmed line. Depletion EXCLUDES waste: it is the demand label
/// ("what sells"), not "what left the van".
final class CloseoutLine {
  const CloseoutLine({
    required this.itemId,
    this.loaded,
    this.returned,
    this.waste,
    required this.depletion,
    this.stockout = false,
    this.approximate = false,
    this.consumptionMovementId,
    this.wasteMovementId,
  });

  final ItemId itemId;
  final Quantity? loaded;
  final Quantity? returned;
  final Quantity? waste;
  final Quantity depletion;
  final bool stockout;
  final bool approximate;

  /// Ledger rows written when this revision was applied (evidence links).
  final MovementId? consumptionMovementId;
  final MovementId? wasteMovementId;
}
