/// THE OWNER'S REPRO (2026-08-15 feedback #1): moving an item to another
/// folder must work even when that item is the ONLY one in its folder — she
/// tried and failed on her phone. This drives the move through the REAL
/// service surfaces, both ways the UI can express it:
///
///  * `CatalogService.moveItemToFolder` (the dedicated move command), and
///  * `CatalogService.updateItem` (the edit form's resubmit path, whose
///    null-folder draft CLEARS the folder by design).
///
/// If everything here passes, the phone bug is NOT in data/domain/
/// application — the items screen's own flow is where it lives.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/catalog/domain/item.dart';

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

  T unwrap<T>(Result<T> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final error) => fail(
      'expected Ok, got ${error.code}: '
      '${error.message}',
    ),
  };

  Future<String?> folderOf(String itemId) async =>
      (await h.itemRow(itemId)).folderId;

  /// The seeded starter folder with [name] — exactly what the phone has.
  Future<String> starterFolder(String name) async {
    final folders = await catalog.watchFolders().first;
    return folders.firstWhere((folder) => folder.name == name).id.value;
  }

  test('a folder\'s ONLY item moves to another folder, then to Unfiled, '
      'through moveItemToFolder', () async {
    final folderA = await starterFolder('Drinks');
    final folderB = await starterFolder('Bakery');
    final itemId = unwrap(
      await catalog.createItem(
        const ItemDraft(name: 'Cola', folderId: null),
        openingCount: Quantity.whole(3),
      ),
    );
    // Make it the ONLY item in folder A.
    unwrap(await catalog.moveItemToFolder(itemId: itemId, folderId: folderA));
    expect(await folderOf(itemId), folderA);

    // The reported failure: sole occupant → another folder.
    unwrap(await catalog.moveItemToFolder(itemId: itemId, folderId: folderB));
    expect(await folderOf(itemId), folderB);

    // And sole occupant → Unfiled (null).
    unwrap(await catalog.moveItemToFolder(itemId: itemId, folderId: null));
    expect(await folderOf(itemId), isNull);

    // The sectioned stream agrees: A and B render empty, Cola is Unfiled.
    final sections = await catalog.watchFoldersWithItems().first;
    final byName = {
      for (final section in sections)
        section.folder?.name ?? 'Unfiled': section.items,
    };
    expect(byName['Drinks'], isEmpty);
    expect(byName['Bakery'], isEmpty);
    expect(byName['Unfiled']!.single.item.name, 'Cola');
  });

  test('the same moves work through the edit form\'s resubmit path '
      '(updateItem with the complete draft)', () async {
    final folderA = await starterFolder('Drinks');
    final folderB = await starterFolder('Bakery');
    final itemId = unwrap(
      await catalog.createItem(ItemDraft(name: 'Cola', folderId: folderA)),
    );
    expect(await folderOf(itemId), folderA);

    // The form resubmits its COMPLETE state; only the folder changes.
    unwrap(
      await catalog.updateItem(
        itemId: itemId,
        draft: ItemDraft(name: 'Cola', folderId: folderB),
      ),
    );
    expect(await folderOf(itemId), folderB);

    // Null folder in the draft = move to Unfiled (clears by design).
    unwrap(
      await catalog.updateItem(
        itemId: itemId,
        draft: const ItemDraft(name: 'Cola', folderId: null),
      ),
    );
    expect(await folderOf(itemId), isNull);
  });

  test('moving the sole item into an ARCHIVED folder is the one legal '
      'refusal, and it is a plain error', () async {
    final folderA = await starterFolder('Drinks');
    final itemId = unwrap(
      await catalog.createItem(ItemDraft(name: 'Cola', folderId: folderA)),
    );
    final folderB = unwrap(
      await catalog.createFolder(
        name: 'Old shelf',
        demandBasis: DemandBasis.perEvent,
      ),
    );
    unwrap(await catalog.archiveFolder(folderB));
    final result = await catalog.moveItemToFolder(
      itemId: itemId,
      folderId: folderB,
    );
    expect(result, isA<Err<void>>());
    expect(await folderOf(itemId), folderA, reason: 'unmoved');
  });
}
