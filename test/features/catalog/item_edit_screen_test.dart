/// §11.3 ItemEditScreen widget tests: add-item validation, live duplicate
/// name check, unit dropdown behavior, and the §4 unit lock in edit mode
/// after a movement (dropdown disabled, helper explains archive+recreate,
/// stored unit resubmitted verbatim).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
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

Future<ItemDetail> readDetail(AppHarness h, String itemId) =>
    h.read(catalogServiceProvider).watchItem(itemId).first;

void main() {
  testWidgets('create validates required fields inline', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter a pack size'), findsOneWidget);
  });

  testWidgets('duplicate live name surfaces the uniqueness error inline', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() => seedItem(h, name: 'Tortillas'));

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'tortillas',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Pack size'),
      '1',
    );
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(
      find.text('A live item with this name already exists.'),
      findsOneWidget,
    );
    // Nothing was created.
    final items = await tester.runAsync(
      () => h
          .read(catalogServiceProvider)
          .watchItems(const ItemFilter(includeArchived: true))
          .first,
    );
    expect(items, hasLength(1));
  });

  testWidgets('creates an item with unit, pack size, and category', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Tortillas',
    );
    await tester.tap(find.byType(DropdownMenu<ItemUnit>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kilograms').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Pack size'),
      '2.5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Category'),
      'Bread',
    );
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    expect(items, hasLength(1));
    final item = items!.single.item;
    expect(item.name, 'Tortillas');
    expect(item.unit, ItemUnit.kg);
    expect(item.packSize, Quantity.fromMicros(2500000));
    expect(item.category, 'Bread');
  });

  testWidgets('edit prefills the form and saves plain updates', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(h, name: 'Tortillas', category: 'Bread'),
    ))!;

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Corn tortillas',
    );
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.name, 'Corn tortillas');
    expect(detail.item.category, 'Bread');
  });

  testWidgets('unit is editable in edit mode while no movement exists', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Salsa')))!;

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));

    final dropdown = tester.widget<DropdownMenu<ItemUnit>>(
      find.byType(DropdownMenu<ItemUnit>),
    );
    expect(dropdown.enabled, isTrue);

    await tester.tap(find.byType(DropdownMenu<ItemUnit>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('litres').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.unit, ItemUnit.litre);
  });

  testWidgets('unit locks after the first movement: dropdown disabled, helper '
      'explains archive+recreate, and saving keeps the stored unit', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final id = await seedItem(h, name: 'Tortillas');
      final result = await h
          .read(inventoryServiceProvider)
          .record(
            MovementFormDraft(
              itemId: id,
              kind: MovementKind.receive,
              quantity: Quantity.whole(5),
            ),
          );
      expect(result, isA<Ok<Object?>>());
      return id;
    }))!;

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));

    final dropdown = tester.widget<DropdownMenu<ItemUnit>>(
      find.byType(DropdownMenu<ItemUnit>),
    );
    expect(dropdown.enabled, isFalse);
    expect(find.text(unitLockedExplanation), findsOneWidget);

    // Editing other fields still works; the stored unit is resubmitted.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Corn tortillas',
    );
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.name, 'Corn tortillas');
    expect(detail.item.unit, ItemUnit.kg);
    expect(detail.hasMovements, isTrue);
  });
}
