/// Schema v3 folders through the single write path: create / rename /
/// reorder / archive / set-basis / move, the invariants around them (a
/// rename can never orphan an item; archiving a folder moves its items to
/// Unfiled and deletes nothing), the item-side cold-start fields, and the
/// service surfaces that read them (sectioned catalog, always-planned
/// auto-add, clone-from-event prefill).
///
/// A fresh database seeds the eight starter folders, so every expectation
/// here counts from that baseline — exactly what a fresh workspace has.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/folder_appearance.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/unit_ratio.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/events/application/event_service.dart';
import 'package:loadout/features/events/domain/event.dart';

import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;
  late DriftCatalogService catalog;
  late DriftEventService events;

  setUp(() {
    h = WritePathHarness();
    catalog = DriftCatalogService(
      h.db,
      h.applier,
      idGenerator: h.ids,
      clock: h.clock,
    );
    events = DriftEventService(
      h.db,
      h.applier,
      idGenerator: h.ids,
      clock: h.clock,
    );
  });

  tearDown(() => h.close());

  Future<List<String>> liveFolderIdsInOrder() async => [
    for (final f in await h.db.folderDao.live()) f.id,
  ];

  group('CreateFolder', () {
    test('appends after the starters and returns the id', () async {
      final receipt = await h.ok(
        const CreateFolder(
          name: 'Van shelf',
          demandBasis: DemandBasis.perEvent,
        ),
      );
      final id = receipt.createdRecordIds.single;
      final row = (await h.db.folderDao.byId(id))!;
      expect(row.name, 'Van shelf');
      expect(row.position, 8, reason: 'after the eight starters');
      expect(row.demandBasis, 'per_event');
      expect(row.alwaysPlanned, isFalse);
      expect(
        (await h.commandRow(receipt.commandId as String)).kind,
        'CreateFolder',
      );
    });

    test('refuses a live duplicate name, case-insensitively', () async {
      final error = await h.err(
        const CreateFolder(name: 'drinks', demandBasis: DemandBasis.perPerson),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('already exists'));
    });

    test('an archived folder frees its name', () async {
      final created = await h.ok(
        const CreateFolder(name: 'Extras', demandBasis: DemandBasis.perPerson),
      );
      await h.ok(ArchiveFolder(FolderId(created.createdRecordIds.single)));
      final again = await h.ok(
        const CreateFolder(name: 'extras', demandBasis: DemandBasis.perEvent),
      );
      expect(
        again.createdRecordIds.single,
        isNot(created.createdRecordIds.single),
      );
    });

    test('name length is validated', () async {
      expect(
        await h.err(
          const CreateFolder(name: '  ', demandBasis: DemandBasis.perPerson),
        ),
        isA<ValidationError>(),
      );
      expect(
        await h.err(
          CreateFolder(name: 'x' * 61, demandBasis: DemandBasis.perPerson),
        ),
        isA<ValidationError>(),
      );
    });
  });

  group('RenameFolder', () {
    test(
      'renames in place; filed items keep pointing at it (FK, not text)',
      () async {
        final ids = await liveFolderIdsInOrder();
        final drinks = ids[4]; // 'Drinks'
        final itemId = await h.createItem(name: 'Water');
        await h.ok(
          MoveItemToFolder(itemId: ItemId(itemId), folderId: FolderId(drinks)),
        );

        await h.ok(RenameFolder(folderId: FolderId(drinks), name: 'Beverages'));

        expect((await h.db.folderDao.byId(drinks))!.name, 'Beverages');
        expect(
          (await h.itemRow(itemId)).folderId,
          drinks,
          reason: 'a rename can never orphan an item',
        );
      },
    );

    test('refuses a name a different live folder holds', () async {
      final ids = await liveFolderIdsInOrder();
      final error = await h.err(
        RenameFolder(folderId: FolderId(ids[0]), name: 'BAKERY'),
      );
      expect(error.message, contains('already exists'));
    });

    test(
      'renaming a folder to its own name (case change) is allowed',
      () async {
        final ids = await liveFolderIdsInOrder();
        await h.ok(RenameFolder(folderId: FolderId(ids[4]), name: 'DRINKS'));
        expect((await h.db.folderDao.byId(ids[4]))!.name, 'DRINKS');
      },
    );
  });

  group('ReorderFolders', () {
    test('a full permutation becomes the new position order', () async {
      final ids = await liveFolderIdsInOrder();
      final reversed = ids.reversed.toList();
      await h.ok(ReorderFolders([for (final id in reversed) FolderId(id)]));
      expect(await liveFolderIdsInOrder(), reversed);
    });

    test('a partial list is rejected — no folder may be forgotten', () async {
      final ids = await liveFolderIdsInOrder();
      final error = await h.err(
        ReorderFolders([for (final id in ids.take(3)) FolderId(id)]),
      );
      expect(error.message, contains('every live folder exactly once'));
    });

    test('duplicates are rejected', () async {
      final ids = await liveFolderIdsInOrder();
      final error = await h.err(
        ReorderFolders([
          for (final id in ids.take(ids.length - 1)) FolderId(id),
          FolderId(ids.first),
        ]),
      );
      expect(error, isA<ValidationError>());
    });
  });

  group('ArchiveFolder', () {
    test(
      'stamps the folder and moves its items to Unfiled — nothing deleted',
      () async {
        final ids = await liveFolderIdsInOrder();
        final cleaning = ids[6]; // 'Cleaning & setup'
        final soap = await h.createItem(name: 'Dish soap');
        final scrubbers = await h.createItem(name: 'Scrubbers');
        await h.ok(
          MoveItemsToFolder(
            itemIds: [ItemId(soap), ItemId(scrubbers)],
            folderId: FolderId(cleaning),
          ),
        );

        await h.ok(ArchiveFolder(FolderId(cleaning)));

        final folder = (await h.db.folderDao.byId(cleaning))!;
        expect(folder.archivedAtMicros, isNotNull);
        expect((await h.itemRow(soap)).folderId, isNull);
        expect((await h.itemRow(scrubbers)).folderId, isNull);
        expect(await h.count('items'), 2, reason: 'never deletes items');
        expect(await liveFolderIdsInOrder(), hasLength(7));
      },
    );

    test(
      'archiving twice is rejected; archived folders refuse writes',
      () async {
        final ids = await liveFolderIdsInOrder();
        await h.ok(ArchiveFolder(FolderId(ids[0])));
        expect(
          (await h.err(ArchiveFolder(FolderId(ids[0])))).message,
          contains('already archived'),
        );
        expect(
          await h.err(RenameFolder(folderId: FolderId(ids[0]), name: 'X')),
          isA<ValidationError>(),
        );
        expect(
          await h.err(
            SetFolderBasis(
              folderId: FolderId(ids[0]),
              demandBasis: DemandBasis.perEvent,
            ),
          ),
          isA<ValidationError>(),
        );
      },
    );

    test('an unknown folder is NotFound', () async {
      expect(
        await h.err(ArchiveFolder(FolderId('F'.padRight(26, '0')))),
        isA<NotFoundError>(),
      );
    });
  });

  group('SetFolderBasis', () {
    test(
      'updates basis, always-planned, or both; neither is rejected',
      () async {
        final ids = await liveFolderIdsInOrder();
        await h.ok(
          SetFolderBasis(
            folderId: FolderId(ids[5]),
            demandBasis: DemandBasis.perEvent,
          ),
        );
        expect((await h.db.folderDao.byId(ids[5]))!.demandBasis, 'per_event');

        await h.ok(
          SetFolderBasis(folderId: FolderId(ids[5]), alwaysPlanned: true),
        );
        final row = (await h.db.folderDao.byId(ids[5]))!;
        expect(row.alwaysPlanned, isTrue);
        expect(row.demandBasis, 'per_event', reason: 'left alone');

        expect(
          (await h.err(SetFolderBasis(folderId: FolderId(ids[5])))).message,
          contains('set the demand basis'),
        );
      },
    );
  });

  group('folder appearance (v4)', () {
    test('CreateFolder stores the chosen hue and icon; the entity reads them '
        'back typed', () async {
      final receipt = await h.ok(
        const CreateFolder(
          name: 'Van shelf',
          demandBasis: DemandBasis.perEvent,
          hue: FolderHue.lake,
          iconName: 'shopping_basket',
        ),
      );
      final id = receipt.createdRecordIds.single;
      final row = (await h.db.folderDao.byId(id))!;
      expect(row.hueName, 'lake');
      expect(row.iconName, 'shopping_basket');

      final folders = await catalog.watchFolders().first;
      final entity = folders.singleWhere((f) => f.id as String == id);
      expect(entity.hue, FolderHue.lake);
      expect(entity.iconName, 'shopping_basket');
      expect(entity.effectiveHue, FolderHue.lake);
      expect(entity.effectiveIconName, 'shopping_basket');
    });

    test('CreateFolder refuses an icon outside the curated grid', () async {
      final error = await h.err(
        const CreateFolder(
          name: 'Van shelf',
          demandBasis: DemandBasis.perPerson,
          iconName: 'rocket_launch',
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('curated'));
    });

    test('SetFolderAppearance updates hue, icon, or both; each leaves the '
        'other alone', () async {
      final ids = await liveFolderIdsInOrder();
      final drinks = ids[4]; // 'Drinks': lake + local_drink from the seed
      await h.ok(
        SetFolderAppearance(folderId: FolderId(drinks), hue: FolderHue.plum),
      );
      var row = (await h.db.folderDao.byId(drinks))!;
      expect(row.hueName, 'plum');
      expect(row.iconName, 'local_drink', reason: 'left alone');

      await h.ok(
        SetFolderAppearance(folderId: FolderId(drinks), iconName: 'liquor'),
      );
      row = (await h.db.folderDao.byId(drinks))!;
      expect(row.hueName, 'plum', reason: 'left alone');
      expect(row.iconName, 'liquor');

      final receipt = await h.ok(
        SetFolderAppearance(
          folderId: FolderId(drinks),
          hue: FolderHue.honey,
          iconName: 'coffee',
        ),
      );
      row = (await h.db.folderDao.byId(drinks))!;
      expect(row.hueName, 'honey');
      expect(row.iconName, 'coffee');
      expect(
        (await h.commandRow(receipt.commandId as String)).kind,
        'SetFolderAppearance',
      );
    });

    test('SetFolderAppearance rejects neither-set, a non-curated icon, an '
        'archived folder, and an unknown folder', () async {
      final ids = await liveFolderIdsInOrder();
      expect(
        (await h.err(SetFolderAppearance(folderId: FolderId(ids[0])))).message,
        contains('set the hue'),
      );
      expect(
        (await h.err(
          SetFolderAppearance(folderId: FolderId(ids[0]), iconName: 'pets'),
        )).message,
        contains('curated'),
      );
      await h.ok(ArchiveFolder(FolderId(ids[0])));
      expect(
        (await h.err(
          SetFolderAppearance(folderId: FolderId(ids[0]), hue: FolderHue.fern),
        )).message,
        contains('archived'),
      );
      expect(
        await h.err(
          SetFolderAppearance(
            folderId: FolderId('F'.padRight(26, '0')),
            hue: FolderHue.fern,
          ),
        ),
        isA<NotFoundError>(),
      );
    });

    test('a folder that never chose renders the effective defaults: hue by '
        'position order, icon by starter name else inventory_2', () async {
      // Ninth folder, no appearance: position 8 wraps to the first hue.
      final created = await h.ok(
        const CreateFolder(
          name: 'Van shelf',
          demandBasis: DemandBasis.perEvent,
        ),
      );
      final id = created.createdRecordIds.single;
      final row = (await h.db.folderDao.byId(id))!;
      expect(row.hueName, isNull);
      expect(row.iconName, isNull);
      var folders = await catalog.watchFolders().first;
      final bare = folders.singleWhere((f) => f.id as String == id);
      expect(bare.effectiveHue, FolderHue.byPosition(8));
      expect(bare.effectiveHue, FolderHue.fern, reason: 'position 8 wraps');
      expect(bare.effectiveIconName, fallbackFolderIconName);

      // A bare folder carrying a starter NAME gets the starter icon —
      // case-insensitively, the way a migrated tidy-up folder would.
      final ids = await liveFolderIdsInOrder();
      await h.ok(ArchiveFolder(FolderId(ids[4]))); // frees 'Drinks'
      final drinks = await h.ok(
        const CreateFolder(name: 'drinks', demandBasis: DemandBasis.perPerson),
      );
      folders = await catalog.watchFolders().first;
      final revived = folders.singleWhere(
        (f) => f.id as String == drinks.createdRecordIds.single,
      );
      expect(revived.effectiveIconName, 'local_drink');
    });

    test(
      'the service surface threads appearance through create and set',
      () async {
        final created = await catalog.createFolder(
          name: 'Merch',
          demandBasis: DemandBasis.perPerson,
          hue: FolderHue.berry,
          iconName: 'sell',
        );
        final id = created.fold((v) => v, (e) => fail(e.message));
        var row = (await h.db.folderDao.byId(id))!;
        expect(row.hueName, 'berry');
        expect(row.iconName, 'sell');

        final set = await catalog.setFolderAppearance(
          folderId: id,
          hue: FolderHue.stone,
        );
        set.fold((_) {}, (e) => fail(e.message));
        row = (await h.db.folderDao.byId(id))!;
        expect(row.hueName, 'stone');
        expect(row.iconName, 'sell');
      },
    );
  });

  group('moving items', () {
    test(
      'single and batch moves write folder_id; null means Unfiled',
      () async {
        final ids = await liveFolderIdsInOrder();
        final a = await h.createItem(name: 'A');
        final b = await h.createItem(name: 'B');

        await h.ok(
          MoveItemsToFolder(
            itemIds: [ItemId(a), ItemId(b)],
            folderId: FolderId(ids[1]),
          ),
        );
        expect((await h.itemRow(a)).folderId, ids[1]);
        expect((await h.itemRow(b)).folderId, ids[1]);

        await h.ok(MoveItemToFolder(itemId: ItemId(a)));
        expect((await h.itemRow(a)).folderId, isNull);
        expect((await h.itemRow(b)).folderId, ids[1]);
      },
    );

    test('rejects archived items, archived folders, duplicates, and an empty '
        'batch', () async {
      final ids = await liveFolderIdsInOrder();
      final a = await h.createItem(name: 'A');
      await h.ok(SetItemArchived(itemId: ItemId(a), archived: true));
      expect(
        await h.err(
          MoveItemToFolder(itemId: ItemId(a), folderId: FolderId(ids[0])),
        ),
        isA<ValidationError>(),
      );

      final b = await h.createItem(name: 'B');
      await h.ok(ArchiveFolder(FolderId(ids[0])));
      expect(
        (await h.err(
          MoveItemToFolder(itemId: ItemId(b), folderId: FolderId(ids[0])),
        )).message,
        contains('archived'),
      );
      expect(
        await h.err(MoveItemsToFolder(itemIds: [ItemId(b), ItemId(b)])),
        isA<ValidationError>(),
      );
      expect(
        (await h.err(const MoveItemsToFolder(itemIds: []))).message,
        contains('at least one item'),
      );
    });
  });

  group('item cold-start fields (v3)', () {
    test(
      'create stores folder, basis override, usual amount, and ratio',
      () async {
        final ids = await liveFolderIdsInOrder();
        final receipt = await h.ok(
          CreateItem(
            name: 'Napkins',
            folderId: FolderId(ids[5]),
            demandBasis: DemandBasis.perPerson,
            perPersonRatio: UnitRatio(3, 1),
          ),
        );
        final napkins = await h.itemRow(receipt.createdRecordIds.first);
        expect(napkins.folderId, ids[5]);
        expect(napkins.demandBasis, 'per_person');
        expect(napkins.perPersonNumerator, 3);
        expect(napkins.perPersonDenominator, 1);
        expect(napkins.servesPerUnitMicros, isNull);

        final soap = await h.ok(
          CreateItem(
            name: 'Dish soap',
            demandBasis: DemandBasis.perEvent,
            perEventBaseline: Quantity.whole(2),
          ),
        );
        final soapRow = await h.itemRow(soap.createdRecordIds.first);
        expect(soapRow.demandBasis, 'per_event');
        expect(soapRow.perEventBaselineMicros, 2000000);
      },
    );

    test('"1 serves N" and "N per person" are mutually exclusive — on create '
        'and as an update post-state', () async {
      expect(
        (await h.err(
          CreateItem(
            name: 'Confused',
            servesPerUnit: Quantity.whole(4),
            perPersonRatio: UnitRatio(3, 1),
          ),
        )).message,
        contains('not both'),
      );

      final id = await h.createItem(
        name: 'Rolls',
        servesPerUnitMicros: 2000000,
      );
      // Adding a ratio WITHOUT clearing the stored serves is the dishonest
      // post-state the validator must catch.
      expect(
        (await h.err(
          UpdateItem(itemId: ItemId(id), perPersonRatio: UnitRatio(1, 2)),
        )).message,
        contains('not both'),
      );
      // Clearing serves in the same command is fine.
      await h.ok(
        UpdateItem(
          itemId: ItemId(id),
          perPersonRatio: UnitRatio(1, 2),
          clearServesPerUnit: true,
        ),
      );
      final row = await h.itemRow(id);
      expect(row.servesPerUnitMicros, isNull);
      expect(row.perPersonNumerator, 1);
      expect(row.perPersonDenominator, 2);
    });

    test('field ranges are validated', () async {
      expect(
        await h.err(CreateItem(name: 'X', perEventBaseline: Quantity.zero)),
        isA<ValidationError>(),
      );
      expect(
        await h.err(
          CreateItem(
            name: 'X',
            perEventBaseline: Quantity.fromMicros(1000000000000 + 1),
          ),
        ),
        isA<ValidationError>(),
      );
      expect(
        await h.err(CreateItem(name: 'X', perPersonRatio: UnitRatio(10001, 1))),
        isA<ValidationError>(),
      );
      expect(
        await h.err(
          CreateItem(name: 'X', folderId: FolderId('F'.padRight(26, '0'))),
        ),
        isA<NotFoundError>(),
      );
    });

    test(
      'the service update clears whatever the complete draft omits',
      () async {
        final ids = await liveFolderIdsInOrder();
        final created = await catalog.createItem(
          ItemDraft(
            name: 'Soap',
            folderId: ids[6],
            demandBasis: DemandBasis.perEvent,
            perEventBaseline: Quantity.whole(2),
          ),
        );
        final id = created.fold((v) => v, (e) => fail(e.message));

        // Resubmitting the form without the override or baseline erases both
        // and refiles under Unfiled — the form always submits its whole state.
        final updated = await catalog.updateItem(
          itemId: id,
          draft: const ItemDraft(name: 'Soap'),
        );
        updated.fold((_) {}, (e) => fail(e.message));
        final row = await h.itemRow(id);
        expect(row.folderId, isNull);
        expect(row.demandBasis, isNull);
        expect(row.perEventBaselineMicros, isNull);
      },
    );
  });

  group('CatalogService folder reads', () {
    test('watchFoldersWithItems: folder order, items by name, Unfiled last '
        'and only when occupied', () async {
      final ids = await liveFolderIdsInOrder();
      final water = await h.createItem(name: 'Water');
      final cola = await h.createItem(name: 'Cola');
      await h.ok(
        MoveItemsToFolder(
          itemIds: [ItemId(water), ItemId(cola)],
          folderId: FolderId(ids[4]), // Drinks
        ),
      );

      var sections = await catalog.watchFoldersWithItems().first;
      expect(sections, hasLength(8), reason: 'nothing unfiled yet');
      expect(sections[4].folder!.name, 'Drinks');
      expect(
        [for (final s in sections[4].items) s.item.name],
        ['Cola', 'Water'],
      );
      expect(sections.every((s) => !s.isUnfiled), isTrue);

      final stray = await h.createItem(name: 'Mystery box');
      sections = await catalog.watchFoldersWithItems().first;
      expect(sections, hasLength(9));
      expect(sections.last.isUnfiled, isTrue);
      expect(sections.last.items.single.item.name, 'Mystery box');
      expect(sections.last.items.single.item.id as String, stray);
    });

    test('archived items leave the sectioned list', () async {
      final id = await h.createItem(name: 'Old thing');
      await h.ok(SetItemArchived(itemId: ItemId(id), archived: true));
      final sections = await catalog.watchFoldersWithItems().first;
      expect(sections.any((s) => s.isUnfiled), isFalse);
    });

    test('watchFolders is live folders in the owner\'s order', () async {
      final folders = await catalog.watchFolders().first;
      expect(folders, hasLength(8));
      expect(folders.first.name, 'Cooked on site');
      expect(folders.last.name, 'Sales table');
      expect(folders[6].demandBasis, DemandBasis.perEvent);
    });
  });

  group('EventService and always-planned folders', () {
    test('event creation pre-adds live items of always-planned folders after '
        'the owner\'s picks', () async {
      final ids = await liveFolderIdsInOrder();
      final soap = await h.createItem(name: 'Dish soap');
      final towels = await h.createItem(name: 'Paper towels');
      final gone = await h.createItem(name: 'Broken mop');
      await h.ok(
        MoveItemsToFolder(
          itemIds: [ItemId(soap), ItemId(towels), ItemId(gone)],
          folderId: FolderId(ids[6]), // Cleaning & setup
        ),
      );
      await h.ok(SetItemArchived(itemId: ItemId(gone), archived: true));
      await h.ok(
        SetFolderBasis(folderId: FolderId(ids[6]), alwaysPlanned: true),
      );
      final cookies = await h.createItem(name: 'Cookies');

      final created = await events.createEvent(
        EventDraft(
          name: 'Fair',
          scheduledDate: '2026-09-01',
          plannedExposure: 200,
          plannedItemIds: [cookies],
        ),
      );
      final eventId = created.fold((v) => v, (e) => fail(e.message));
      final planned = await h.db.eventDao.plannedItems(eventId);
      expect(
        [for (final p in planned) p.itemId],
        [cookies, soap, towels],
        reason:
            'owner picks first, then the standing stuff by name; the '
            'archived mop stays out',
      );
    });

    test('an always-planned item already picked is not added twice', () async {
      final ids = await liveFolderIdsInOrder();
      final soap = await h.createItem(name: 'Dish soap');
      await h.ok(
        MoveItemToFolder(itemId: ItemId(soap), folderId: FolderId(ids[6])),
      );
      await h.ok(
        SetFolderBasis(folderId: FolderId(ids[6]), alwaysPlanned: true),
      );
      final created = await events.createEvent(
        EventDraft(
          name: 'Fair',
          scheduledDate: '2026-09-01',
          plannedItemIds: [soap],
        ),
      );
      final eventId = created.fold((v) => v, (e) => fail(e.message));
      expect(await h.db.eventDao.plannedItems(eventId), hasLength(1));
    });

    test(
      'clonePlannedItemsFrom returns the live planned items in order',
      () async {
        final a = await h.createItem(name: 'A');
        final b = await h.createItem(name: 'B');
        final c = await h.createItem(name: 'C');
        final eventId = await h.createEvent(
          name: 'Last month',
          plannedItemIds: [c, a, b],
        );
        await h.ok(SetItemArchived(itemId: ItemId(a), archived: true));
        expect(await events.clonePlannedItemsFrom(eventId), [c, b]);
      },
    );
  });
}
