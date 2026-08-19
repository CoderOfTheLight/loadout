/// The two cost answers of `domain/event_cost.dart`, computed over live
/// workspace state: what this event is about to cost, and what events like
/// it usually cost.
///
/// Price arithmetic lives HERE and only here. The frozen forecast engine
/// produces quantities; this multiplies them by money, in integer cents
/// ([Money]), never a double. Nothing in this file writes: every figure is
/// derived, and every watch goes through [TableWatch.watchTables] with its
/// own unique label, because drift caches query streams by statement text
/// plus variables — NOT by `readsFrom`.
library;

import 'package:drift/drift.dart' show Variable;

import '../../../core/money.dart';
import '../../../data/db/app_database.dart' as db;
import '../../../data/db/table_watch.dart';
import '../../settings/application/settings_service.dart';
import '../domain/event_cost.dart';
import '../domain/forecast_engine.dart';
import '../domain/snapshot.dart';
import 'forecast_service.dart';

/// Screen-facing cost surface. Both answers are watchable and keyed by
/// event id, so a list that gains or loses an item re-costs itself.
abstract interface class EventCostService {
  /// What the owner is about to spend on [eventId], at today's prices.
  ///
  /// THE planned-quantity rule, in priority order:
  ///
  ///  1. the latest forecast snapshot's EFFECTIVE load for the item — the
  ///     override-winning figure the forecast screen shows and its cost
  ///     caption multiplies ([ForecastLineView.effectiveLoadMicros]: a live
  ///     override, else the engine's load, else the cold-start baseline's);
  ///  2. nothing else. `event_items` is (event, item, position): the schema
  ///     carries NO per-event planned quantity, so there is no second
  ///     source to fall back to and none is invented.
  ///
  /// A planned item with no quantity is therefore UNCOUNTED exactly as an
  /// item with no price is: it contributes nothing to [PlannedCost.total]
  /// and increments [PlannedCost.unpricedItemCount], so a total that leaves
  /// something out is visibly incomplete rather than quietly short. Before
  /// any forecast exists no item has a planned quantity at all, so
  /// `pricedItemCount` is 0, [PlannedCost.isEmpty] is true, and the surface
  /// shows no total — the honest answer to "what will this cost?" when
  /// nothing has been planned yet.
  Stream<PlannedCost> watchPlannedCost(String eventId);

  /// One-shot [watchPlannedCost].
  Future<PlannedCost> plannedCost(String eventId);

  /// What events like [eventId] usually cost, or null when nothing
  /// confirmed backs the question — never a zero.
  ///
  /// Evidence is CONFIRMED closeouts only, the §4.3 rule: the LATEST
  /// revision of each CLOSED event, priced with the cents SNAPSHOTTED on
  /// each closeout line (`closeout_lines.unit_price_cents`) rather than
  /// today's catalog price, over the CONFIRMED exposure from the closeout
  /// header rather than the planned estimate. Plans, baselines, overrides
  /// and forecast snapshots are as unreachable from here as they are from
  /// the §4.3 label query.
  Stream<EventCostPrediction?> watchCostPrediction(String eventId);

  /// One-shot [watchCostPrediction].
  Future<EventCostPrediction?> costPrediction(String eventId);
}

final class DriftEventCostService implements EventCostService {
  DriftEventCostService(
    db.AppDatabase database,
    ForecastService forecast,
    DriftSettingsService settings,
  ) : _db = database,
      _forecast = forecast,
      _settings = settings;

  final db.AppDatabase _db;
  final ForecastService _forecast;
  final DriftSettingsService _settings;

  // -------------------------------------------------------- planned cost

  @override
  Stream<PlannedCost> watchPlannedCost(String eventId) => _db
      .watchTables('cost.plannedCost', {
        // The list itself, so adding or removing an item re-costs live.
        _db.eventItems,
        // Prices are master data: an edit moves this total immediately.
        _db.items,
        // The quantities: a regenerated snapshot or a new override moves it
        // too — the caption and this total must never disagree.
        _db.forecastSnapshots,
        _db.forecastLines,
        _db.forecastOverrides,
      })
      .asyncMap((_) => plannedCost(eventId));

  @override
  Future<PlannedCost> plannedCost(String eventId) async {
    final planned = await _db.eventDao.plannedItems(eventId);
    if (planned.isEmpty) return _emptyPlannedCost;
    // The snapshot is read whole (never `.first` on the watch stream — that
    // would open a second subscription inside an asyncMap) so the load used
    // here is byte-identical to the one the forecast screen shows.
    final snapshot = await _forecast.latestSnapshot(eventId);
    final loadByItem = <String, int?>{
      for (final line in snapshot?.lines ?? const <ForecastLineView>[])
        line.itemId as String: line.effectiveLoadMicros,
    };
    final priceByItem = <String, int?>{
      for (final item in await _db.itemDao.byIds([
        for (final row in planned) row.itemId,
      ]))
        item.id: item.unitPriceCents,
    };
    var total = Money.zero;
    var priced = 0;
    var unpriced = 0;
    for (final row in planned) {
      final cents = priceByItem[row.itemId];
      final loadMicros = loadByItem[row.itemId];
      // No price, or no planned quantity to price: counted out loud, worth
      // nothing to the total. A load of exactly zero is a real answer — the
      // plan needs none of this item — and stays a priced, counted line.
      if (cents == null || loadMicros == null) {
        unpriced++;
        continue;
      }
      total = total.plus(
        Money.fromCents(cents).timesQuantityMicros(loadMicros),
      );
      priced++;
    }
    return PlannedCost(
      total: total,
      pricedItemCount: priced,
      unpricedItemCount: unpriced,
    );
  }

