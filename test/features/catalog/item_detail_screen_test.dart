/// §11.3 ItemDetailScreen widget tests: derived on-hand stat, day-grouped
/// movement history (corrected rows struck through, never hidden),
/// archive/unarchive via the menu, quick record-movement links.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/folder_chip.dart';
import 'package:loadout/app/widgets/warning_banner.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/approval/domain/proposal.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_detail_screen.dart';
import 'package:loadout/features/catalog/presentation/item_list_screen.dart';
import 'package:loadout/features/catalog/presentation/unfiled_chip.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/inventory/presentation/movement_entry_screen.dart';

import '../../support/app_harness.dart';

Future<String> seedItem(
  AppHarness h, {
  required String name,
  String? category,
  Quantity? servesPerUnit,
  // Legacy schema-v1 shape; nothing asks for these any more.
  ItemUnit unit = ItemUnit.each,
  int packWhole = 1,
}) async {
  final result = await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(
          name: name,
          servesPerUnit: servesPerUnit,
          unit: unit,
          packSize: Quantity.whole(packWhole),
          category: category,
        ),
      );
  return (result as Ok<String>).value;
}

Future<CommandReceipt> seedMovement(
  AppHarness h,
  String itemId, {
  MovementKind kind = MovementKind.receive,
  int whole = 5,
}) async {
  final result = await h
      .read(inventoryServiceProvider)
      .record(
        MovementFormDraft(
          itemId: itemId,
          kind: kind,
          quantity: Quantity.whole(whole),
        ),
      );
  return (result as Ok<CommandReceipt>).value;
}

Future<ItemDetail> readDetail(AppHarness h, String itemId) =>
    h.read(catalogServiceProvider).watchItem(itemId).first;

