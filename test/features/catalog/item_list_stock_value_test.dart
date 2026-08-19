/// "Stock value" on `/items` (v7 money): what everything on the list is
/// worth, Σ (on-hand × price each) over LIVE items, at the owner's current
/// prices.
///
/// The honesty rules are the pins, not the arithmetic:
///  * an unpriced item contributes nothing and is COUNTED and said out loud
///    — never a $0 standing in for a price she has not given;
///  * an item counted BELOW ZERO contributes nothing and is counted on its
///    own line: a negative count is a counting error, not stock in the van,
///    and letting it subtract would quietly shrink a total that is supposed
///    to say what is on the shelves;
///  * with nothing priced at all there is no total UI whatsoever;
///  * the figure is LIVE — a repriced item or a changed count moves it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_list_screen.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../../support/app_harness.dart';

Future<AppHarness> startWorkspace(WidgetTester tester) async => (await tester
    .runAsync(() => AppHarness.start(state: AppHarnessState.workspace)))!;

Future<String> seedItem(
  AppHarness h, {
  required String name,
  Money? unitPrice,
  int openingWhole = 0,
}) async {
  final result = await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(name: name, unitPrice: unitPrice),
        openingCount: Quantity.whole(openingWhole),
      );
  return (result as Ok<String>).value;
}

/// Drives an item's count below zero the way the ledger really does.
Future<void> wasteWhole(AppHarness h, String itemId, int whole) async {
  final result = await h
      .read(inventoryServiceProvider)
      .record(
        MovementFormDraft(
          itemId: itemId,
          kind: MovementKind.waste,
          quantity: Quantity.whole(whole),
        ),
      );
  expect(result, isA<Ok<Object?>>());
}

