/// §11.1 family F (catalog write path, schema v6): an item learns its
/// barcode. The barcode is the RAW payload string exactly as the scan
/// detector delivered it — stored verbatim, compared verbatim, never
/// interpreted — and unique among LIVE items only: archiving an item frees
/// its barcode for a future item, exactly as it frees the name.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';

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

  group('create', () {
    test(
      'a scanned payload is stored verbatim; unscanned stays NULL',
      () async {
        final scanned = await h.ok(
          const CreateItem(name: 'Buns', barcode: ' 5000112637922 '),
        );
        final plain = await h.ok(const CreateItem(name: 'Rolls'));
        expect(
          (await h.itemRow(scanned.createdRecordIds.first)).barcode,
          ' 5000112637922 ',
          reason: 'raw payload byte for byte — never trimmed or normalized',
        );
        expect((await h.itemRow(plain.createdRecordIds.first)).barcode, isNull);
      },
    );

    test('a payload another LIVE item carries is rejected', () async {
      await h.ok(const CreateItem(name: 'Buns', barcode: '5000112637922'));
      final error = await h.err(
        const CreateItem(name: 'Rolls', barcode: '5000112637922'),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, 'another item already has this barcode');
      expect(await h.count('items'), 1, reason: 'the duplicate never landed');
    });

    test('comparison is verbatim: differently-cased payloads are two '
        'different barcodes', () async {
      await h.ok(const CreateItem(name: 'Buns', barcode: 'CODE-abc'));
      await h.ok(const CreateItem(name: 'Rolls', barcode: 'code-ABC'));
      expect(await h.count('items'), 2);
    });

    test('archiving the holder frees the payload for a future item', () async {
      final receipt = await h.ok(
        const CreateItem(name: 'Buns', barcode: '5000112637922'),
      );
      await h.ok(
        SetItemArchived(
          itemId: ItemId(receipt.createdRecordIds.first),
          archived: true,
        ),
      );
      await h.ok(const CreateItem(name: 'Rolls', barcode: '5000112637922'));
      expect(await h.count('items'), 2);
    });

    test('bounds: 1-64 characters once trimmed, and 64 is legal', () async {
      for (final bad in ['', '   ', 'x' * 65]) {
        final error = await h.err(CreateItem(name: 'Buns', barcode: bad));
        expect(error, isA<ValidationError>());
        expect(error.message, 'barcode must be 1-64 characters');
      }
      expect(await h.count('items'), 0);
      await h.ok(CreateItem(name: 'Buns', barcode: 'x' * 64));
    });
  });

  group('update', () {
    test('sets, re-sets, leaves alone, and clears', () async {
      final itemId = await h.createItem(name: 'Buns');
      await h.ok(UpdateItem(itemId: ItemId(itemId), barcode: '5000112637922'));
      expect((await h.itemRow(itemId)).barcode, '5000112637922');

      // A re-scan replaces the payload.
      await h.ok(UpdateItem(itemId: ItemId(itemId), barcode: '4088600550862'));
      expect((await h.itemRow(itemId)).barcode, '4088600550862');

      // An unrelated update leaves the barcode alone.
      await h.ok(UpdateItem(itemId: ItemId(itemId), name: 'Brioche buns'));
      expect((await h.itemRow(itemId)).barcode, '4088600550862');

      // clearBarcode erases it.
      await h.ok(UpdateItem(itemId: ItemId(itemId), clearBarcode: true));
      expect((await h.itemRow(itemId)).barcode, isNull);
    });

    test('a payload another LIVE item carries is rejected; re-sending your '
        'own is fine', () async {
      final holder = await h.ok(
        const CreateItem(name: 'Buns', barcode: '5000112637922'),
      );
      final itemId = await h.createItem(name: 'Rolls');
      final error = await h.err(
        UpdateItem(itemId: ItemId(itemId), barcode: '5000112637922'),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, 'another item already has this barcode');
      expect((await h.itemRow(itemId)).barcode, isNull);

      // The holder re-scanning its own payload is not a collision.
      await h.ok(
        UpdateItem(
          itemId: ItemId(holder.createdRecordIds.first),
          barcode: '5000112637922',
        ),
      );
    });

    test('barcode and clearBarcode together are rejected', () async {
      final itemId = await h.createItem(name: 'Buns');
      final error = await h.err(
        UpdateItem(
          itemId: ItemId(itemId),
          barcode: '5000112637922',
          clearBarcode: true,
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, 'set a barcode or clear it, not both');
      expect((await h.itemRow(itemId)).barcode, isNull);
    });

    test('bounds apply on update too', () async {
      final itemId = await h.createItem(name: 'Buns');
      final error = await h.err(
        UpdateItem(itemId: ItemId(itemId), barcode: 'x' * 65),
      );
      expect(error.message, 'barcode must be 1-64 characters');
    });
  });

  group('unarchive', () {
    test('blocked while a live item carries the stored payload; clearing '
        'the newcomer unblocks it', () async {
      final first = await h.ok(
        const CreateItem(name: 'Buns', barcode: '5000112637922'),
      );
      final firstId = first.createdRecordIds.first;
      await h.ok(SetItemArchived(itemId: ItemId(firstId), archived: true));

      // A future item claimed the freed payload…
      final second = await h.ok(
        const CreateItem(name: 'Rolls', barcode: '5000112637922'),
      );

      // …so the archived holder cannot come back carrying it.
      final error = await h.err(
        SetItemArchived(itemId: ItemId(firstId), archived: false),
      );
      expect(error, isA<ValidationError>());
      expect(
        error.message,
        'another item already has this barcode; clear it first',
      );

      // Clearing the newcomer's barcode unblocks the unarchive.
      await h.ok(
        UpdateItem(
          itemId: ItemId(second.createdRecordIds.first),
          clearBarcode: true,
        ),
      );
      await h.ok(SetItemArchived(itemId: ItemId(firstId), archived: false));
      expect((await h.itemRow(firstId)).barcode, '5000112637922');
    });
  });

  group('CatalogService', () {
    test('itemByBarcode finds LIVE items only, by exact payload', () async {
      final receipt = await h.ok(
        const CreateItem(name: 'Buns', barcode: '5000112637922'),
      );
      final itemId = receipt.createdRecordIds.first;

      final found = await catalog.itemByBarcode('5000112637922');
      expect(found, isNotNull);
      expect(found!.id as String, itemId);
      expect(found.barcode, '5000112637922');

      // Near-misses never match: verbatim comparison, no normalization.
      expect(await catalog.itemByBarcode(' 5000112637922'), isNull);
      expect(await catalog.itemByBarcode('5000112637921'), isNull);

      // Archived items never match — and a future live item with the freed
      // payload is the one that does.
      await h.ok(SetItemArchived(itemId: ItemId(itemId), archived: true));
      expect(await catalog.itemByBarcode('5000112637922'), isNull);
      final successor = await h.ok(
        const CreateItem(name: 'Rolls', barcode: '5000112637922'),
      );
      final refound = await catalog.itemByBarcode('5000112637922');
      expect(refound!.id as String, successor.createdRecordIds.first);
    });

    test(
      'setItemBarcode assigns through the write path; null clears',
      () async {
        final itemId = await h.createItem(name: 'Buns');
        (await catalog.setItemBarcode(
          itemId: itemId,
          barcode: '5000112637922',
        )).fold((_) {}, (e) => fail(e.message));
        expect((await h.itemRow(itemId)).barcode, '5000112637922');

        (await catalog.setItemBarcode(
          itemId: itemId,
          barcode: null,
        )).fold((_) {}, (e) => fail(e.message));
        expect((await h.itemRow(itemId)).barcode, isNull);
      },
    );

    test('setItemBarcode surfaces the duplicate rejection', () async {
      await h.ok(const CreateItem(name: 'Buns', barcode: '5000112637922'));
      final itemId = await h.createItem(name: 'Rolls');
      final result = await catalog.setItemBarcode(
        itemId: itemId,
        barcode: '5000112637922',
      );
      result.fold(
        (_) => fail('expected the duplicate to be rejected'),
        (e) => expect(e.message, 'another item already has this barcode'),
      );
    });
  });

  group('SQL backstop', () {
    test('a fresh database carries uidx_items_barcode_live', () async {
      final index = await h.db
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE name = 'uidx_items_barcode_live'",
          )
          .get();
      expect(index, hasLength(1));
    });

    test('the live-uniqueness index and the 1-64 CHECK hold even against '
        'raw SQL', () async {
      final a = await h.createItem(name: 'Buns');
      final b = await h.createItem(name: 'Rolls');
      await h.db.customStatement(
        "UPDATE items SET barcode = '5000112637922' WHERE id = ?",
        [a],
      );
      await expectLater(
        h.db.customStatement(
          "UPDATE items SET barcode = '5000112637922' WHERE id = ?",
          [b],
        ),
        throwsA(anything),
        reason: 'two LIVE items may never share one payload',
      );
      await expectLater(
        h.db.customStatement('UPDATE items SET barcode = ? WHERE id = ?', [
          'x' * 65,
          b,
        ]),
        throwsA(anything),
        reason: 'the CHECK bounds hostile writes too',
      );
    });
  });
}
