/// §11.3 ItemListScreen widget tests: catalog + on-hand at a glance,
/// search, archived toggle, negative on-hand shown signed, empty state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/empty_state.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_list_screen.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

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

Future<void> seedMovement(
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
  expect(result, isA<Ok<Object?>>());
}

void main() {
  testWidgets('shows items with on-hand, unit, and pack caption', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final tortillas = await seedItem(h, name: 'Tortillas', category: 'Bread');
      await seedItem(h, name: 'Salsa', unit: ItemUnit.litre, packWhole: 1);
      await seedMovement(h, tortillas, whole: 5);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('5 kg'), findsOneWidget);
    expect(find.text('Bread · Pack of 2 kg'), findsOneWidget);
    expect(find.text('Salsa'), findsOneWidget);
    expect(find.text('0 L'), findsOneWidget);
  });

  testWidgets('negative on-hand is shown signed with a warning', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final id = await seedItem(h, name: 'Tortillas');
      await seedMovement(h, id, kind: MovementKind.waste, whole: 2);
    });

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.text('−2 kg'), findsOneWidget);
    expect(find.text('Negative'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  testWidgets('search filters the list', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, name: 'Tortillas');
      await seedItem(h, name: 'Salsa');
    });

    await h.pumpScreen(tester, const ItemListScreen());
    expect(find.text('Salsa'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'tor');
    await tester.pumpAndSettle();

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Salsa'), findsNothing);
  });

  testWidgets('archived items appear only via the Show archived toggle', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, name: 'Tortillas');
      final retired = await seedItem(h, name: 'Old cups');
      final result = await h
          .read(catalogServiceProvider)
          .setArchived(itemId: retired, archived: true);
      expect(result, isA<Ok<void>>());
    });

    await h.pumpScreen(tester, const ItemListScreen());
    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Old cups'), findsNothing);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckedPopupMenuItem<String>));
    await tester.pumpAndSettle();

    expect(find.text('Old cups'), findsOneWidget);
    expect(find.textContaining('Archived'), findsOneWidget);
  });

  testWidgets('category chips filter the list', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, name: 'Tortillas', category: 'Bread');
      await seedItem(h, name: 'Salsa', category: 'Sauces');
    });

    await h.pumpScreen(tester, const ItemListScreen());
    expect(find.byType(FilterChip), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilterChip, 'Bread'));
    await tester.pumpAndSettle();

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Salsa'), findsNothing);
  });

  testWidgets('empty catalog shows the §9 empty state', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemListScreen());

    expect(find.byType(EmptyState), findsOneWidget);
    expect(
      find.text('No items yet. Add what you sell or bring.'),
      findsOneWidget,
    );
  });
}
