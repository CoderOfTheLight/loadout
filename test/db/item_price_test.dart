/// §11.1 family F (catalog write path, schema v7): an item learns its price.
/// Integer CENTS only, 1 cent to $1,000,000 against the shared cap
/// (`unitPriceCapCents` = `maxUnitPriceCents`), NULL = never priced. The
/// price on `items` is the owner's CURRENT price — mutable master data;
/// history costs come from the closeout-line snapshot, tested separately in
/// closeout_price_snapshot_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';

import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;

  setUp(() => h = WritePathHarness());

  tearDown(() => h.close());

  group('create', () {
    test('a priced item stores exact cents; unpriced stays NULL', () async {
      final priced = await h.ok(
        CreateItem(name: 'Buns', unitPrice: Money.fromCents(1250)),
      );
      final plain = await h.ok(const CreateItem(name: 'Rolls'));
      expect(
        (await h.itemRow(priced.createdRecordIds.first)).unitPriceCents,
        1250,
      );
      expect(
        (await h.itemRow(plain.createdRecordIds.first)).unitPriceCents,
        isNull,
        reason: 'NULL = never priced, the honest default',
      );
    });

    test('bounds: 1 cent and \$1,000,000 are legal, zero and a cent over '
        'are not', () async {
      await h.ok(
        CreateItem(name: 'Penny sweet', unitPrice: Money.fromCents(1)),
      );
      await h.ok(
        CreateItem(name: 'The urn', unitPrice: Money.fromCents(100000000)),
      );
      for (final (name, cents) in [('Free', 0), ('Too dear', 100000001)]) {
        final error = await h.err(
          CreateItem(name: name, unitPrice: Money.fromCents(cents)),
        );
        expect(error, isA<ValidationError>(), reason: '$cents cents');
        expect(error.message, 'price must be between 1 cent and \$1,000,000');
      }
      expect(await h.count('items'), 2, reason: 'only the legal two landed');
    });
  });

  group('update', () {
    test('sets, re-sets, leaves alone, and clears', () async {
      final itemId = await h.createItem(name: 'Buns');
      await h.ok(
        UpdateItem(itemId: ItemId(itemId), unitPrice: Money.fromCents(1250)),
      );
      expect((await h.itemRow(itemId)).unitPriceCents, 1250);

      // A price change replaces the stored cents.
      await h.ok(
        UpdateItem(itemId: ItemId(itemId), unitPrice: Money.fromCents(1399)),
      );
      expect((await h.itemRow(itemId)).unitPriceCents, 1399);

      // An unrelated update leaves the price alone.
      await h.ok(UpdateItem(itemId: ItemId(itemId), name: 'Brioche buns'));
      expect((await h.itemRow(itemId)).unitPriceCents, 1399);

      // clearUnitPrice erases it.
      await h.ok(UpdateItem(itemId: ItemId(itemId), clearUnitPrice: true));
      expect((await h.itemRow(itemId)).unitPriceCents, isNull);
    });

    test('unitPrice and clearUnitPrice together are rejected', () async {
      final itemId = await h.createItem(name: 'Buns');
      final error = await h.err(
        UpdateItem(
          itemId: ItemId(itemId),
          unitPrice: Money.fromCents(1250),
          clearUnitPrice: true,
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, 'set a price or clear it, not both');
      expect((await h.itemRow(itemId)).unitPriceCents, isNull);
    });

    test('bounds apply on update too, at both ends', () async {
      final itemId = await h.createItem(name: 'Buns');
      for (final cents in [0, 100000001]) {
        final error = await h.err(
          UpdateItem(itemId: ItemId(itemId), unitPrice: Money.fromCents(cents)),
        );
        expect(error, isA<ValidationError>(), reason: '$cents cents');
        expect(error.message, 'price must be between 1 cent and \$1,000,000');
      }
      await h.ok(
        UpdateItem(itemId: ItemId(itemId), unitPrice: Money.fromCents(1)),
      );
      await h.ok(
        UpdateItem(
          itemId: ItemId(itemId),
          unitPrice: Money.fromCents(100000000),
        ),
      );
      expect((await h.itemRow(itemId)).unitPriceCents, 100000000);
    });
  });

  group('CatalogService', () {
    late DriftCatalogService catalog;

    setUp(() {
      catalog = DriftCatalogService(
        h.db,
        h.applier,
        idGenerator: h.ids,
        clock: h.clock,
      );
    });

    test('the draft carries the price: create stores it, whole-state '
        'update clears it when null', () async {
      final created = await catalog.createItem(
        ItemDraft(name: 'Buns', unitPrice: Money.fromCents(1250)),
      );
      final itemId = created.fold((id) => id, (e) => fail(e.message));
      expect((await h.itemRow(itemId)).unitPriceCents, 1250);

      // The form always submits its complete state: a draft without a price
      // CLEARS the stored one, exactly as unitLabel and servesPerUnit do.
      (await catalog.updateItem(
        itemId: itemId,
        draft: const ItemDraft(name: 'Buns'),
      )).fold((_) {}, (e) => fail(e.message));
      expect((await h.itemRow(itemId)).unitPriceCents, isNull);

      // And a draft with one sets it again.
      (await catalog.updateItem(
        itemId: itemId,
        draft: ItemDraft(name: 'Buns', unitPrice: Money.fromCents(99)),
      )).fold((_) {}, (e) => fail(e.message));
      expect((await h.itemRow(itemId)).unitPriceCents, 99);
    });

    test('the read model maps unit_price_cents onto Item.unitPrice', () async {
      await catalog.createItem(
        ItemDraft(name: 'Buns', unitPrice: Money.fromCents(1250)),
      );
      await catalog.createItem(const ItemDraft(name: 'Rolls'));
      final sections = await catalog.watchFoldersWithItems().first;
      final items = [for (final s in sections) ...s.items];
      expect(
        items.singleWhere((i) => i.item.name == 'Buns').item.unitPrice,
        Money.fromCents(1250),
      );
      expect(
        items.singleWhere((i) => i.item.name == 'Rolls').item.unitPrice,
        isNull,
      );
    });
  });

  group('SQL backstop', () {
    test('the CHECK bounds hostile writes on items too', () async {
      final itemId = await h.createItem(name: 'Buns');
      await h.db.customStatement(
        'UPDATE items SET unit_price_cents = 100000000 WHERE id = ?',
        [itemId],
      );
      for (final bad in [0, -1, 100000001]) {
        await expectLater(
          h.db.customStatement(
            'UPDATE items SET unit_price_cents = ? WHERE id = ?',
            [bad, itemId],
          ),
          throwsA(anything),
          reason: '$bad cents is outside the CHECK range',
        );
      }
      // NULL stays legal: unpriced items carry no price.
      await h.db.customStatement(
        'UPDATE items SET unit_price_cents = NULL WHERE id = ?',
        [itemId],
      );
    });
  });
}