  static const _emptyPlannedCost = PlannedCost(
    total: Money.zero,
    pricedItemCount: 0,
    unpricedItemCount: 0,
  );

  // ----------------------------------------------------------- prediction

  @override
  Stream<EventCostPrediction?> watchCostPrediction(String eventId) => _db
      .watchTables('cost.prediction', {
        // The target event's planned exposure scales the answer; every
        // other event's status decides whether it is evidence at all.
        _db.events,
        _db.eventCloseouts,
        _db.closeoutLines,
        // The history window is a workspace preference.
        _db.settings,
      })
      .asyncMap((_) => costPrediction(eventId));

  @override
  Future<EventCostPrediction?> costPrediction(String eventId) async {
    final event = await _db.eventDao.byId(eventId);
    // No event, or no attendance to scale to: there is nothing to predict.
    // A rate with no exposure is not a total, and a total is what was asked
    // for — so the answer is absent, not zero.
    final exposure = event?.plannedExposure;
    if (exposure == null) return null;
    final evidence = await _confirmedEvidence();
    if (evidence.isEmpty) return null;
    final perPerson = Money.fromCents(
      medianCents([for (final past in evidence) past.perPersonCents]),
    );
    return EventCostPrediction(
      perPerson: perPerson,
      total: perPerson.times(exposure),
      evidence: List.unmodifiable(evidence),
      exposure: exposure,
    );
  }

  /// The §4.3-shaped evidence query for MONEY: one row per closed event,
  /// its latest revision only, newest first, and only where that revision
  /// priced something.
  ///
  /// The `EXISTS` clause is the "not evidence, not zero" rule in SQL: an
  /// event whose confirmed lines carry no price at all says nothing about
  /// what an event costs, so it is excluded here rather than counted as a
  /// free event — and, like the label query, it never spends one of the
  /// history window's slots.
  static const evidenceSql = '''
SELECT h.id AS closeout_id, h.event_id AS event_id, e.name AS event_name,
       h.confirmed_exposure AS confirmed_exposure
FROM event_closeouts h
JOIN events e ON e.id = h.event_id
WHERE e.status = 'closed'
  AND h.revision = (SELECT MAX(h2.revision) FROM event_closeouts h2
                    WHERE h2.event_id = h.event_id)
  AND EXISTS (SELECT 1 FROM closeout_lines l
              WHERE l.closeout_id = h.id AND l.unit_price_cents IS NOT NULL)
ORDER BY e.scheduled_date DESC, e.id DESC
LIMIT ?1
''';

  /// Confirmed spend per past event, newest first, bounded by the
  /// workspace's history window — the same last-N setting the forecast
  /// service passes to the §4.3 label query, read the same way, so "how far
  /// back do you look?" has one answer across the app.
  Future<List<EventCostEvidence>> _confirmedEvidence() async {
    final rows = await _db
        .customSelect(
          evidenceSql,
          variables: [Variable<int>(await _settings.historyWindow())],
          readsFrom: {_db.eventCloseouts, _db.closeoutLines, _db.events},
        )
        .get();
    final evidence = <EventCostEvidence>[];
    for (final row in rows) {
      final lines = await _db.closeoutDao.linesFor(
        row.read<String>('closeout_id'),
      );
      var total = Money.zero;
      var unpricedLines = 0;
      for (final line in lines) {
        final cents = line.unitPriceCents;
        if (cents == null) {
          unpricedLines++;
          continue;
        }
        total = total.plus(
          Money.fromCents(cents).timesQuantityMicros(line.depletionMicros),
        );
      }
      evidence.add(
        EventCostEvidence(
          eventId: row.read<String>('event_id'),
          eventName: row.read<String>('event_name'),
          total: total,
          confirmedExposure: row.read<int>('confirmed_exposure'),
          unpricedLineCount: unpricedLines,
        ),
      );
    }
    return evidence;
  }
}

/// The app's median, in cents — the frozen engine's convention, matched
/// exactly ([DeterministicForecastEngine.forecastDirect]): sort ascending,
/// an odd count takes the middle value, an EVEN count takes the TRUNCATING
/// integer mean of the two middle values.
///
/// Integer-only and order-independent, because nothing forecasting-adjacent
/// in this app is allowed to be nondeterministic: the same inputs must give
/// the same cents, on every device, forever. [values] must not be empty —
/// callers check for evidence first, since "no evidence" is a missing
/// prediction, not a median of nothing.
int medianCents(List<int> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) ~/ 2;
}
