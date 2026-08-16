/// ItemEditScreen widget tests, rebuilt around the folders proposal §3:
/// NAME + HOW MANY YOU HAVE + a FOLDER (picked, never typed) + the one
/// question ("Does how much you bring depend on how many people come?")
/// with its basis-shaped cold-start field(s).
///
/// Covers create (opening count as one movement), the folder picker with
/// "New folder…" creating through the command path, the folder pre-answering
/// the question with the override stored only when the item differs, the
/// one-value-two-phrasings pair (serves N / N per person, exact ratio), the
/// per-event "how many do you usually bring?", the plain-words confirm when
/// changing the answer on an item with history, the live duplicate-name
/// check, edit mode's read-only derived count, and the absence of every
/// unit / pack-size control.
///
/// Deliberately superseded pin from the flat-list era: the free-text
/// "Group" field is gone (folders proposal §3 — typed names are how
/// "Drinks"/"drinks"/"Beverages" become three folders). A legacy row's
/// category text now rides along verbatim instead, pinned below.
///
/// v5 deliberately superseded pins (owner's amount + unit rulings):
/// * "the count field takes whole numbers only" is GONE — the opening
///   count accepts decimals and simple/mixed fractions ("1 1/2" → 1.5),
///   pinned below at the form level.
/// * "nothing about units" is NARROWED — the legacy unit DROPDOWN stays
///   gone, but the optional display-label "Unit" field (free text +
///   shared suggestion chips, never converted) is now part of the form.
///
/// Also pinned here: the only-item move bug the owner hit — moving an
/// item with history between folders whose default answers differ used to
/// raise the "Read past events differently?" confirm, whose safe-sounding
/// "Keep it as it was" aborted the whole save and silently dropped the
/// move. A folder pick now keeps the item's effective answer (stored as
/// the per-item exception), so the move always survives and forecasts are
/// untouched.
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
const String servesField = 'How many people does one serve?';
const String perPersonField = 'How many per person?';
const String usualBringField = 'How many do you usually bring?';
const String perPersonChoice = 'More people, more of it';
const String perEventChoice = 'About the same every event';

