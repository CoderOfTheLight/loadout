/// ItemEditScreen widget tests, rebuilt around the owner's model of an
/// item: NAME + HOW MANY YOU HAVE + optionally HOW MANY PEOPLE ONE SERVES.
///
/// Covers create (with the opening count written as one movement in the
/// same transaction), the optional serves-per-unit field and clearing it,
/// the live duplicate-name check, edit mode's read-only derived count, and
/// the absence of every unit / pack-size control from the form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/count_form_field.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../../support/app_harness.dart';

const String nameField = 'Item name';
const String countField = 'How many do you have?';
const String servesField = 'How many people does one serve?';

Future<String> seedItem(
  AppHarness h, {
  required String name,
  String? category,
  Quantity? servesPerUnit,
  Quantity openingCount = Quantity.zero,
  // Legacy schema-v1 shape: a measured unit and a real pack size. Nothing
  // asks for these any more; they only arrive from a migrated database.
  ItemUnit unit = ItemUnit.each,
  Quantity packSize = Quantity.one,
}) async {
  final result = await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(
          name: name,
          servesPerUnit: servesPerUnit,
          unit: unit,
          packSize: packSize,
          category: category,
        ),
        openingCount: openingCount,
      );
  return (result as Ok<String>).value;
}

Future<ItemDetail> readDetail(AppHarness h, String itemId) =>
    h.read(catalogServiceProvider).watchItem(itemId).first;

Future<AppHarness> startWorkspace(WidgetTester tester) async => (await tester
    .runAsync(() => AppHarness.start(state: AppHarnessState.workspace)))!;

void main() {
  testWidgets('the form asks for a name, a count and who one serves — and '
      'nothing about units or packs', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());

    expect(find.widgetWithText(TextFormField, nameField), findsOneWidget);
    expect(find.widgetWithText(TextFormField, countField), findsOneWidget);
    expect(find.widgetWithText(TextFormField, servesField), findsOneWidget);

    // The dropdown the owner could not use, and the field she did not
    // understand, are gone from the product surface.
    expect(find.byType(DropdownMenu<ItemUnit>), findsNothing);
    expect(find.textContaining('Pack'), findsNothing);
    expect(find.textContaining('pack size'), findsNothing);
    expect(find.textContaining('Unit'), findsNothing);
    expect(find.text('kilograms'), findsNothing);
  });

  testWidgets('create needs only a name', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Beef burgers',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    expect(items, hasLength(1));
    final item = items!.single.item;
    expect(item.name, 'Beef burgers');
    expect(item.servesPerUnit, isNull);
    // Defaulted, never asked: a counted thing rounded to whole things.
    expect(item.unit, ItemUnit.each);
    expect(item.packSize, Quantity.one);
    // No count typed, so no opening movement exists.
    expect(items.single.onHandMicros, 0);
  });

  testWidgets('the opening count becomes on-hand through one movement', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Bread rolls',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, countField),
      '48',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, servesField),
      '2',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    final summary = items!.single;
    expect(summary.item.name, 'Bread rolls');
    expect(summary.item.servesPerUnit, Quantity.whole(2));
    expect(summary.onHandMicros, 48000000);

    // Derived from the append-only ledger, not stored on the item row.
    final movements = await tester.runAsync(
      () => h
          .read(inventoryServiceProvider)
          .watchMovements(const MovementFilter())
          .first,
    );
    expect(movements, hasLength(1));
    expect(movements!.single.movement.kind, MovementKind.adjust);
    expect(movements.single.movement.deltaMicros, 48000000);
  });

  testWidgets('the count field takes whole numbers only', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, countField),
      '2.5',
    );
    await tester.pump();

    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(CountFormField, countField),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      '25',
    );
  });

  testWidgets('serves-per-unit is optional and capped at 10000', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Paella pan',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, servesField),
      '20000',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a whole number from 1 to 10,000'), findsOneWidget);
    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    expect(items, isEmpty);
  });

  testWidgets('duplicate live name surfaces the uniqueness error inline', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() => seedItem(h, name: 'Tortillas'));

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'tortillas',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    expect(
      find.text('A live item with this name already exists.'),
      findsOneWidget,
    );
    final items = await tester.runAsync(
      () => h
          .read(catalogServiceProvider)
          .watchItems(const ItemFilter(includeArchived: true))
          .first,
    );
    expect(items, hasLength(1));
  });

  testWidgets('edit prefills name and serves, and saves plain updates', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(
        h,
        name: 'Tortillas',
        category: 'Bread',
        servesPerUnit: Quantity.whole(3),
      ),
    ))!;

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Corn tortillas',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, servesField),
      '4',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.name, 'Corn tortillas');
    expect(detail.item.category, 'Bread');
    expect(detail.item.servesPerUnit, Quantity.whole(4));
  });

  testWidgets('clearing serves-per-unit erases the stored value', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(h, name: 'Chilli', servesPerUnit: Quantity.whole(6)),
    ))!;

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    await tester.enterText(find.widgetWithText(TextFormField, servesField), '');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.servesPerUnit, isNull);
  });

  testWidgets('edit shows the derived count read-only, with a way to record '
      'a movement', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(h, name: 'Cups', openingCount: Quantity.whole(200)),
    ))!;

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));

    expect(find.text('How many you have now'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('Record a count'), findsOneWidget);
    // The count is ledger-derived: there is no field to type it into here.
    expect(find.widgetWithText(TextFormField, countField), findsNothing);
  });

  testWidgets('editing a legacy measured item keeps its unit and pack size', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    // A migrated schema-v1 row, plus a movement: its unit is locked, so a
    // form that resubmitted the new default would be rejected outright.
    final id = (await tester.runAsync(() async {
      final id = await seedItem(
        h,
        name: 'Mince',
        unit: ItemUnit.kg,
        packSize: Quantity.fromMicros(500000),
      );
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
    // Its measured unit is still not a control on this form.
    expect(find.byType(DropdownMenu<ItemUnit>), findsNothing);
    // It IS shown next to the number, so 5 kg is never read as 5 things.
    expect(find.text('5 kg'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Mince (500 g packs)',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.name, 'Mince (500 g packs)');
    expect(detail.item.unit, ItemUnit.kg);
    expect(detail.item.packSize, Quantity.fromMicros(500000));
  });
}
