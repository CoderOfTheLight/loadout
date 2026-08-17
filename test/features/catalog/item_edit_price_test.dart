/// Item price on the form and the detail screen (v7): 'Price each
/// (optional)' — exact cents through MoneyCodec, never a double.
///
/// THE CRITICAL PIN: `CatalogService.updateItem` is whole-state, so a form
/// save with a null draft price CLEARS a stored one. The edit form must
/// prefill the price and carry it through, or renaming an item silently
/// wipes its price. An explicitly EMPTIED field clearing the price is the
/// same grammar working as intended — both directions are pinned here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_detail_screen.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';

import '../../support/app_harness.dart';

const String nameField = 'Item name';
const String priceField = 'Price each (optional)';

Future<AppHarness> startWorkspace(WidgetTester tester) async => (await tester
    .runAsync(() => AppHarness.start(state: AppHarnessState.workspace)))!;

Future<String> seedItem(
  AppHarness h, {
  required String name,
  Money? unitPrice,
  Quantity openingCount = Quantity.zero,
}) async {
  final result = await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(name: name, unitPrice: unitPrice),
        openingCount: openingCount,
      );
  return (result as Ok<String>).value;
}

Future<Item> readItem(AppHarness h, String itemId) async =>
    (await h.read(catalogServiceProvider).watchItem(itemId).first).item;

String? priceFieldText(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, priceField),
        matching: find.byType(TextField),
      ),
    )
    .controller
    ?.text;

void main() {
  testWidgets('CRITICAL: editing only the name keeps a stored price — the '
      'whole-state save carries the prefilled value through', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(h, name: 'Lemonade', unitPrice: Money.fromCents(250)),
    ))!;

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    // The prefill (the field paints its own '$' prefix, so no '$' here).
    expect(priceFieldText(tester), '2.50');

    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Pink lemonade',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final item = await tester.runAsync(() => readItem(h, id));
    expect(item!.name, 'Pink lemonade');
    // The rename did not wipe the price.
    expect(item.unitPrice, Money.fromCents(250));
    await h.flushTimers(tester);
  });

  testWidgets('create stores the typed price as exact cents', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Beef burgers',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, priceField),
      '1,234.56',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    expect(items!.single.item.unitPrice, Money.fromCents(123456));
  });

  testWidgets('setting a price on edit stores it; emptying the field on a '
      'later edit clears it — the whole-state grammar, both ways', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Cups')))!;

    // No price yet: the field starts empty.
    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    expect(priceFieldText(tester), isEmpty);
    await tester.enterText(
      find.widgetWithText(TextFormField, priceField),
      '12.50',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    var item = await tester.runAsync(() => readItem(h, id));
    expect(item!.unitPrice, Money.fromCents(1250));

    // Emptying the prefilled field is the owner's answer: no price.
    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    expect(priceFieldText(tester), '12.50');
    await tester.enterText(find.widgetWithText(TextFormField, priceField), '');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    item = await tester.runAsync(() => readItem(h, id));
    expect(item!.unitPrice, isNull);
    await h.flushTimers(tester);
  });

  testWidgets('a malformed or out-of-range price blocks the save in plain '
      'words', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Ice bags',
    );
    // '12.' passes the keystroke formatter (a typing intermediate) but is
    // not a dollar amount; '0' parses but no price is under one cent.
    await tester.enterText(
      find.widgetWithText(TextFormField, priceField),
      '12.',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a price like 12.50'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, priceField), '0');
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a price like 12.50'), findsOneWidget);

    // Over the validator's unit-price cap.
    await tester.enterText(
      find.widgetWithText(TextFormField, priceField),
      '2000000',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    expect(find.text(r'Keep it under $1,000,000'), findsOneWidget);

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    expect(items, isEmpty);
  });

  testWidgets('the detail screen states the price fact only when one is '
      'set', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final priced = (await tester.runAsync(
      () => seedItem(h, name: 'Lemonade', unitPrice: Money.fromCents(250)),
    ))!;
    final unpriced = (await tester.runAsync(
      () => seedItem(h, name: 'Napkins'),
    ))!;

    await h.pumpScreen(tester, ItemDetailScreen(itemId: priced));
    expect(find.textContaining(r'Price each · $2.50'), findsOneWidget);

    await h.pumpScreen(tester, ItemDetailScreen(itemId: unpriced));
    expect(find.textContaining('Price each'), findsNothing);
    await h.flushTimers(tester);
  });
}
