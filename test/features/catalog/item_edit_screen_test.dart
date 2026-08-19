/// ItemEditScreen widget tests.
///
/// THE FRONT DOOR IS FOUR FIELDS. `/items/new` asks for a NAME, HOW MANY YOU
/// HAVE, a PRICE EACH (optional) and a FOLDER (picked, never typed) — the
/// same four the scan-in "New item" sheet asks, which is the shape this form
/// was rebuilt to match. Nothing else is on the way in.
///
/// Everything else lives on the SAVED item behind one "More options" row:
/// the display-label Unit, the one question as a single checkbox ("Bring the
/// same amount however many people come"), the cold-start number, and notes.
///
/// Deliberately superseded pins from the long-form era:
/// * the one question is NOT on the create form — the folder answers it and
///   the item inherits silently (the stored override stays null);
/// * "How many people does one serve?" and "How many per person?" are no
///   longer two fields that clear each other: ONE number plus a two-option
///   phrasing pick, round-tripped both ways below;
/// * the 13 unit-suggestion chips are gone — a plain text box with a hint
///   is the whole control;
/// * the "this item is the exception" caption is gone (the checkbox shows
///   the answer); the BEHAVIOUR it described is pinned below unchanged.
///
/// Older superseded pins that still hold: no unit dropdown, no pack size, no
/// free-text group — a legacy row's unit, pack size and category ride along
/// verbatim. The opening count accepts decimals and simple/mixed fractions.
///
/// Also pinned here: the only-item move bug the owner hit — moving an item
/// with history between folders whose default answers differ used to raise
/// the "Read past events differently?" confirm, whose safe-sounding "Keep it
/// as it was" aborted the whole save and silently dropped the move. A folder
/// pick keeps the item's effective answer (stored as the per-item
/// exception), so the move always survives and forecasts are untouched.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/count_form_field.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/unit_ratio.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../../support/app_harness.dart';

const String nameField = 'Item name';
const String countField = 'How many do you have?';
const String priceField = 'Price each (optional)';
const String unitField = 'Unit (optional)';
const String usualBringField = 'How many do you usually bring?';
const String basisCheckbox = 'Bring the same amount however many people come';
const String perPersonChoice = 'More people, more of it';
const String perEventChoice = 'About the same every event';

/// The old two-field pair, by the labels it used to carry. Nothing on the
/// form may answer to these again.
const String servesField = 'How many people does one serve?';
const String perPersonField = 'How many per person?';

