import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'forecast_dao.g.dart';

/// One row of the §4.3 label query: the latest closeout revision's confirmed
/// outcome for one item at one closed event.
final class LabelQueryRow {
  const LabelQueryRow({
    required this.closeoutId,
    required this.eventId,
    required this.confirmedExposure,
    required this.depletionMicros,
    required this.stockout,
    required this.approximate,
  });

  final String closeoutId;
  final String eventId;
  final int confirmedExposure;
  final int depletionMicros;
  final bool stockout;
  final bool approximate;
}

/// Forecast-side reads. [labelHistory] is THE only label source (design §4.3):
/// it reads exclusively the latest closeout revision of closed events, and is
/// structurally unable to touch `forecast_*`, `events.planned_exposure`, or
/// drafts.
@DriftAccessor(
  tables: [
    ForecastSnapshots,
    ForecastLines,
    ForecastEvidence,
    ForecastOverrides,
    EventCloseouts,
    CloseoutLines,
    Events,
  ],
)
class ForecastDao extends DatabaseAccessor<AppDatabase>
    with _$ForecastDaoMixin {
  ForecastDao(super.db);

  /// The §4.3 forecast-history SQL, verbatim. Kept as a constant so tests can
  /// pin that no forecast table, prediction, or draft is ever referenced.
  static const labelQuerySql = '''
SELECT h.id AS closeout_id, h.event_id, h.confirmed_exposure,
       l.depletion_micros, l.stockout, l.approximate
FROM closeout_lines l
JOIN event_closeouts h ON h.id = l.closeout_id
JOIN events e ON e.id = h.event_id
WHERE l.item_id = ?1
  AND e.status = 'closed'
  AND h.revision = (SELECT MAX(h2.revision) FROM event_closeouts h2
                    WHERE h2.event_id = h.event_id)
ORDER BY e.scheduled_date DESC, e.id DESC
LIMIT ?2
''';

  /// Confirmed outcomes for [itemId], newest event first, at most
  /// [historyWindow] rows — the exact observations the frozen engine consumes.
  Future<List<LabelQueryRow>> labelHistory(
    String itemId, {
    required int historyWindow,
  }) async {
    final rows = await customSelect(
      labelQuerySql,
      variables: [Variable<String>(itemId), Variable<int>(historyWindow)],
      readsFrom: {closeoutLines, eventCloseouts, events},
    ).get();
    return [
      for (final row in rows)
        LabelQueryRow(
          closeoutId: row.read<String>('closeout_id'),
          eventId: row.read<String>('event_id'),
          confirmedExposure: row.read<int>('confirmed_exposure'),
          depletionMicros: row.read<int>('depletion_micros'),
          stockout: row.read<bool>('stockout'),
          approximate: row.read<bool>('approximate'),
        ),
    ];
  }
}
