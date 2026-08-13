/// Shared seeding for the forecast widget tests: everything goes through
/// the REAL services (design §11.3) — call these inside `tester.runAsync`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/events/domain/event.dart';

import '../../support/app_harness.dart';

/// Unwraps [result] or fails the test with the domain error.
T unwrap<T>(Result<T> result) => result.fold(
  (value) => value,
  (error) => fail('unexpected domain error: ${error.code}: ${error.message}'),
);

/// Creates an `each` item with pack size 12 (the §9 narration example).
Future<String> seedItem(AppHarness h, {String name = 'Tortillas'}) async =>
    unwrap(
      await h
          .read(catalogServiceProvider)
          .createItem(
            ItemDraft(
              name: name,
              unit: ItemUnit.each,
              packSize: Quantity.fromMicros(12 * 1000000),
            ),
          ),
    );

/// Creates an item shaped the way the owner's model shapes one: a NAME, and
/// how many people one serves. No unit, no pack size (both default), so
/// nothing on screen may mention either.
Future<String> seedServesItem(
  AppHarness h, {
  String name = 'Pizzas',
  int servesPerUnit = 4,
}) async => unwrap(
  await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(name: name, servesPerUnit: Quantity.whole(servesPerUnit)),
      ),
);

Future<String> seedEvent(
  AppHarness h, {
  required String name,
  required String date,
  int? exposure,
  List<String> itemIds = const [],
}) async => unwrap(
  await h
      .read(eventServiceProvider)
      .createEvent(
        EventDraft(
          name: name,
          scheduledDate: date,
          plannedExposure: exposure,
          plannedItemIds: itemIds,
        ),
      ),
);

/// Activates [eventId] and confirms its closeout with one line — the real
/// label factory, producing confirmed history for the engine.
Future<void> seedCloseout(
  AppHarness h, {
  required String eventId,
  required int confirmedExposure,
  required String itemId,
  required int depletionMicros,
  bool stockout = false,
  bool approximate = false,
}) async {
  unwrap(await h.read(eventServiceProvider).activate(eventId));
  unwrap(
    await h
        .read(closeoutServiceProvider)
        .confirm(
          CloseoutFormDraft(
            eventId: eventId,
            confirmedExposure: confirmedExposure,
            lines: [
              CloseoutFormLine(
                itemId: itemId,
                depletion: Quantity.fromMicros(depletionMicros),
                stockout: stockout,
                approximate: approximate,
              ),
            ],
          ),
        ),
  );
}

final class ForecastScenario {
  const ForecastScenario({
    required this.itemId,
    required this.historyEventId,
    required this.upcomingEventId,
  });

  final String itemId;
  final String historyEventId;
  final String upcomingEventId;
}

/// One closed history event (exposure 100, depletion 30 each) plus an
/// upcoming planned event for 150. The closeout's consume leaves the ledger
/// at −30 (usable on-hand clamps to 0), so with pack size 12 the frozen
/// engine yields: expected 45, planned 49.5, load 60, acquire 60, grade
/// singleEvent, and the exposure-outside-observed-range warning.
Future<ForecastScenario> seedScenario(AppHarness h) async {
  final itemId = await seedItem(h);
  final historyEventId = await seedEvent(
    h,
    name: 'Past market',
    date: '2026-07-01',
    exposure: 100,
    itemIds: [itemId],
  );
  await seedCloseout(
    h,
    eventId: historyEventId,
    confirmedExposure: 100,
    itemId: itemId,
    depletionMicros: 30 * 1000000,
  );
  final upcomingEventId = await seedEvent(
    h,
    name: 'Street fair',
    date: '2026-09-01',
    exposure: 150,
    itemIds: [itemId],
  );
  return ForecastScenario(
    itemId: itemId,
    historyEventId: historyEventId,
    upcomingEventId: upcomingEventId,
  );
}