void main() {
  testWidgets('the list opens with what the stock is worth, and says how '
      'many items it could not price', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      // 4 × $3.50 = $14.00, 3 × $1.25 = $3.75 → $17.75.
      await seedItem(
        h,
        name: 'Croissants',
        unitPrice: Money.fromCents(350),
        openingWhole: 4,
      );
      await seedItem(
        h,
        name: 'Tortillas',
        unitPrice: Money.fromCents(125),
        openingWhole: 3,
      );
      await seedItem(h, name: 'Water', openingWhole: 6);
      await seedItem(h, name: 'Cups', openingWhole: 2);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.text('Stock value'), findsOneWidget);
    expect(find.text(r'$17.75'), findsOneWidget);
    expect(
      find.text("What's on hand, at your current prices."),
      findsOneWidget,
    );
    expect(
      find.text('2 items have no price yet — not counted.'),
      findsOneWidget,
    );
    // The unpriced items are counted in the note, never as free stock.
    expect(find.text(r'$21.75'), findsNothing);
  });

  testWidgets('one unpriced item is said in the singular', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(
        h,
        name: 'Croissants',
        unitPrice: Money.fromCents(350),
        openingWhole: 4,
      );
      await seedItem(h, name: 'Water', openingWhole: 6);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.text(r'$14'), findsOneWidget);
    expect(find.text('1 item has no price yet — not counted.'), findsOneWidget);
    expect(find.textContaining('items have no price'), findsNothing);
  });

  testWidgets('nothing priced at all → no total UI whatsoever', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, name: 'Water', openingWhole: 6);
      await seedItem(h, name: 'Cups', openingWhole: 2);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.text('Stock value'), findsNothing);
    expect(find.text(r'$0'), findsNothing);
    expect(find.textContaining('not counted'), findsNothing);
    expect(find.textContaining("What's on hand"), findsNothing);
  });

  testWidgets(r'a priced catalog with nothing on hand is worth $0 — a true '
      'answer, not a stand-in for an unknown one', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, name: 'Croissants', unitPrice: Money.fromCents(350));
    });

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.text('Stock value'), findsOneWidget);
    expect(find.text(r'$0'), findsOneWidget);
    expect(find.textContaining('not counted'), findsNothing);
  });

  testWidgets('the total follows a price change and a count change', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String croissants;
    await tester.runAsync(() async {
      croissants = await seedItem(
        h,
        name: 'Croissants',
        unitPrice: Money.fromCents(350),
        openingWhole: 4,
      );
    });

    await h.pumpScreen(tester, const ItemListScreen());
    expect(find.text(r'$14'), findsOneWidget);

    // Reprice: 4 × $4.25 = $17.00.
    await tester.runAsync(() async {
      final result = await h
          .read(catalogServiceProvider)
          .updateItem(
            itemId: croissants,
            draft: const ItemDraft(name: 'Croissants'),
          );
      expect(result, isA<Ok<void>>());
    });
    await tester.pumpAndSettle();
    // Clearing the price removes the item from the total AND from the
    // figure entirely — nothing else on this list is priced.
    expect(find.text('Stock value'), findsNothing);

    await tester.runAsync(() async {
      final result = await h
          .read(catalogServiceProvider)
          .updateItem(
            itemId: croissants,
            draft: ItemDraft(
              name: 'Croissants',
              unitPrice: Money.fromCents(425),
            ),
          );
      expect(result, isA<Ok<void>>());
    });
    await tester.pumpAndSettle();
    expect(find.text(r'$17'), findsOneWidget);

    // Count two more in: 6 × $4.25 = $25.50.
    await tester.runAsync(() async {
      final result = await h
          .read(inventoryServiceProvider)
          .record(
            MovementFormDraft(
              itemId: croissants,
              kind: MovementKind.receive,
              quantity: Quantity.whole(2),
            ),
          );
      expect(result, isA<Ok<Object?>>());
    });
    await tester.pumpAndSettle();
    expect(find.text(r'$25.50'), findsOneWidget);
  });

  testWidgets('an item counted below zero contributes nothing and is said '
      'on its own line — it never subtracts', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(
        h,
        name: 'Croissants',
        unitPrice: Money.fromCents(350),
        openingWhole: 4,
      );
      final salsa = await seedItem(
        h,
        name: 'Salsa',
        unitPrice: Money.fromCents(200),
      );
      await wasteWhole(h, salsa, 2); // on hand −2
    });

    await h.pumpScreen(tester, const ItemListScreen());

    // $14.00, not $10.00 (which is what −2 × $2.00 subtracting would give).
    expect(find.text(r'$14'), findsOneWidget);
    expect(find.text(r'$10'), findsNothing);
    expect(
      find.text('1 item has a negative count — not counted.'),
      findsOneWidget,
    );
    expect(find.textContaining('no price yet'), findsNothing);
  });

  testWidgets('several negative counts are said in the plural, and an '
      'unpriced negative item counts as unpriced', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(
        h,
        name: 'Croissants',
        unitPrice: Money.fromCents(350),
        openingWhole: 4,
      );
      for (final name in ['Salsa', 'Beans']) {
        final id = await seedItem(
          h,
          name: name,
          unitPrice: Money.fromCents(200),
        );
        await wasteWhole(h, id, 1);
      }
      // No price AND below zero: the missing price is the first thing wrong
      // with it, so it is counted once, as unpriced.
      final cups = await seedItem(h, name: 'Cups');
      await wasteWhole(h, cups, 1);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.text(r'$14'), findsOneWidget);
    expect(
      find.text('2 items have a negative count — not counted.'),
      findsOneWidget,
    );
    expect(find.text('1 item has no price yet — not counted.'), findsOneWidget);
  });

  testWidgets('searching hides the total — a whole-catalog figure over a '
      'filtered list would answer a question nobody asked', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(
        h,
        name: 'Croissants',
        unitPrice: Money.fromCents(350),
        openingWhole: 4,
      );
      await seedItem(
        h,
        name: 'Tortillas',
        unitPrice: Money.fromCents(125),
        openingWhole: 3,
      );
    });

    await h.pumpScreen(tester, const ItemListScreen());
    expect(find.text(r'$17.75'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'tor');
    await tester.pumpAndSettle();
    expect(find.text('Stock value'), findsNothing);
    expect(find.text(r'$17.75'), findsNothing);

    await tester.enterText(find.byType(SearchBar), '');
    await tester.pumpAndSettle();
    expect(find.text(r'$17.75'), findsOneWidget);
  });

  testWidgets('archived items are not stock: the toggle never moves the '
      'total', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(
        h,
        name: 'Croissants',
        unitPrice: Money.fromCents(350),
        openingWhole: 4,
      );
      final salsa = await seedItem(
        h,
        name: 'Salsa',
        unitPrice: Money.fromCents(200),
        openingWhole: 5,
      );
      final result = await h
          .read(catalogServiceProvider)
          .setArchived(itemId: salsa, archived: true);
      expect(result, isA<Ok<void>>());
    });

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.text(r'$14'), findsOneWidget);
    expect(find.text(r'$24'), findsNothing);
  });

  testWidgets('the total survives 200 % text scale in both brightnesses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(
        h,
        name: 'Croissants',
        unitPrice: Money.fromCents(350),
        openingWhole: 4,
      );
      final salsa = await seedItem(
        h,
        name: 'Salsa',
        unitPrice: Money.fromCents(200),
      );
      await wasteWhole(h, salsa, 2);
      await seedItem(h, name: 'Water', openingWhole: 6);
    });

    // An overflow at 200 % scale would throw and fail the test here.
    await h.pumpScreen(tester, const ItemListScreen());
    expect(find.text('Stock value'), findsOneWidget);
    expect(find.text(r'$14'), findsOneWidget);
    expect(find.text('1 item has no price yet — not counted.'), findsOneWidget);
    expect(
      find.text('1 item has a negative count — not counted.'),
      findsOneWidget,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text(r'$14'), findsOneWidget);
  });

  testWidgets('the jump chips still land on their section with the summary '
      'sitting above them', (tester) async {
    // The summary is part of the jump arithmetic now (its measured height
    // is added to every section offset). A jump that ignored it would land
    // one summary short of the section it names.
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await h.read(catalogServiceProvider).watchFolders().first;
      expect(folders, hasLength(8));
      for (var i = 0; i < 80; i++) {
        await h
            .read(catalogServiceProvider)
            .createItem(
              ItemDraft(
                name: 'Item ${'${i + 1}'.padLeft(3, '0')}',
                folderId: folders[i % 8].id.value,
                unitPrice: Money.fromCents(100),
              ),
              openingCount: Quantity.whole(1),
            );
      }
    });

    await h.pumpScreen(tester, const ItemListScreen());
    // 80 items × 1 on hand × $1.00.
    expect(find.text(r'$80'), findsOneWidget);

    final inList = find.descendant(
      of: find.byType(SliverMainAxisGroup),
      matching: find.text('Sales table'),
    );
    expect(inList, findsNothing);

    // The chip sits past the right edge of the horizontal jump row.
    await tester.ensureVisible(find.text('Sales table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales table'));
    await tester.pumpAndSettle();

    // Landed: the section's own header is on screen with its items
    // (i % 8 == 7 → Item 008, 016, …).
    expect(inList, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SliverMainAxisGroup),
        matching: find.text('Item 008'),
      ),
      findsOneWidget,
    );
  });
}
