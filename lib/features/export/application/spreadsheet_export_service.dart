/// The four CSV documents, built from live workspace state.
///
/// Read-only, top to bottom: nothing here writes, and nothing here logs. The
/// file the owner saves is her own data leaving by her own hand, which is
/// exactly what the feature is for — but two things never leave with it:
///
///  * **Internal ids.** No ULID is ever a column. The count export keys its
///    rows by ITEM NAME, because that is what the person reading the file
///    knows the item by.
///  * **Barcode payloads.** The items export says whether an item has a
///    barcode, never what it is.
///
/// Honesty rule, everywhere: an unknown value is an EMPTY cell. A zero would
/// say "free" where the truth is "no price recorded", and a treasurer
/// summing that column would get a number the owner cannot defend.
library;

import '../../../data/db/app_database.dart' as db;
import '../../forecasting/application/event_cost_service.dart';
import '../../forecasting/application/forecast_service.dart';
import '../domain/csv_cells.dart';
import '../domain/csv_writer.dart';

/// One event that has been counted — the picker's row for the count export.
final class CountedEvent {
  const CountedEvent({
    required this.id,
    required this.name,
    required this.scheduledDate,
  });

  final String id;
  final String name;

  /// `YYYY-MM-DD`, straight from the event.
  final String scheduledDate;
}

abstract interface class SpreadsheetExportService {
  /// Every item, live and archived, folder by folder.
  Future<String> itemsCsv();

  /// Every event, newest first.
  Future<String> eventsCsv();

  /// One event's confirmed count — its latest closeout revision, priced at
  /// the prices recorded that day.
  Future<String> eventCountCsv(String eventId);

  /// Every live recipe's current revision, one row per ingredient.
  Future<String> recipesCsv();

  /// Events with a confirmed count, newest first. Empty when nothing has
  /// been counted yet — the screen says so rather than offering a picker
  /// with nothing in it.
  Future<List<CountedEvent>> countedEvents();
}

final class DriftSpreadsheetExportService implements SpreadsheetExportService {
  DriftSpreadsheetExportService(
    db.AppDatabase database,
    ForecastService forecast,
    EventCostService costs,
  ) : _db = database,
      _forecast = forecast,
      _costs = costs;

  final db.AppDatabase _db;
  final ForecastService _forecast;
  final EventCostService _costs;

  // ------------------------------------------------------------- headings
  // Plain words a spreadsheet reader understands. Never a column name.

  static const List<String> itemsHeader = [
    'Folder',
    'Item',
    'Amount on hand',
    'Unit label',
    'Price each',
    'Value',
    'Planning answer',
    'Has barcode',
    'Archived',
  ];

  static const List<String> eventsHeader = [
    'Event',
    'Date',
    'Status',
    'Planned attendance',
    'Confirmed attendance',
    'Estimated cost',
    'Actual spent',
    'Items missing from the cost',
  ];

  static const List<String> eventCountHeader = [
    'Item',
    'Counted',
    'Expected',
    'Variance',
    'Price each',
    'Line cost',
  ];

  static const List<String> recipesHeader = [
    'Recipe',
    'Revision',
    'Yield',
    'Yield label',
    'Ingredient',
    'Amount per batch',
    'Unit label',
    'Linked item',
  ];

  /// What an item with no folder is called. "Unfiled" is a real answer the
  /// app already uses on screen, not missing data, so it is not an empty
  /// cell.
  static const String unfiledFolderName = 'Unfiled';

  // ---------------------------------------------------------------- items