Future<String> seedItem(
  AppHarness h, {
  required String name,
  String? category,
  String? folderId,
  Quantity? servesPerUnit,
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

void main() {
  testWidgets('the form asks for a name, a count, a folder and the one '
      'question — and nothing about units, packs or free-text groups', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());

    expect(find.widgetWithText(TextFormField, nameField), findsOneWidget);
    expect(find.widgetWithText(TextFormField, countField), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('Unfiled'), findsOneWidget);
    expect(
      find.text('Does how much you bring depend on how many people come?'),
      findsOneWidget,
    );
    expect(find.text(perPersonChoice), findsOneWidget);
    expect(find.text(perEventChoice), findsOneWidget);
    // Per-person by default (unfiled), so BOTH phrasings of the cold-start
    // question are offered — and the per-event one is not.
    expect(find.widgetWithText(TextFormField, servesField), findsOneWidget);
    expect(find.widgetWithText(TextFormField, perPersonField), findsOneWidget);
    expect(find.widgetWithText(TextFormField, usualBringField), findsNothing);

    // The dropdown the owner could not use, the field she did not
    // understand, and the free-text group box are gone.
    expect(find.byType(DropdownMenu<ItemUnit>), findsNothing);
    expect(find.textContaining('Pack'), findsNothing);
    expect(find.textContaining('pack size'), findsNothing);
    expect(find.text('kilograms'), findsNothing);
    expect(find.text('Group'), findsNothing);

    // v5: the optional DISPLAY-label unit field, with the shared
    // suggestion chips — a label, never a convertible unit.
    expect(
      find.widgetWithText(TextFormField, 'Unit (optional)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ActionChip, 'tsp'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'cup'), findsOneWidget);
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
    expect(item.perPersonRatio, isNull);
    expect(item.perEventBaseline, isNull);
    // Unfiled, inheriting the default answer: no override is stored.
    expect(item.folderId, isNull);
    expect(item.demandBasis, isNull);
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

  testWidgets('the count field accepts fractions at the form level: '
      '"1 1/2" becomes exactly 1.5 on hand', (tester) async {
    // Deliberately superseded pin: the digits-only opening count is gone
    // (owner's amount ruling — decimals, simple and mixed fractions).
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
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

  testWidgets('one value, two phrasings: typing "per person" clears '
      '"one serves", and stores an exact ratio', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Napkins',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, servesField),
      '4',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, perPersonField),
      '3',
    );
    await tester.pump();

    // The two fields are one question said two ways — never both.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(CountFormField, servesField),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      isEmpty,
    );

    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    final item = items!.single.item;
    // Exact integer ratio, not a reciprocal: 200 people × 3/person = 600.
    expect(item.perPersonRatio, UnitRatio(3, 1));
    expect(item.servesPerUnit, isNull);
    expect(
      item.perPersonRatio!.applyCeil(Quantity.whole(200)),
      Quantity.whole(600),
    );
  });

  testWidgets('the folder picker creates a folder through the command path '
      'and files the item into it', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
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
    // The dialog asks the one question too; the form behind it shows the
    // same labels, so aim for the dialog's copy.
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

    // The new folder pre-answers the question: per-event, so the usual-
    // bring field is on screen and no exception caption shows.
    expect(find.widgetWithText(TextFormField, usualBringField), findsOneWidget);
    expect(find.textContaining('this item is the exception'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, usualBringField),
      '2',
    );
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
    expect(item.perEventBaseline, Quantity.whole(2));
  });

  testWidgets('picking a per-event folder pre-answers the question; an '
      'explicit different answer is stored as the exception', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Sponges',
    );
    await openFolderPicker(tester);
    await tapPickerEntry(tester, 'Cleaning & setup');

    // The starter Cleaning & setup folder answers per-event.
    expect(find.widgetWithText(TextFormField, usualBringField), findsOneWidget);
    expect(find.widgetWithText(TextFormField, servesField), findsNothing);
    expect(find.textContaining('this item is the exception'), findsNothing);

    // Overriding flips the cold-start fields and calls out the exception.
    await tester.ensureVisible(find.text(perPersonChoice));
    await tester.tap(find.text(perPersonChoice));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, servesField), findsOneWidget);
    expect(find.textContaining('this item is the exception'), findsOneWidget);

    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    final item = items!.single.item;
    // Differs from the folder's answer → the override IS stored.
    expect(item.demandBasis, DemandBasis.perPerson);
  });

  testWidgets('changing the answer on an item WITH history asks first, in '
      'plain words', (tester) async {
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

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    await tester.ensureVisible(find.text(perEventChoice));
    await tester.tap(find.text(perEventChoice));
    await tester.pumpAndSettle();
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

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    await tester.ensureVisible(find.text(perEventChoice));
    await tester.tap(find.text(perEventChoice));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Read past events differently?'), findsNothing);
    final detail = await tester.runAsync(() => readDetail(h, id));
    expect(detail!.item.demandBasis, DemandBasis.perEvent);
    await h.flushTimers(tester);
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

  testWidgets('edit prefills name, folder and serves, saves plain updates, '
      'and carries a legacy category along verbatim', (tester) async {
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

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));

    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Bakery'), findsOneWidget);
    // The serves controller carries the stored value ('3'; asserted via
    // the controller because the sibling per-person field hints '3' too).
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(CountFormField, servesField),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      '3',
    );
    // The free-text group box is gone; its old text is not on the surface.
    expect(find.text('Bread'), findsNothing);

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
    expect(detail.item.folderId?.value, isNotNull);
    expect(detail.item.servesPerUnit, Quantity.whole(4));
    // The tidy-up flow's raw material survives an unrelated edit.
    expect(detail.item.category, 'Bread');
    await h.flushTimers(tester);
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
    await h.flushTimers(tester);
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
    await h.flushTimers(tester);
  });

  testWidgets('a suggestion chip fills the unit label, create stores it, '
      'and clearing the field on edit erases it', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ItemEditScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, nameField),
      'Sugar',
    );
    await tester.ensureVisible(find.widgetWithText(ActionChip, 'cup'));
    await tester.tap(find.widgetWithText(ActionChip, 'cup'));
    await tester.pump();
    // The chip filled the free-text field — a suggestion, not a picker.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'Unit (optional)'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'cup',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    final id = items!.single.item.id.value;
    expect(items.single.item.unitLabel, 'cup');

    // Edit prefills the label; clearing it clears the stored value (the
    // form always submits its complete state).
    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'Unit (optional)'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'cup',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Unit (optional)'),
      '',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final detail = await tester.runAsync(() => readDetail(h, id));
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

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    await openFolderPicker(tester, currentName: 'Bakery');
    await tapPickerEntry(tester, 'Drinks');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    var detail = await tester.runAsync(() => readDetail(h, id));
    var folders = await tester.runAsync(() => folderIdsByName(h));
    expect(detail!.item.folderId?.value, folders!['Drinks']);

    // Now the only item of Drinks → Unfiled (null folder), same form path.
    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
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

    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    await openFolderPicker(tester, currentName: 'Bakery');
    await tapPickerEntry(tester, 'Cleaning & setup');

    // The form keeps the answer the item already had — visibly the
    // exception in its new folder — instead of silently flipping it.
    expect(find.textContaining('this item is the exception'), findsOneWidget);

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
    await h.pumpScreen(tester, ItemEditScreen(itemId: id));
    await tester.ensureVisible(find.text(perEventChoice));
    await tester.tap(find.text(perEventChoice));
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
}
