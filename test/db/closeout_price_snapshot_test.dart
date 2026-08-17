/// §11.1 family F (closeout semantics, schema v7): every closeout line
/// snapshots the item's CURRENT unit_price_cents at the moment its revision
/// is applied — confirm and revision alike — so "what this event cost"
/// survives later price edits. A revision re-snapshots at revision time (a
/// correction is made at today's knowledge); the superseded revision's rows
/// keep the price of THEIR moment, byte-intact under the append-only
/// triggers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/closeout/application/closeout_service.dart';
import 'package:loadout/features/closeout/domain/closeout.dart';
import 'package:loadout/features/forecasting/application/forecast_service.dart';

import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;
  late String priced;
  late String unpriced;
  late String eventId;

  setUp(() async {
    h = WritePathHarness();
    final receipt = await h.ok(
      CreateItem(name: 'Tortillas', unitPrice: Money.fromCents(299)),
    );
    priced = receipt.createdRecordIds.first;
    unpriced = await h.createItem(name: 'Salsa');
    eventId = await h.createEvent(
      name: 'Market',
      plannedExposure: 100,
      plannedItemIds: [priced, unpriced],
    );
    await h.ok(ActivateEvent(EventId(eventId)));
    await h.receive(priced, 50000000);
    await h.receive(unpriced, 10000000);
  });

  tearDown(() => h.close());

  CloseoutLineDraft line(String itemId, int depletionMicros) =>
      CloseoutLineDraft(
        itemId: ItemId(itemId),
        depletion: Quantity.fromMicros(depletionMicros),
      );

  Future<String> confirm() async {
    final receipt = await h.ok(
      RecordCloseout(
        eventId: EventId(eventId),
        confirmedExposure: 100,
        lines: [line(priced, 30000000), line(unpriced, 5000000)],
      ),
    );
    return receipt.createdRecordIds.first;
  }

  Future<Map<String, int?>> priceByItem(String closeoutId) async => {
    for (final l in await h.db.closeoutDao.linesFor(closeoutId))
      l.itemId: l.unitPriceCents,
  };

  test('confirm stamps each line with the price of that moment; an '
      'unpriced item stamps NULL', () async {
    final closeoutId = await confirm();
    final prices = await priceByItem(closeoutId);
    expect(prices[priced], 299);
    expect(prices[unpriced], isNull, reason: 'no price then = NULL forever');
  });

  test('the snapshot survives a later price edit; a revision re-snapshots '
      'at revision time and the original rows stay untouched', () async {
    final firstId = await confirm();

    // The owner reprices the item AFTER the event closed…
    await h.ok(
      UpdateItem(itemId: ItemId(priced), unitPrice: Money.fromCents(349)),
    );
    // …and gives the other item its first price.
    await h.ok(
      UpdateItem(itemId: ItemId(unpriced), unitPrice: Money.fromCents(150)),
    );

    // Revision 1 still says what the event cost when it happened.
    final original = await priceByItem(firstId);
    expect(original[priced], 299, reason: 'history survives the edit');
    expect(original[unpriced], isNull);

    // A revision is a correction made at today's knowledge: it carries
    // today's prices.
    final revised = await h.ok(
      ReviseCloseout(
        eventId: EventId(eventId),
        confirmedExposure: 120,
        lines: [line(priced, 32000000), line(unpriced, 5000000)],
      ),
    );
    final secondId = revised.createdRecordIds.first;
    final revision = await priceByItem(secondId);
    expect(revision[priced], 349);
    expect(revision[unpriced], 150);

    // And revision 1's rows are byte-intact — the append-only contract.
    final untouched = await priceByItem(firstId);
    expect(untouched[priced], 299);
    expect(untouched[unpriced], isNull);
  });

  group('read surface', () {
    late DriftCloseoutService service;

    setUp(() {
      service = DriftCloseoutService(
        h.db,
        h.applier,
        forecastService: _UnusedForecastService(),
        idGenerator: h.ids,
        clock: h.clock,
      );
    });

    test('watchRevisions exposes each revision\'s own snapshot', () async {
      await confirm();
      await h.ok(
        UpdateItem(itemId: ItemId(priced), unitPrice: Money.fromCents(349)),
      );
      await h.ok(
        ReviseCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 120,
          lines: [line(priced, 32000000), line(unpriced, 5000000)],
        ),
      );

      final revisions = await service.watchRevisions(eventId).first;
      expect(revisions, hasLength(2));
      CloseoutLine lineFor(int revision, String itemId) => revisions
          .singleWhere((r) => r.revision == revision)
          .lines
          .singleWhere((l) => l.itemId as String == itemId);
      expect(lineFor(1, priced).unitPriceCents, 299);
      expect(lineFor(2, priced).unitPriceCents, 349);
      expect(lineFor(1, unpriced).unitPriceCents, isNull);
      expect(lineFor(2, unpriced).unitPriceCents, isNull);
    });

    test('latestCloseoutCostLines: latest revision only, name-ordered, '
        'depletion + snapshot + names; empty when never closed', () async {
      expect(await service.latestCloseoutCostLines(eventId), isEmpty);

      await confirm();
      await h.ok(
        UpdateItem(itemId: ItemId(priced), unitPrice: Money.fromCents(349)),
      );
      await h.ok(
        ReviseCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 120,
          lines: [line(priced, 32000000), line(unpriced, 5000000)],
        ),
      );

      final lines = await service.latestCloseoutCostLines(eventId);
      expect([for (final l in lines) l.itemName], ['Salsa', 'Tortillas']);
      final tortillas = lines.singleWhere((l) => l.itemId == priced);
      expect(tortillas.depletionMicros, 32000000);
      expect(tortillas.unitPriceCents, 349, reason: 'the LATEST revision');
      final salsa = lines.singleWhere((l) => l.itemId == unpriced);
      expect(salsa.depletionMicros, 5000000);
      expect(
        salsa.unitPriceCents,
        isNull,
        reason:
            'unpriced at revision time — a total must say "unknown", '
            'not pretend the event was cheaper',
      );
    });
  });

  test('SQL backstop: the CHECK bounds hostile closeout_lines writes and '
      'INSERT stays legal on the append-only table', () async {
    final closeoutId = await confirm();
    await expectLater(
      h.db.customStatement(
        'INSERT INTO closeout_lines '
        '(closeout_id, item_id, depletion_micros, unit_price_cents) '
        'VALUES (?, ?, 0, 0)',
        [closeoutId, priced],
      ),
      throwsA(anything),
      reason: '0 cents is outside the CHECK range',
    );
    await expectLater(
      h.db.customStatement(
        'UPDATE closeout_lines SET unit_price_cents = 350 WHERE closeout_id = ?',
        [closeoutId],
      ),
      throwsA(anything),
      reason: 'the append-only trigger still forbids every UPDATE',
    );
  });
}

/// prefill() is the only CloseoutService member that touches forecasting,
/// and nothing here calls it.
final class _UnusedForecastService implements ForecastService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by this test');
}