  @override
  Future<String> itemsCsv() async {
    final items = await _db.select(_db.items).get();
    final folders = {
      for (final folder in await _db.select(_db.folders).get())
        folder.id: folder,
    };
    final onHand = await _db.ledgerDao.onHandByItem();
    // Packing order: the owner's folder order, Unfiled last, then by name.
    // Nothing sorts by id — the reader has never seen one.
    items.sort((a, b) {
      final left = folders[a.folderId]?.position ?? _unfiledPosition;
      final right = folders[b.folderId]?.position ?? _unfiledPosition;
      if (left != right) return left.compareTo(right);
      return _byName(a.name, b.name);
    });
    final rows = <List<String?>>[itemsHeader];
    for (final item in items) {
      final price = item.unitPriceCents;
      final amountMicros = onHand[item.id] ?? 0;
      rows.add([
        folders[item.folderId]?.name ?? unfiledFolderName,
        item.name,
        csvQuantity(amountMicros),
        item.unitLabel,
        csvMoney(price),
        price == null
            ? null
            : csvMoney(
                lineCents(unitPriceCents: price, quantityMicros: amountMicros),
              ),
        _planningAnswer(item),
        csvYesNo(item.barcode != null),
        csvYesNo(item.archivedAtMicros != null),
      ]);
    }
    return encodeCsv(rows);
  }

  static const int _unfiledPosition = 1 << 30;

  /// The one question every item answers, in the words the app uses on
  /// screen. Exactly one of the three forms can be stored (the validator
  /// enforces it); never answered is an empty cell, not a zero.
  static String? _planningAnswer(db.Item item) {
    if (item.servesPerUnitMicros case final serves?) {
      return 'One serves ${csvQuantity(serves)} people';
    }
    final numerator = item.perPersonNumerator;
    final denominator = item.perPersonDenominator;
    if (numerator != null && denominator != null) {
      return denominator == 1
          ? '$numerator per person'
          : '$numerator per $denominator people';
    }
    if (item.perEventBaselineMicros case final baseline?) {
      return 'Usually bring ${csvQuantity(baseline)}';
    }
    return null;
  }

  // --------------------------------------------------------------- events

  @override
  Future<String> eventsCsv() async {
    final events = await _db.select(_db.events).get();
    events.sort((a, b) {
      final byDate = b.scheduledDate.compareTo(a.scheduledDate); // newest first
      return byDate != 0 ? byDate : _byName(a.name, b.name);
    });
    final rows = <List<String?>>[eventsHeader];
    for (final event in events) {
      final closeout = await _db.closeoutDao.latestHeaderForEvent(event.id);
      String? estimated;
      String? spent;
      String? missing;
      if (event.status == 'closed') {
        // A closed event's money is history: the quantities it confirmed,
        // at the prices snapshotted the day it was closed out. Today's
        // catalog prices are not what she paid, so they never appear here.
        if (closeout != null) {
          final lines = await _db.closeoutDao.linesFor(closeout.id);
          var total = 0;
          var priced = 0;
          var unpriced = 0;
          for (final line in lines) {
            final cents = line.unitPriceCents;
            if (cents == null) {
              unpriced++;
              continue;
            }
            total += lineCents(
              unitPriceCents: cents,
              quantityMicros: line.depletionMicros,
            );
            priced++;
          }
          spent = priced == 0 ? null : csvMoney(total);
          missing = csvInteger(unpriced);
        }
      } else if (event.status != 'cancelled') {
        // Still to come: the packing list priced at today's prices — the
        // same arithmetic the event screen shows, so the file and the app
        // can never disagree.
        final planned = await _costs.plannedCost(event.id);
        estimated = planned.isEmpty ? null : csvMoney(planned.total.cents);
        missing = csvInteger(planned.unpricedItemCount);
      }
      rows.add([
        event.name,
        event.scheduledDate,
        _statusWord(event.status),
        csvInteger(event.plannedExposure),
        csvInteger(closeout?.confirmedExposure),
        estimated,
        spent,
        missing,
      ]);
    }
    return encodeCsv(rows);
  }

  static String _statusWord(String status) => switch (status) {
    'planned' => 'Planned',
    'active' => 'Active',
    'closed' => 'Closed',
    'cancelled' => 'Cancelled',
    _ => status,
  };

  // ---------------------------------------------------------- event count

