/// §11.1 family F (delete against an append-only ledger): DeleteItem and
/// DeleteAllItems hard-delete the row when no history references it and
/// archive it when any does. Both paths clear the item's mutable references
/// (recipe_lines_v2 links, the recipe output binding, not-yet-closed event
/// plan rows); blocker rows — movements, closeout lines, frozen v1 recipe
/// lines, forecast rows, closed-event plan rows — are never touched.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import 'fixtures.dart';
import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;
  late DriftCatalogService catalog;

  setUp(() {
    h = WritePathHarness();
    catalog = DriftCatalogService(
      h.db,
      h.applier,
      idGenerator: h.ids,
      clock: h.clock,
    );
  });

  tearDown(() => h.close());

  Future<Item?> itemRowOrNull(String id) => (h.db.select(
    h.db.items,
  )..where((i) => i.id.equals(id))).getSingleOrNull();

  Future<void> expectFksClean() async {
    final violations = await h.db
        .customSelect('PRAGMA foreign_key_check')
        .get();
    expect(violations, isEmpty);
  }

  group('hard delete (no history)', () {
    test('a fresh item row is gone from items', () async {
      final itemId = await h.createItem(name: 'Buns');
      await h.ok(DeleteItem(itemId: ItemId(itemId)));
      expect(await itemRowOrNull(itemId), isNull);
      expect(await h.count('items'), 0);
      await expectFksClean();
    });

    test('CatalogService.deleteItem drives the same command', () async {
      final itemId = await h.createItem(name: 'Buns');
      (await catalog.deleteItem(
        itemId: itemId,
      )).fold((_) {}, (e) => fail(e.message));
      expect(await h.count('items'), 0);
    });

    test('an archived item with no history is hard-deleted too', () async {
      final itemId = await h.createItem(name: 'Buns');
      await h.ok(SetItemArchived(itemId: ItemId(itemId), archived: true));
      await h.ok(DeleteItem(itemId: ItemId(itemId)));
      expect(await itemRowOrNull(itemId), isNull);
    });
  });

  group('archive fallback (history exists)', () {
    test('a movement keeps the row; delete archives and frees the '
        'name for reuse', () async {
      final itemId = await h.createItem(name: 'Buns', openingMicros: 48000000);
      await h.ok(DeleteItem(itemId: ItemId(itemId)));

      final row = await itemRowOrNull(itemId);
      expect(row, isNotNull, reason: 'the ledger blocks a hard delete');
      expect(row!.archivedAtMicros, h.clock.now().epochMicrosUtc);
      expect(await h.count('inventory_movements'), 1, reason: 'untouched');

      // The live-name partial unique index no longer sees the archived row.
      final again = await h.createItem(name: 'Buns');
      expect((await h.itemRow(again)).name, 'Buns');
      await expectFksClean();
    });

    test('deleting an already-archived blocked item is a successful no-op '
        'that keeps the original archived_at', () async {
      final itemId = await h.createItem(name: 'Buns', openingMicros: 48000000);
      await h.ok(SetItemArchived(itemId: ItemId(itemId), archived: true));
      final archivedAt = (await h.itemRow(itemId)).archivedAtMicros;

      h.clock.advanceMicros(1000000);
      await h.ok(DeleteItem(itemId: ItemId(itemId)));
      final row = await h.itemRow(itemId);
      expect(row.archivedAtMicros, archivedAt, reason: 'not re-stamped');
    });
  });

  group('recipe references (cleared on both paths)', () {
    test('a linked recipe_lines_v2 line is unlinked; its own name '
        'survives', () async {
      final itemId = await h.createItem(name: 'Salsa');
      await h.ok(
        CreateRecipe(
          name: 'Tacos',
          firstRevision: RecipeRevisionDraft(
            yieldQuantity: Quantity.whole(12),
            lines: [
              RecipeLineDraft(
                ingredientItemId: ItemId(itemId),
                quantityPerBatch: Quantity.one,
              ),
            ],
          ),
        ),
      );
      await h.ok(DeleteItem(itemId: ItemId(itemId)));

      expect(await itemRowOrNull(itemId), isNull, reason: 'links never block');
      final line = await h.db.select(h.db.recipeLinesV2).getSingle();
      expect(line.ingredientItemId, isNull);
      expect(line.ingredientName, 'Salsa', reason: 'snapshotted at write');
      await expectFksClean();
    });

    test('a recipe output binding is unbound; the recipe survives', () async {
      final itemId = await h.createItem(name: 'Salsa');
      final receipt = await h.ok(
        CreateRecipe(
          outputItemId: ItemId(itemId),
          name: 'Salsa',
          firstRevision: RecipeRevisionDraft(
            yieldQuantity: Quantity.whole(1),
            lines: const [
              RecipeLineDraft(name: 'Tomatoes', quantityPerBatch: Quantity.one),
            ],
          ),
        ),
      );
      await h.ok(DeleteItem(itemId: ItemId(itemId)));

      expect(await itemRowOrNull(itemId), isNull);
      final recipe = await (h.db.select(
        h.db.recipes,
      )..where((r) => r.id.equals(receipt.createdRecordIds.first))).getSingle();
      expect(recipe.outputItemId, isNull, reason: 'left the items list');
      await expectFksClean();
    });

    test('a frozen v1 recipe line blocks the hard delete', () async {
      final outputId = await h.createItem(name: 'Salsa');
      final ingredientId = await h.createItem(name: 'Tomatoes');
      await insertRecipe(h.db, tid('R1'), outputItemId: outputId);
      await insertRecipeRevision(h.db, tid('RV1'), recipeId: tid('R1'));
      await insertRecipeLine(
        h.db,
        revisionId: tid('RV1'),
        ingredientItemId: ingredientId,
      );
      await h.ok(DeleteItem(itemId: ItemId(ingredientId)));

      final row = await itemRowOrNull(ingredientId);
      expect(row!.archivedAtMicros, isNotNull, reason: 'v1 lines are frozen');
      expect(await h.count('recipe_lines'), 1, reason: 'untouched');
      await expectFksClean();
    });
  });

  group('event plans', () {
    test('a planned event loses its plan row and the item row goes', () async {
      final itemId = await h.createItem(name: 'Buns');
      await h.createEvent(name: 'Market', plannedItemIds: [itemId]);
      await h.ok(DeleteItem(itemId: ItemId(itemId)));

      expect(await h.count('event_items'), 0, reason: 'plans are mutable');
      expect(await itemRowOrNull(itemId), isNull);
      await expectFksClean();
    });

    test('closed-event history archives; closeout rows and the closed plan '
        'row stay untouched', () async {
      final itemId = await h.createItem(name: 'Buns');
      final eventId = await h.createEvent(
        name: 'Market',
        plannedItemIds: [itemId],
      );
      await h.ok(ActivateEvent(EventId(eventId)));
      await h.receive(itemId, 50000000);
      await h.ok(
        RecordCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 100,
          lines: [
            CloseoutLineDraft(
              itemId: ItemId(itemId),
              depletion: Quantity.fromMicros(30000000),
            ),
          ],
        ),
      );
      final movementsBefore = await h.count('inventory_movements');

      await h.ok(DeleteItem(itemId: ItemId(itemId)));
      final row = await h.itemRow(itemId);
      expect(row.archivedAtMicros, isNotNull);
      expect(await h.count('closeout_lines'), 1, reason: 'history untouched');
      expect(await h.count('event_items'), 1, reason: 'closed plans stay');
      expect(await h.count('inventory_movements'), movementsBefore);
      await expectFksClean();
    });
  });

  group('forecast history', () {
    test('a snapshot line blocks the hard delete', () async {
      final itemId = await h.createItem(name: 'Buns');
      final eventId = await h.createEvent(name: 'Market');
      await insertCommand(h.db, tid('CMDX'));
      await insertSnapshot(
        h.db,
        tid('SNAP'),
        eventId: eventId,
        sourceCommandId: tid('CMDX'),
      );
      await insertForecastLine(h.db, snapshotId: tid('SNAP'), itemId: itemId);
      await h.ok(DeleteItem(itemId: ItemId(itemId)));

      final row = await itemRowOrNull(itemId);
      expect(row!.archivedAtMicros, isNotNull);
      expect(await h.count('forecast_lines'), 1, reason: 'untouched');
      await expectFksClean();
    });
  });

  group('DeleteAllItems', () {
    test('the per-item routine over every live item, one command', () async {
      final fresh = await h.createItem(name: 'Fresh');
      final counted = await h.createItem(
        name: 'Counted',
        openingMicros: 5000000,
      );
      final planned = await h.createItem(name: 'Planned');
      await h.createEvent(name: 'Market', plannedItemIds: [planned]);
      final archivedBefore = await h.createItem(
        name: 'Old',
        openingMicros: 1000000,
      );
      await h.ok(
        SetItemArchived(itemId: ItemId(archivedBefore), archived: true),
      );
      final archivedAt = (await h.itemRow(archivedBefore)).archivedAtMicros;
      final commandsBefore = await h.count('commands');

      h.clock.advanceMicros(1000000);
      await h.ok(const DeleteAllItems());

      expect(await itemRowOrNull(fresh), isNull, reason: 'hard-deleted');
      expect(await itemRowOrNull(planned), isNull, reason: 'plan row cleared');
      expect(await h.count('event_items'), 0);
      final countedRow = await h.itemRow(counted);
      expect(countedRow.archivedAtMicros, isNotNull, reason: 'ledger blocks');
      expect(
        (await h.itemRow(archivedBefore)).archivedAtMicros,
        archivedAt,
        reason: 'previously-archived items are left alone',
      );
      expect(await h.count('commands'), commandsBefore + 1);
      await expectFksClean();
    });

    test('no live items is a successful no-op', () async {
      await h.ok(const DeleteAllItems());
      expect(await h.count('items'), 0);
    });
  });

  group('validation', () {
    test('DeleteItem on an unknown id → NotFoundError', () async {
      final error = await h.err(DeleteItem(itemId: ItemId(tid('NOPE'))));
      expect(error, isA<NotFoundError>());
      expect(error.message, 'item not found');
    });

    test('a rejected delete leaves everything in place', () async {
      final itemId = await h.createItem(name: 'Buns');
      final result = await catalog.deleteItem(itemId: tid('NOPE'));
      expect(result, isA<Err<void>>());
      expect(await itemRowOrNull(itemId), isNotNull);
    });
  });
}
