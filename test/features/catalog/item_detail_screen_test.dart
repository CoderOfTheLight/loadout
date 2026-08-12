/// §11.3 ItemDetailScreen widget tests: derived on-hand stat, day-grouped
/// movement history (corrected rows struck through, never hidden),
/// archive/unarchive via the menu, quick record-movement links.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/warning_banner.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/approval/domain/proposal.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_detail_screen.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/inventory/presentation/movement_entry_screen.dart';

import '../../support/app_harness.dart';

Future<String> seedItem(
  AppHarness h, {
  required String name,
  ItemUnit unit = ItemUnit.kg,
  int packWhole = 2,
  String? category,
}) async {
  final result = await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(
          name: name,
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
      final id = await seedItem(h, name: 'Tortillas', category: 'Bread');
      await seedMovement(h, id, whole: 5);
      await seedMovement(h, id, kind: MovementKind.waste, whole: 2);
      return id;
    }))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: id));

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Bread · kilograms · Pack of 2 kg'), findsOneWidget);
    expect(find.text('On hand'), findsOneWidget);
    expect(find.text('3 kg'), findsOneWidget);
    expect(find.text('Purchase'), findsOneWidget);
    expect(find.text('+5 kg'), findsOneWidget);
    expect(find.text('Waste'), findsOneWidget);
    expect(find.text('−2 kg'), findsOneWidget);
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

    expect(find.text('−2 kg'), findsNWidgets(2)); // stat + history row
    expect(find.text('Negative — record a count to fix it.'), findsOneWidget);
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