Future<String> seedItem(
  AppHarness h, {
  required String name,
  String? category,
  String? folderId,
  Quantity? servesPerUnit,
  UnitRatio? perPersonRatio,
  DemandBasis? demandBasis,
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
          perPersonRatio: perPersonRatio,
          folderId: folderId,
          demandBasis: demandBasis,
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

Future<Map<String, String>> folderIdsByName(AppHarness h) async {
  final folders = await h.read(catalogServiceProvider).watchFolders().first;
  return {for (final folder in folders) folder.name: folder.id.value};
}

Future<AppHarness> startWorkspace(WidgetTester tester) async => (await tester
    .runAsync(() => AppHarness.start(state: AppHarnessState.workspace)))!;

/// Opens the folder picker sheet from the form's Folder field, which shows
/// [currentName] as its value.
Future<void> openFolderPicker(
  WidgetTester tester, {
  String currentName = 'Unfiled',
}) async {
  await tester.ensureVisible(find.text(currentName));
  await tester.tap(find.text(currentName));
  await tester.pumpAndSettle();
}

/// Scrolls the open picker sheet to [label] and taps it (eight starter
/// folders push the later entries below the sheet's fold).
Future<void> tapPickerEntry(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.dragUntilVisible(
    target,
    find.byType(ListView),
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Pumps the form fresh. A plain `pumpScreen(const ItemEditScreen())` twice
/// in a row REUSES the state (same type, same key), which silently carries
/// the folder pick and the open/closed More options row into what is
/// supposed to be a new screen; the unique key makes each pump a new one.
Future<void> pumpForm(WidgetTester tester, AppHarness h, [String? itemId]) =>
    h.pumpScreen(tester, ItemEditScreen(key: UniqueKey(), itemId: itemId));

/// The one plain row that opens everything that is not on the way in.
Future<void> openMoreOptions(WidgetTester tester) async {
  await tester.ensureVisible(find.text('More options'));
  await tester.tap(find.text('More options'));
  await tester.pumpAndSettle();
}

/// The cold-start row's number, read off its controller.
String? coldStartText(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byType(CountFormField),
        matching: find.byType(TextField),
      ),
    )
    .controller
    ?.text;

Future<void> enterColdStart(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(CountFormField),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pump();
}

/// Picks a phrasing in the cold-start row's two-option dropdown.
Future<void> pickPhrasing(WidgetTester tester, String label) async {
  final dropdown = find.byKey(const Key('per-person-phrasing'));
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('/items/new is FOUR fields: a name, how many, a price and a '
      'folder — and nothing else', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await pumpForm(tester, h);

    expect(find.widgetWithText(TextFormField, nameField), findsOneWidget);
    expect(find.widgetWithText(TextFormField, countField), findsOneWidget);
    expect(find.widgetWithText(TextFormField, priceField), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('Unfiled'), findsOneWidget);
    // Three text fields and the folder pick-list. Exactly.
    expect(find.byType(TextFormField), findsNWidgets(3));

    // The forecast engine's DemandBasis in costume is not asked at all.
    expect(
      find.text('Does how much you bring depend on how many people come?'),
      findsNothing,
    );
    expect(find.text(perPersonChoice), findsNothing);
    expect(find.text(perEventChoice), findsNothing);
    expect(find.text(basisCheckbox), findsNothing);

    // Neither cold-start phrasing, old or new, is on the way in.
    expect(find.widgetWithText(TextFormField, servesField), findsNothing);
    expect(find.widgetWithText(TextFormField, perPersonField), findsNothing);
    expect(find.widgetWithText(TextFormField, usualBringField), findsNothing);
    expect(find.byKey(const Key('per-person-phrasing')), findsNothing);

    // Nor the unit label, its 13 chips, the notes box, or the row that
    // opens them — that row belongs to a SAVED item.
    expect(find.widgetWithText(TextFormField, unitField), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('More options'), findsNothing);

    // The dropdown the owner could not use, the field she did not
    // understand, and the free-text group box stay gone.
    expect(find.byType(DropdownMenu<ItemUnit>), findsNothing);
    expect(find.textContaining('Pack'), findsNothing);
    expect(find.textContaining('pack size'), findsNothing);
    expect(find.text('Group'), findsNothing);
  });

  testWidgets('create needs only a name', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await pumpForm(tester, h);
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
    expect(item.perPersonRatio, isNull);
    expect(item.perEventBaseline, isNull);
    // Unfiled, inheriting the default answer: no override is stored.
    expect(item.folderId, isNull);
    expect(item.demandBasis, isNull);
    // Defaulted, never asked: a counted thing rounded to whole things.
    expect(item.unit, ItemUnit.each);
    expect(item.packSize, Quantity.one);
    expect(item.unitLabel, isNull);
    // No count typed, so no opening movement exists.
    expect(items.single.onHandMicros, 0);
  });

  testWidgets('an item created at /items/new inherits its folder\'s answer '
      'silently — nothing asked, no override stored', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    // Cleaning & setup is a starter folder that answers per-event; Bakery
    // answers per-person. Neither question reaches the create form.
    await pumpForm(tester, h);
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Sponges',
    );
    await openFolderPicker(tester);
    await tapPickerEntry(tester, 'Cleaning & setup');
    expect(find.text(basisCheckbox), findsNothing);
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final folders = (await tester.runAsync(() => folderIdsByName(h)))!;
    var items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    var item = items!.single.item;
    expect(item.folderId?.value, folders['Cleaning & setup']);
    // Inherited, not copied: a folder-level change carries its items along.
    expect(item.demandBasis, isNull);

    // The same on the other side of the question.
    await pumpForm(tester, h);
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Croissants',
    );
    await openFolderPicker(tester);
    await tapPickerEntry(tester, 'Bakery');
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    item = items!.firstWhere((s) => s.item.name == 'Croissants').item;
    expect(item.folderId?.value, folders['Bakery']);
    expect(item.demandBasis, isNull);
    await h.flushTimers(tester);
  });

  testWidgets('the opening count becomes on-hand through one movement', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await pumpForm(tester, h);
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Bread rolls',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, countField),
      '48',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    final summary = items!.single;
    expect(summary.item.name, 'Bread rolls');
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

  testWidgets('the count field accepts fractions at the form level: '
      '"1 1/2" becomes exactly 1.5 on hand', (tester) async {
    // Deliberately superseded pin: the digits-only opening count is gone
    // (owner's amount ruling — decimals, simple and mixed fractions).
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await pumpForm(tester, h);
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Flour (bag)',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, countField),
      '1 1/2',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    // Exact integer micros — never a double on the way through.
    expect(items!.single.onHandMicros, 1500000);
  });

  testWidgets('duplicate live name surfaces the uniqueness error inline', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() => seedItem(h, name: 'Tortillas'));

    await pumpForm(tester, h);
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

  testWidgets('the folder picker creates a folder through the command path '
      'and files the item into it', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await pumpForm(tester, h);
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Songbook',
    );
    await openFolderPicker(tester);

    // The owner's folders, in her order, with "New folder…" at the bottom.
    expect(find.text('Choose a folder'), findsOneWidget);
    expect(find.text('Cooked on site'), findsOneWidget);

    await tapPickerEntry(tester, 'New folder…');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Folder name'),
      'Front table',
    );
    // The dialog asks the one question (a folder's answer is the one place
    // it IS asked); the form behind it no longer does.
    await tester.tap(find.text(perEventChoice).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();

    // Created through the command path, appended to the owner's order, and
    // selected in the form.
    final folders = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchFolders().first,
    );
    expect(folders!.last.name, 'Front table');
    expect(folders.last.demandBasis, DemandBasis.perEvent);
    expect(folders.last.position, 8);
    expect(find.text('Front table'), findsOneWidget);

    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    final item = items!.single.item;
    expect(item.name, 'Songbook');
    expect(item.folderId?.value, folders.last.id.value);
    // Matches the folder's answer → inherit, no stored override.
    expect(item.demandBasis, isNull);
  });

  testWidgets('More options is what reveals the rest — and only on a saved '
      'item', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Cups')))!;

    await pumpForm(tester, h, id);

    // Closed: the four fields, the barcode row, and one plain row.
    expect(find.text('More options'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, unitField), findsNothing);
    expect(find.text(basisCheckbox), findsNothing);
    expect(find.text('Notes'), findsNothing);
    expect(find.byKey(const Key('per-person-phrasing')), findsNothing);

    await openMoreOptions(tester);

    expect(find.widgetWithText(TextFormField, unitField), findsOneWidget);
    expect(find.text(basisCheckbox), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    // Unfiled answers per-person, so the cold-start row is the number pair.
    expect(find.byKey(const Key('per-person-phrasing')), findsOneWidget);
    // One number and one pick — never the two fields that cleared each
    // other, and never the 13 chips.
    expect(find.byType(CountFormField), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('the cold-start row round-trips BOTH phrasings through one '
      'number and one pick', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(h, name: 'Chilli', servesPerUnit: Quantity.whole(3)),
    ))!;

    // Stored as "one serves 3 people": the number and the phrasing both
    // come back.
    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    expect(coldStartText(tester), '3');
    expect(find.text('people per one'), findsOneWidget);

    // Flip the phrasing only — the number stays, the meaning changes, and
    // the exact integer ratio is what gets stored.
    await pickPhrasing(tester, 'per person');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    var detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.perPersonRatio, UnitRatio(3, 1));
    expect(detail.item.servesPerUnit, isNull);
    // Exact integer ratio, not a reciprocal: 200 people × 3/person = 600.
    expect(
      detail.item.perPersonRatio!.applyCeil(Quantity.whole(200)),
      Quantity.whole(600),
    );

    // And back again, with a new number.
    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    expect(coldStartText(tester), '3');
    expect(find.text('per person'), findsOneWidget);
    await enterColdStart(tester, '8');
    await pickPhrasing(tester, 'people per one');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.servesPerUnit, Quantity.whole(8));
    expect(detail.item.perPersonRatio, isNull);
    await h.flushTimers(tester);
  });

  testWidgets('a phrasing this form cannot express rides along verbatim '
      'through an unrelated rename', (tester) async {
    // "3 per 4 people" has a denominator this whole-number row cannot show.
    // Opening More options and touching nothing must not rewrite it.
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(h, name: 'Punch', perPersonRatio: UnitRatio(3, 4)),
    ))!;

    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    expect(coldStartText(tester), isEmpty);
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Fruit punch',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.name, 'Fruit punch');
    expect(detail.item.perPersonRatio, UnitRatio(3, 4));
    await h.flushTimers(tester);
  });

  testWidgets('the cold-start number is optional and capped at 10000', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Paella pan')))!;

    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    await enterColdStart(tester, '20000');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a whole number from 1 to 10,000'), findsOneWidget);
    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.servesPerUnit, isNull);
    await h.flushTimers(tester);
  });

  testWidgets('clearing the cold-start number erases the stored value', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(h, name: 'Chilli', servesPerUnit: Quantity.whole(6)),
    ))!;

    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    await enterColdStart(tester, '');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.servesPerUnit, isNull);
    await h.flushTimers(tester);
  });

  testWidgets('the one question is ONE checkbox, and ticking it on an item '
      'WITH history asks first, in plain words', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final id = await seedItem(h, name: 'Dish soap');
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

    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    // Unfiled answers per-person, so the box starts unticked.
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.ensureVisible(find.text(basisCheckbox));
    await tester.tap(find.text(basisCheckbox));
    await tester.pumpAndSettle();
    // Ticked, the cold-start row becomes the per-event question.
    expect(find.widgetWithText(TextFormField, usualBringField), findsOneWidget);
    expect(find.byKey(const Key('per-person-phrasing')), findsNothing);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // The plain-words confirm, not a silent rewrite.
    expect(find.text('Read past events differently?'), findsOneWidget);
    expect(find.textContaining('This item has history'), findsOneWidget);

    // Backing out keeps everything as it was.
    await tester.tap(find.text('Keep it as it was'));
    await tester.pumpAndSettle();
    var detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.demandBasis, isNull);

    // Confirming saves the new answer.
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change it'));
    await tester.pumpAndSettle();
    detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.demandBasis, DemandBasis.perEvent);
    await h.flushTimers(tester);
  });

  testWidgets('changing the answer on an item WITHOUT history saves without '
      'asking', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Table signs')))!;

    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    await tester.ensureVisible(find.text(basisCheckbox));
    await tester.tap(find.text(basisCheckbox));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, usualBringField),
      '2',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Read past events differently?'), findsNothing);
    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.demandBasis, DemandBasis.perEvent);
    expect(detail.item.perEventBaseline, Quantity.whole(2));
    await h.flushTimers(tester);
  });

  testWidgets('edit prefills name and folder, saves plain updates, and '
      'carries a legacy category along verbatim', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      return seedItem(
        h,
        name: 'Tortillas',
        category: 'Bread',
        folderId: folders['Bakery'],
        servesPerUnit: Quantity.whole(3),
      );
    }))!;

    await pumpForm(tester, h, id);

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Bakery'), findsOneWidget);
    // The free-text group box is gone; its old text is not on the surface.
    expect(find.text('Bread'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Corn tortillas',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.name, 'Corn tortillas');
    expect(detail.item.folderId?.value, isNotNull);
    // Untouched behind the closed row, and untouched in the database.
    expect(detail.item.servesPerUnit, Quantity.whole(3));
    // The tidy-up flow's raw material survives an unrelated edit.
    expect(detail.item.category, 'Bread');
    await h.flushTimers(tester);
  });

  testWidgets('edit shows the derived count read-only, with a way to record '
      'a count', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(h, name: 'Cups', openingCount: Quantity.whole(200)),
    ))!;

    await pumpForm(tester, h, id);

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

    await pumpForm(tester, h, id);
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
    await h.flushTimers(tester);
  });

  testWidgets('the unit label is a plain text box under More options: typing '
      'stores it, clearing it erases it', (tester) async {
    // Deliberately superseded pin: the 13 suggestion chips are gone — a
    // bespoke keyboard for a field most items leave blank.
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() => seedItem(h, name: 'Sugar')))!;

    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    expect(find.byType(ActionChip), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, unitField),
      'cup',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    var detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.unitLabel, 'cup');

    // Edit prefills the label; clearing it clears the stored value (the
    // form always submits its complete state).
    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(TextFormField, unitField),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'cup',
    );
    await tester.enterText(find.widgetWithText(TextFormField, unitField), '');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.unitLabel, isNull);
    await h.flushTimers(tester);
  });

  testWidgets("moving a folder's ONLY item out via the edit form works — "
      'to another folder and to Unfiled', (tester) async {
    // The owner's report, pinned: she tried to move a sole occupant and
    // failed. The service always worked; the form path must too.
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      return seedItem(h, name: 'Croissants', folderId: folders['Bakery']);
    }))!;

    await pumpForm(tester, h, id);
    await openFolderPicker(tester, currentName: 'Bakery');
    await tapPickerEntry(tester, 'Drinks');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    var detail = await tester.runAsync(() => readDetail(h, id));
    var folders = await tester.runAsync(() => folderIdsByName(h));
    expect(detail!.item.folderId?.value, folders!['Drinks']);

    // Now the only item of Drinks → Unfiled (null folder), same form path.
    await pumpForm(tester, h, id);
    await openFolderPicker(tester, currentName: 'Drinks');
    await tapPickerEntry(tester, 'Unfiled');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.folderId, isNull);
    await h.flushTimers(tester);
  });

  testWidgets('ROOT CAUSE pinned: moving an item WITH history into a '
      'folder with a different answer saves the move without asking, and '
      'keeps the answer it had as the exception', (tester) async {
    // Before the fix, this exact flow raised "Read past events
    // differently?" and its safe-sounding "Keep it as it was" aborted the
    // WHOLE save — the move was silently dropped (the failure the owner
    // hit on her phone with a folder's only item).
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(() async {
      final folders = await folderIdsByName(h);
      // Bakery answers per-person; Cleaning & setup answers per-event.
      final id = await seedItem(
        h,
        name: 'Napkin holder',
        folderId: folders['Bakery'],
      );
      final result = await h
          .read(inventoryServiceProvider)
          .record(
            MovementFormDraft(
              itemId: id,
              kind: MovementKind.receive,
              quantity: Quantity.whole(1),
            ),
          );
      expect(result, isA<Ok<Object?>>());
      return id;
    }))!;

    await pumpForm(tester, h, id);
    await openFolderPicker(tester, currentName: 'Bakery');
    await tapPickerEntry(tester, 'Cleaning & setup');

    // The form keeps the answer the item already had — the box stays
    // unticked in a folder that would have ticked it — instead of silently
    // flipping it.
    await openMoreOptions(tester);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // No forecasting confirm for a pure move — nothing about forecasting
    // changed.
    expect(find.text('Read past events differently?'), findsNothing);

    final detail = await tester.runAsync(() => readDetail(h, id));
    final folders = await tester.runAsync(() => folderIdsByName(h));
    // The move survived ...
    expect(detail!.item.folderId?.value, folders!['Cleaning & setup']);
    // ... and past events read exactly as before: the old effective
    // answer is stored as the per-item exception.
    expect(detail.item.demandBasis, DemandBasis.perPerson);

    // Changing the answer stays HER explicit act — and still confirms.
    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    await tester.ensureVisible(find.text(basisCheckbox));
    await tester.tap(find.text(basisCheckbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Read past events differently?'), findsOneWidget);
    await tester.tap(find.text('Change it'));
    await tester.pumpAndSettle();
    final after = await tester.runAsync(() => readDetail(h, id));
    // Matches the folder's answer again → override cleared, inherits.
    expect(after!.item.demandBasis, isNull);
    await h.flushTimers(tester);
  });

  testWidgets('create and edit both survive 200% text scale on a 320 dp '
      'viewport — More options open, cold-start row and all', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    final id = (await tester.runAsync(
      () => seedItem(
        h,
        name: 'Chicken soup',
        servesPerUnit: Quantity.whole(8),
        openingCount: Quantity.whole(40),
      ),
    ))!;

    // An overflow at this scale would throw and fail the test here.
    await pumpForm(tester, h);
    expect(find.widgetWithText(TextFormField, nameField), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await pumpForm(tester, h, id);
    await openMoreOptions(tester);
    expect(find.text(basisCheckbox), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('per-person-phrasing')), findsOneWidget);

    // Dark too: the form is rebuilt per brightness.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });
}