  @override
  Future<String> eventCountCsv(String eventId) async {
    final rows = <List<String?>>[eventCountHeader];
    // The app's own forecast-vs-actual comparison, reused verbatim: what
    // was expected is whatever the accuracy screen calls expected, so the
    // exported variance and the on-screen variance are the same number.
    final review = await _forecast.accuracyReview(eventId);
    final closeoutId = review.closeoutId;
    if (closeoutId == null) return encodeCsv(rows);
    final lines = await _db.closeoutDao.linesFor(closeoutId.value);
    final priceByItem = {
      for (final line in lines) line.itemId: line.unitPriceCents,
    };
    final names = {
      for (final item in await _db.itemDao.byIds(priceByItem.keys))
        item.id: item.name,
    };
    // Keyed by item NAME, never by id: a ULID column would mean nothing to
    // the person opening this file, and the name is what she calls it.
    final counted = [
      for (final line in review.lines)
        if (priceByItem.containsKey(line.itemId as String))
          (id: line.itemId as String, line: line),
    ]..sort((a, b) => _byName(names[a.id] ?? '', names[b.id] ?? ''));
    for (final (:id, :line) in counted) {
      final price = priceByItem[id];
      final depletion = line.actualDepletionMicros;
      rows.add([
        names[id],
        csvQuantity(depletion),
        csvQuantity(line.expectedUseMicros),
        csvQuantity(line.varianceMicros),
        csvMoney(price),
        price == null || depletion == null
            ? null
            : csvMoney(
                lineCents(unitPriceCents: price, quantityMicros: depletion),
              ),
      ]);
    }
    return encodeCsv(rows);
  }

  @override
  Future<List<CountedEvent>> countedEvents() async {
    final rows = await _db
        .customSelect(
          'SELECT e.id AS id, e.name AS name, '
          'e.scheduled_date AS scheduled_date '
          'FROM events e '
          'WHERE EXISTS (SELECT 1 FROM event_closeouts c '
          '              WHERE c.event_id = e.id) '
          'ORDER BY e.scheduled_date DESC, lower(e.name) ASC',
          readsFrom: {_db.events, _db.eventCloseouts},
        )
        .get();
    return [
      for (final row in rows)
        CountedEvent(
          id: row.read<String>('id'),
          name: row.read<String>('name'),
          scheduledDate: row.read<String>('scheduled_date'),
        ),
    ];
  }

  // -------------------------------------------------------------- recipes

  @override
  Future<String> recipesCsv() async {
    final rows = <List<String?>>[recipesHeader];
    // Live recipes only, and each one's CURRENT revision: the question this
    // file answers is "what is the recipe", not "what did it used to be".
    // The revision number rides along so the reader knows which one it is.
    final recipes = [
      for (final recipe in await _db.recipeDao.all())
        if (recipe.archivedAtMicros == null) recipe,
    ];
    for (final recipe in recipes) {
      final revision = await _db.recipeDao.latestRevisionFor(recipe.id);
      if (revision == null) continue;
      final lines = await _db.recipeDao.linesForRevision(revision.id);
      final linkedNames = {
        for (final item in await _db.itemDao.byIds([
          for (final line in lines) ?line.ingredientItemId,
        ]))
          item.id: item.name,
      };
      final head = <String?>[
        recipe.name,
        csvInteger(revision.revision),
        csvQuantity(revision.yieldMicros),
        revision.yieldLabel,
      ];
      if (lines.isEmpty) {
        // A recipe with no ingredients recorded is still a recipe: a row
        // with empty ingredient cells is honest, silence is not.
        rows.add([...head, null, null, null, null]);
        continue;
      }
      for (final line in lines) {
        rows.add([
          ...head,
          line.ingredientName,
          csvQuantity(line.quantityPerBatchMicros),
          line.unitLabel,
          linkedNames[line.ingredientItemId],
        ]);
      }
    }
    return encodeCsv(rows);
  }

  /// Case-insensitive name order, the app's own list order.
  static int _byName(String a, String b) {
    final byLower = a.toLowerCase().compareTo(b.toLowerCase());
    return byLower != 0 ? byLower : a.compareTo(b);
  }
}
