/// What each of the four exports actually writes: the exact header row a
/// spreadsheet user reads, and the exact content of a seeded row.
///
/// The rule these tests exist to hold is the honesty one — an unknown value
/// is an EMPTY cell. An unpriced item must not export `0.00`, because a
/// treasurer summing that column would get a number the owner cannot
/// defend.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/unit_ratio.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../../support/app_harness.dart';
import 'export_test_support.dart';

void main() {
  testWidgets('items: header, folder order, and no zero for no price', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    late String document;
    await tester.runAsync(() async {
      final drinks = await folderIdByName(h, 'Drinks');
      await seedItem(
        h,
        name: 'Lemonade',
        folderId: drinks,
        unitPrice: Money.fromCents(250),
        unitLabel: 'bottles',
        openingCount: Quantity.whole(12),
        servesPerUnit: Quantity.whole(4),
        barcode: '5012345678900',
      );
      // No price at all: the value column must stay blank, not read 0.00.
      await seedItem(
        h,
        name: 'Napkins',
        folderId: await folderIdByName(h, 'Disposables'),
        openingCount: Quantity.whole(200),
        perPersonRatio: UnitRatio(3, 1),
      );
      // Unfiled, archived, and named like a formula.
      final leftovers = await seedItem(h, name: '-- leftovers');
      await archiveItem(h, leftovers);
      document = await h.read(spreadsheetExportServiceProvider).itemsCsv();
    });

    final rows = csvRows(document);
    expect(
      rows.first,
      'Folder,Item,Amount on hand,Unit label,Price each,Value,'
      'Planning answer,Has barcode,Archived',
    );
    // Folder order is the owner's packing order; Unfiled goes last.
    expect(
      rows[1],
      'Drinks,Lemonade,12,bottles,2.50,30.00,One serves 4 people,Yes,No',
    );
    expect(rows[2], 'Disposables,Napkins,200,,,,3 per person,No,No');
    expect(rows[3], "Unfiled,'-- leftovers,0,,,,,No,Yes");
    expect(rows, hasLength(4));
  });

  testWidgets('events: estimate ahead, actual spent behind, both honest', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    late String document;
    await tester.runAsync(() async {
      final cups = await seedItem(
        h,
        name: 'Cups',
        unitPrice: Money.fromCents(200),
        servesPerUnit: Quantity.whole(4),
      );
      final napkins = await seedItem(h, name: 'Napkins');
      final past = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [cups, napkins],
      );
      await activateEvent(h, past);
      await confirmCloseout(
        h,
        past,
        exposure: 90,
        lines: [
          CloseoutFormLine(itemId: cups, depletion: Quantity.whole(30)),
          CloseoutFormLine(itemId: napkins, depletion: Quantity.whole(10)),
        ],
      );
      final upcoming = await seedEvent(
        h,
        name: 'Autumn market',
        date: '2026-09-05',
        exposure: 40,
        itemIds: [cups, napkins],
      );
      await generateForecast(h, upcoming);
      // Never started, never counted: no money at all, either way.
      await seedEvent(h, name: 'Bake sale', date: '2026-06-01');
      document = await h.read(spreadsheetExportServiceProvider).eventsCsv();
    });

    final rows = csvRows(document);
    expect(
      rows.first,
      'Event,Date,Status,Planned attendance,Confirmed attendance,'
      'Estimated cost,Actual spent,Items missing from the cost',
    );
    // Newest first. The upcoming event is priced at today's prices — the
    // SAME arithmetic the event screen shows (the forecast's effective load
    // × the current price), so the file and the app can never disagree —
    // and the unpriced napkins are counted out loud rather than dropped.
    expect(rows[1], 'Autumn market,2026-09-05,Planned,40,,30.00,,1');
    // The closed event's money is history: 30 cups at the 2.00 recorded
    // when it was closed out. Napkins had no price, so they are missing
    // from the total and said so.
    expect(rows[2], 'Street fair,2026-08-10,Closed,100,90,,60.00,1');
    expect(rows[3], 'Bake sale,2026-06-01,Planned,,,,,0');
    expect(rows, hasLength(4));
  });

  testWidgets('one event count: counted against expected, priced as counted', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    late String document;
    late List<String> counted;
    await tester.runAsync(() async {
      final cups = await seedItem(
        h,
        name: 'Cups',
        unitPrice: Money.fromCents(200),
        servesPerUnit: Quantity.whole(4),
      );
      final napkins = await seedItem(h, name: 'Napkins');
      final eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [cups, napkins],
      );
      await generateForecast(h, eventId);
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [
          CloseoutFormLine(itemId: cups, depletion: Quantity.whole(30)),
          CloseoutFormLine(itemId: napkins, depletion: Quantity.whole(10)),
        ],
      );
      final service = h.read(spreadsheetExportServiceProvider);
      document = await service.eventCountCsv(eventId);
      counted = [for (final event in await service.countedEvents()) event.name];
    });

    final rows = csvRows(document);
    expect(rows.first, 'Item,Counted,Expected,Variance,Price each,Line cost');
    // 100 people at "one serves 4" expected 25; 30 were counted.
    expect(rows[1], 'Cups,30,25,5,2.00,60.00');
    // No forecast for this item and no price: three empty cells, no zeros.
    expect(rows[2], 'Napkins,10,,,,');
    expect(rows, hasLength(3));
    expect(counted, ['Street fair']);
  });

  testWidgets('recipes: one row per ingredient, link named where linked', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    late String document;
    await tester.runAsync(() async {
      final beans = await seedItem(h, name: 'Black beans');
      await seedRecipe(
        h,
        name: 'Chilli',
        yieldWhole: 12,
        yieldLabel: 'bowls',
        lines: [
          RecipeFormLine(itemId: beans, quantityPerBatch: Quantity.whole(3)),
          RecipeFormLine(
            name: 'Cumin',
            unitLabel: 'tsp',
            quantityPerBatch: Quantity.fromMicros(1500000),
          ),
        ],
      );
      document = await h.read(spreadsheetExportServiceProvider).recipesCsv();
    });

    final rows = csvRows(document);
    expect(
      rows.first,
      'Recipe,Revision,Yield,Yield label,Ingredient,Amount per batch,'
      'Unit label,Linked item',
    );
    expect(rows[1], 'Chilli,1,12,bowls,Black beans,3,,Black beans');
    expect(rows[2], 'Chilli,1,12,bowls,Cumin,1.5,tsp,');
    expect(rows, hasLength(3));
  });

  testWidgets('an empty workspace exports headers and nothing else', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await tester.runAsync(() async {
      final service = h.read(spreadsheetExportServiceProvider);
      expect(csvRows(await service.itemsCsv()), hasLength(1));
      expect(csvRows(await service.eventsCsv()), hasLength(1));
      expect(csvRows(await service.recipesCsv()), hasLength(1));
      expect(await service.countedEvents(), isEmpty);
    });
  });
}