void main() {
  testWidgets('shows header, on-hand stat, and day-grouped history', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final id = await seedItem(
        h,
        name: 'Tortillas',
        category: 'Bread',
        servesPerUnit: Quantity.whole(4),
      );
      await seedMovement(h, id, whole: 5);
      await seedMovement(h, id, kind: MovementKind.waste, whole: 2);
      return id;
    }))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Bread · One serves 4 people'), findsOneWidget);
    expect(find.text('You have'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Purchase'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('Waste'), findsOneWidget);
    expect(find.text('−2'), findsOneWidget);
    // One day header groups both movements (both recorded "now").
    final today = DateTime.now();
    final day =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    expect(find.text(day), findsOneWidget);
  });

  testWidgets('negative on-hand gets a signed stat and warning', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final id = await seedItem(h, name: 'Tortillas');
      await seedMovement(h, id, kind: MovementKind.waste, whole: 2);
      return id;
    }))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));

    expect(find.text('−2'), findsNWidgets(2)); // stat + history row
    expect(find.text('Negative — record a count to fix it.'), findsOneWidget);
  });

  testWidgets('a legacy measured item keeps its unit beside the number', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      // Migrated schema-v1 row: 5 kg is a weight, not five things.
      final id = await seedItem(h, name: 'Mince', unit: ItemUnit.kg);
      await seedMovement(h, id, whole: 5);
      return id;
    }))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));

    expect(find.text('5 kg'), findsOneWidget);
    expect(find.text('+5 kg'), findsOneWidget);
  });

  testWidgets('empty history shows the §9 message', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Salsa')))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));

    expect(
      find.text(
        'No movements yet. Record a purchase or a count to establish '
        'on-hand.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('corrected movements stay visible, struck through', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final id = await seedItem(h, name: 'Tortillas');
      final receipt = await seedMovement(h, id, whole: 5);
      final correct = await h
          .read(inventoryServiceProvider)
          .correct(
            movementId: receipt.createdRecordIds.first,
            reason: 'entered against the wrong item',
          );
      expect(correct, isA<Ok<CommandReceipt>>());
      return id;
    }))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));

    // Original purchase row still present, marked corrected; the reversal
    // row is labeled Correction.
    expect(find.text('Purchase'), findsOneWidget);
    expect(find.text('Corrected'), findsOneWidget);
    expect(find.text('Correction'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Corrected entry: Purchase')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('archive and unarchive from the menu', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Tortillas')))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.byType(WarningBanner), findsOneWidget);
    expect(find.textContaining('This item is archived.'), findsOneWidget);
    var detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.isArchived, isTrue);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unarchive').last);
    await tester.pumpAndSettle();

    expect(find.byType(WarningBanner), findsNothing);
    detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.isArchived, isFalse);
  });

  testWidgets('quick actions route to the movement entry form', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Tortillas')))!;

    await h.pumpApp(tester);
    await h.go(tester, '/items/$id');
    expect(find.byType(ItemDetailScreen), findsOneWidget);

    await tester.tap(find.text('Record movement'));
    await tester.pumpAndSettle();

    // The router passed the item through the ?itemId= query parameter.
    final entry = tester.widget<MovementEntryScreen>(
      find.byType(MovementEntryScreen),
    );
    expect(entry.itemId, id);
    expect(entry.kind, isNull);
  });

  testWidgets('the header names where the item lives — folder chip and '
      'name, neutral inbox for Unfiled — and the amount wears its label', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final folders = await h.read(catalogServiceProvider).watchFolders().first;
      final bakery = folders
          .firstWhere((folder) => folder.name == 'Bakery')
          .id
          .value;
      final created = await h
          .read(catalogServiceProvider)
          .createItem(
            ItemDraft(
              name: 'Snack packs',
              folderId: bakery,
              unitLabel: 'packages',
            ),
          );
      final itemId = (created as Ok<String>).value;
      await seedMovement(h, itemId, whole: 12);
      return itemId;
    }))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));

    expect(find.text('Bakery'), findsOneWidget);
    expect(find.byType(FolderChip), findsOneWidget);
    // The on-hand stat reads "12 packages" — label after the amount.
    expect(find.text('12 packages'), findsOneWidget);

    // Move it to Unfiled: the header follows, chip turns neutral.
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder…'));
    await tester.pumpAndSettle();
    // The Unfiled entry sits past the sheet's fold, below the 8 folders.
    await tester.dragUntilVisible(
      find.text('Unfiled'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unfiled'));
    await tester.pumpAndSettle();

    expect(find.text('Unfiled'), findsOneWidget);
    expect(find.byType(FolderChip), findsNothing);
    expect(find.byType(UnfiledChip), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets("Move to folder… in the menu moves a folder's ONLY item — "
      'the first-class move, no edit form needed', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final folders = await h.read(catalogServiceProvider).watchFolders().first;
      final bakery = folders
          .firstWhere((folder) => folder.name == 'Bakery')
          .id
          .value;
      final created = await h
          .read(catalogServiceProvider)
          .createItem(ItemDraft(name: 'Croissants', folderId: bakery));
      return (created as Ok<String>).value;
    }))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));
    expect(find.text('Bakery'), findsOneWidget);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder…'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a folder'), findsOneWidget);
    await tester.tap(find.text('Drinks'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    final folders = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchFolders().first,
    );
    expect(
      detail!.item.folderId?.value,
      folders!.firstWhere((folder) => folder.name == 'Drinks').id.value,
    );
    // The header follows the stream.
    expect(find.text('Drinks'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('Delete item… confirms, pops back to the items list, and the '
      'snackbar names it', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Tortillas')))!;

    // The delete pops the route, so pump the full app rather than one
    // screen.
    await h.pumpApp(tester);
    await h.go(tester, '/items/$id');
    expect(find.byType(ItemDetailScreen), findsOneWidget);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete item…'));
    await tester.pumpAndSettle();

    // The shared confirmation, same wording as the list rows'.
    expect(find.text('Delete "Tortillas"?'), findsOneWidget);
    expect(
      find.text(
        'It comes off your items list. What happened at past events stays '
        'in your history.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Back on the items list (assert the screen type, not the URI), with
    // the snackbar over it; the item is gone for good (no history).
    expect(find.byType(ItemDetailScreen), findsNothing);
    expect(find.byType(ItemListScreen), findsOneWidget);
    expect(find.text('Deleted "Tortillas"'), findsOneWidget);
    final items = await tester.runAsync(
      () => h
          .read(catalogServiceProvider)
          .watchItems(const ItemFilter(includeArchived: true))
          .first,
    );
    expect(items, isEmpty);
    await h.flushTimers(tester);
  });

  testWidgets('unknown item id shows a fallback, not a crash', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await h.pumpScreen(
      tester,
      const ItemDetailScreen(itemId: '00000000000000000000000000'),
    );

    expect(find.text('This item is not available.'), findsOneWidget);
  });
}
