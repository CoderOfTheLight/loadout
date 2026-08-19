/// What an event is going to cost — the two honest answers, kept apart.
///
/// The owner asks the question two ways, and they deserve different maths:
///
///  * **What am I about to spend?** — the packing list she is building right
///    now, priced at today's prices. Arithmetic, not prediction: sum the
///    planned quantities × each item's current price. [PlannedCost].
///  * **What do events like this usually cost?** — read off CONFIRMED
///    closeouts only, the same evidence rule the forecast engine lives by
///    (§4.3: confirmed outcomes are the only history). Each past event's
///    spend is what it actually used × the price recorded the day it was
///    closed out, divided by the people it actually served; the median of
///    those per-person figures, scaled to this event's expected attendance.
///    [EventCostPrediction].
///
/// Neither number ever enters the frozen forecast engine: price arithmetic
/// happens here, on quantities the engine produced. Money is integer cents
/// throughout ([Money]); the only division is per-person, and it rounds
/// half-up once, at the end.
///
/// Honesty rules, because a cost the owner cannot trust is worse than no
/// cost at all:
///  * An item with no price contributes nothing and is COUNTED and reported
///    ([unpricedItemCount]) — a cheaper-looking total is a lie.
///  * A past event with no priced lines at all is not evidence; it is
///    excluded, not treated as zero.
///  * With no evidence, the prediction is absent — never a zero, never a
///    guess dressed as a number.
library;

import '../../../core/money.dart';

/// The packing list priced at today's prices — plain arithmetic over the
/// items currently planned for one event.
final class PlannedCost {
  const PlannedCost({
    required this.total,
    required this.pricedItemCount,
    required this.unpricedItemCount,
  });

  /// Σ (planned quantity × current unit price) over priced items.
  final Money total;

  /// How many planned items carried a price (drove [total]).
  final int pricedItemCount;

  /// How many planned items were left OUT of [total] — no price, or no
  /// planned quantity yet to price (`event_items` stores no quantity, so a
  /// forecast is the only source of one). Either way the item is said out
  /// loud wherever the total is shown: a cheaper-looking total is a lie
  /// whichever half is missing.
  final int unpricedItemCount;

  /// True when nothing on the list is priced: show no total at all.
  bool get isEmpty => pricedItemCount == 0;

  /// True when the total is real but incomplete.
  bool get isPartial => pricedItemCount > 0 && unpricedItemCount > 0;
}

/// One past event's confirmed spend — the unit of evidence behind
/// [EventCostPrediction].
final class EventCostEvidence {
  const EventCostEvidence({
    required this.eventId,
    required this.eventName,
    required this.total,
    required this.confirmedExposure,
    required this.unpricedLineCount,
  });

  final String eventId;
  final String eventName;

  /// Σ (confirmed depletion × the price snapshotted at closeout).
  final Money total;

  /// The people this event actually served (closeout header, never the
  /// planned estimate).
  final int confirmedExposure;

  /// Closeout lines that carried no price — [total] excludes them.
  final int unpricedLineCount;

  /// Cost per person in cents, rounded half-up. [confirmedExposure] is
  /// CHECK-constrained positive, so this never divides by zero.
  int get perPersonCents =>
      (total.cents * 2 + confirmedExposure) ~/ (confirmedExposure * 2);
}

/// What events like this one usually cost, from confirmed history alone.
final class EventCostPrediction {
  const EventCostPrediction({
    required this.perPerson,
    required this.total,
    required this.evidence,
    required this.exposure,
  });

  /// Median per-person spend across [evidence].
  final Money perPerson;

  /// [perPerson] × [exposure] — what this event should cost at that rate.
  final Money total;

  /// The confirmed events this reads from, newest first. Never empty: with
  /// no evidence there is no prediction object at all.
  final List<EventCostEvidence> evidence;

  /// The attendance this was scaled to (the event's planned exposure).
  final int exposure;

  /// One event is a data point, not a pattern — surfaces say so.
  bool get isThin => evidence.length < 3;

  /// True when any evidence event had unpriced lines, so the rate — and
  /// therefore the prediction — understates reality.
  bool get understates => evidence.any((event) => event.unpricedLineCount > 0);
}
