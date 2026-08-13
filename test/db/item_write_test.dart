/// §11.1 family F (catalog write path, schema v2): an item is a NAME + HOW
/// MANY YOU HAVE + optionally HOW MANY PEOPLE ONE SERVES. Units and pack
/// sizes are defaulted, never asked; the opening count is one `adjust`
/// movement written in the SAME transaction as the item row.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/approval/domain/command_validator.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

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

  group('defaults (units left the product surface)', () {
    test('a name-only draft stores each / one unit / no serves', () async {
      final itemId = (await catalog.createItem(
        const ItemDraft(name: 'Buns'),
      )).fold((id) => id, (e) => fail(e.message));
      final row = await h.itemRow(itemId);
      expect(row.unit, 'each');
      expect(row.packSizeMicros, Quantity.scale);
      expect(row.servesPerUnitMicros, isNull);
      expect(
        await h.onHand(itemId),
        0,
        reason: 'no opening count, no movement',
      );
      expect(await h.count('inventory_movements'), 0);
    });
  });

  group('serves per unit', () {
    test('stored, updated, and cleared through the command path', () async {
      final itemId = (await catalog.createItem(
        ItemDraft(name: 'Pizza', servesPerUnit: Quantity.whole(4)),
      )).fold((id) => id, (e) => fail(e.message));
      expect((await h.itemRow(itemId)).servesPerUnitMicros, 4000000);

      // 1 pizza now serves 6 (bigger pizzas).
      (await catalog.updateItem(
        itemId: itemId,
        draft: ItemDraft(name: 'Pizza', servesPerUnit: Quantity.whole(6)),
      )).fold((_) {}, (e) => fail(e.message));
      expect((await h.itemRow(itemId)).servesPerUnitMicros, 6000000);

      // A draft with no answer clears it: "I don't know" is a legal answer.
      (await catalog.updateItem(
        itemId: itemId,
        draft: const ItemDraft(name: 'Pizza'),
      )).fold((_) {}, (e) => fail(e.message));
      expect((await h.itemRow(itemId)).servesPerUnitMicros, isNull);
    });

    test('must be greater than zero', () async {
      final error = await h.err(
        CreateItem(name: 'Pizza', servesPerUnit: Quantity.zero),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('greater than zero'));
      expect(await h.count('items'), 0);
    });

    test('is capped at a sane number of people', () async {
      final tooMany = Quantity.fromMicros(maxServesPerUnitMicros + 1);
      final error = await h.err(
        CreateItem(name: 'Urn of tea', servesPerUnit: tooMany),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('at most 10000'));
      expect(await h.count('items'), 0);

      // The cap itself is legal.
      await h.ok(
        CreateItem(
          name: 'Urn of tea',
          servesPerUnit: Quantity.fromMicros(maxServesPerUnitMicros),
        ),
      );
    });

    test('the cap is enforced by SQL too, not only by the validator', () async {
      await expectLater(
        insertItem(
          h.db,
          tid('IX'),
          name: 'Hostile',
          servesPerUnitMicros: maxServesPerUnitMicros + 1,
        ),
        throwsA(anything),
      );
      await expectLater(
        insertItem(h.db, tid('IY'), name: 'Hostile2', servesPerUnitMicros: 0),
        throwsA(anything),
      );
    });
  });

  group('opening count', () {
    test(
      'one command writes the item AND its opening adjust movement',
      () async {
        final receipt = await h.ok(
          CreateItem(name: 'Buns', openingCount: Quantity.whole(48)),
        );
        final itemId = receipt.createdRecordIds.first;
        expect(receipt.createdRecordIds, hasLength(2));
        expect(await h.count('commands'), 1, reason: 'ONE logical operation');
        expect(await h.onHand(itemId), 48000000);

        final movement = await h.movementRow(receipt.createdRecordIds[1]);
        expect(movement.itemId, itemId);
        expect(movement.kind, 'adjust');
        expect(movement.deltaMicros, 48000000);
        expect(movement.note, 'Opening count');
        expect(
          movement.sourceCommandId,
          receipt.commandId as String,
          reason: 'the movement is audited to the same command as the item',
        );
      },
    );

    test('zero (or absent) records no movement at all', () async {
      final zero = await h.ok(
        CreateItem(name: 'Buns', openingCount: Quantity.zero),
      );
      expect(zero.createdRecordIds, hasLength(1));
      final absent = await h.ok(const CreateItem(name: 'Napkins'));
      expect(absent.createdRecordIds, hasLength(1));
      expect(await h.count('inventory_movements'), 0);
    });

    test('a rejected create leaves neither an item nor a movement', () async {
      await h.createItem(name: 'Buns');
      final error = await h.err(
        CreateItem(name: 'buns', openingCount: Quantity.whole(10)),
      );
      expect(error, isA<ValidationError>());
      expect(await h.count('items'), 1, reason: 'the duplicate never landed');
      expect(
        await h.count('inventory_movements'),
        0,
        reason: 'no orphan movement from the rejected create',
      );
    });

    test(
      'a movement the database refuses takes the item down with it',
      () async {
        // Fault injection at the only layer that can still fail after
        // validation passes: SQL itself. If the opening movement cannot be
        // written, the item it belongs to must not exist either.
        await h.db.customStatement(
          'CREATE TRIGGER trg_test_block BEFORE INSERT ON inventory_movements '
          "BEGIN SELECT RAISE(ABORT, 'injected'); END",
        );
        await expectLater(
          h.submit(CreateItem(name: 'Buns', openingCount: Quantity.whole(48))),
          throwsA(isA<SqliteException>()),
        );
        expect(await h.count('items'), 0, reason: 'no item without its count');
        expect(await h.count('inventory_movements'), 0);
        expect(
          await h.count('commands'),
          0,
          reason: 'the audit row rolled back',
        );
      },
    );

    test('replaying the same commandId does not double the count', () async {
      final command = CreateItem(
        name: 'Buns',
        openingCount: Quantity.whole(48),
      );
      final first = await h.ok(command, commandId: tid('CMD1'));
      final second = await h.ok(command, commandId: tid('CMD1'));
      expect(second.createdRecordIds, first.createdRecordIds);
      expect(await h.count('items'), 1);
      expect(await h.count('inventory_movements'), 1);
      expect(await h.onHand(first.createdRecordIds.first), 48000000);
    });

    test(
      'CatalogService.createItem threads it and returns the ITEM id',
      () async {
        final itemId = (await catalog.createItem(
          const ItemDraft(name: 'Buns'),
          openingCount: Quantity.whole(12),
        )).fold((id) => id, (e) => fail(e.message));
        expect((await h.itemRow(itemId)).name, 'Buns');
        expect(await h.onHand(itemId), 12000000);
      },
    );

    test('the opening movement is a normal correctable ledger row', () async {
      final receipt = await h.ok(
        CreateItem(name: 'Buns', openingCount: Quantity.whole(48)),
      );
      final itemId = receipt.createdRecordIds.first;
      await h.ok(
        CorrectMovement(
          target: MovementId(receipt.createdRecordIds[1]),
          reason: 'miscounted the tray',
        ),
      );
      expect(await h.onHand(itemId), 0);
    });
  });

  group('legacy rows keep their v1 shape', () {
    test('an explicit unit and pack size still round-trip', () async {
      final itemId = await h.createItem(
        name: 'Mince (500g packs)',
        unit: ItemUnit.kg,
        packMicros: 500000,
      );
      final row = await h.itemRow(itemId);
      expect(row.unit, 'kg');
      expect(row.packSizeMicros, 500000);
    });
  });
}
