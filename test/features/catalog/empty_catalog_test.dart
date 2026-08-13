/// THE reported bug: "the new recipe form will not let me select anything
/// from the dropdown menus."
///
/// Every picker in the app is built from the item catalog, so an EMPTY
/// catalog used to render dropdowns with zero options and no explanation.
/// Each test here opens one of those screens with an empty workspace and
/// asserts two things: guidance that says what to do, and a control that
/// actually reaches `/items/new`.
///
/// These run against the FULL app (router + shell), because "a working way
/// out" means the route really opens — not that a button exists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/events/presentation/planned_items_picker.dart';
import 'package:loadout/features/inventory/presentation/item_picker_sheet.dart';

import '../../support/app_harness.dart';

/// Minimal host for the two bottom sheets, so each can be opened without
/// the screen that normally guards it.
class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.onOpen});

  final Future<Object?> Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => FilledButton(
          onPressed: () => onOpen(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

Future<AppHarness> startEmptyWorkspace(WidgetTester tester) async =>
    (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;

/// Taps the way out and asserts the new-item form is on screen.
Future<void> expectReachesNewItemForm(
  WidgetTester tester,
  Finder wayOut,
) async {
  expect(wayOut, findsOneWidget);
  await tester.ensureVisible(wayOut);
  await tester.tap(wayOut);
  await tester.pumpAndSettle();
  expect(find.byType(ItemEditScreen), findsOneWidget);
  expect(
    find.widgetWithText(TextFormField, 'How many do you have?'),
    findsOneWidget,
  );
}

void main() {
  testWidgets('the recipe form explains itself instead of showing empty '
      'dropdowns, and leads to the item form', (tester) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    // No dead dropdown: the output-item picker is not even built.
    expect(find.byKey(const Key('output-item-picker')), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Add an item first'), findsOneWidget);
    expect(
      find.textContaining('A recipe is built from your items'),
      findsOneWidget,
    );

    await expectReachesNewItemForm(tester, find.text('Add an item'));
  });

  testWidgets('an item added from the recipe dead end unblocks the form', (
    tester,
  ) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');
    await tester.tap(find.text('Add an item'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Item name'),
      'Tortillas',
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    // Back on the recipe form, now with a usable picker.
    expect(find.byKey(const Key('output-item-picker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('output-item-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Tortillas'), findsWidgets);
  });

  testWidgets('the event form stays usable but its planned-items section '
      'explains the empty catalog and leads out', (tester) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');

    // The rest of the event is still answerable ...
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    // ... but the picker that would open onto nothing is replaced.
    expect(find.text('Add items'), findsNothing);
    expect(find.textContaining('Add what you will bring'), findsOneWidget);

    await expectReachesNewItemForm(tester, find.text('Add an item'));
  });

  testWidgets('the planned-items sheet explains an empty catalog and closes '
      'onto the item form', (tester) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);

    // The sheet is guarded twice: the event form above replaces it while
    // the catalog is empty (previous test), and the sheet itself refuses to
    // be an empty checklist. This exercises the second guard directly.
    await h.pumpScreen(
      tester,
      _SheetHost(
        onOpen: (context) =>
            showPlannedItemsPicker(context, selected: const []),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to plan yet'), findsOneWidget);
    expect(find.textContaining('Add what you will bring'), findsOneWidget);
    // No dead checklist, and no "Done" over an empty selection.
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Done'), findsNothing);

    // The way out closes the sheet on its way to /items/new (routing itself
    // is covered by the event-form test above, which runs the real router).
    await tester.tap(find.text('Add an item'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to plan yet'), findsNothing);
    // Closing the sheet auto-disposes its providers; let drift's stream
    // close timer fire before the tree goes away.
    await h.flushTimers(tester);
  });

  testWidgets('the movement form explains an empty catalog instead of '
      'offering an item picker onto nothing', (tester) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpApp(tester);
    await h.go(tester, '/movements/new');

    expect(find.text('Add an item first'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'How many?'), findsNothing);

    await expectReachesNewItemForm(tester, find.text('Add an item'));
  });

  testWidgets('the item picker sheet explains an empty catalog and closes '
      'onto the item form', (tester) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpScreen(tester, _SheetHost(onOpen: showItemPickerSheet));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('No items yet'), findsOneWidget);
    // Searching an empty catalog helps nobody: the search field is gone too.
    expect(find.widgetWithText(TextField, 'Search items'), findsNothing);

    await tester.tap(find.text('Add an item'));
    await tester.pumpAndSettle();
    expect(find.text('No items yet'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('a recipe whose only item is its own output explains the '
      'empty ingredient picker', (tester) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(
      () => h
          .read(catalogServiceProvider)
          .createItem(const ItemDraft(name: 'Taco kit')),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    await tester.tap(find.byKey(const Key('output-item-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taco kit').last);
    await tester.pumpAndSettle();

    // The only live item is the output, so the ingredient row has nothing
    // to offer — and says so instead of opening onto nothing.
    expect(find.byKey(const ValueKey('ingredient-item-0')), findsNothing);
    expect(
      find.textContaining('The only item you have is what this recipe makes'),
      findsOneWidget,
    );

    // It also blocks the save: a line was never filled in.
    await tester.ensureVisible(find.byKey(const Key('save-recipe')));
    await tester.tap(find.byKey(const Key('save-recipe')));
    await tester.pumpAndSettle();
    expect(
      find.text('Add another item to use as an ingredient'),
      findsOneWidget,
    );

    await expectReachesNewItemForm(tester, find.text('Add an item'));
  });

  testWidgets('the item list itself explains what an item is', (tester) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);

    await h.pumpApp(tester);
    await h.go(tester, '/items');

    expect(find.text('Nothing in your list yet'), findsOneWidget);
    expect(
      find.textContaining('Items are the things you bring and sell'),
      findsOneWidget,
    );

    await expectReachesNewItemForm(tester, find.text('Add your first item'));
  });

  testWidgets('an event with no planned items still closes out', (
    tester,
  ) async {
    final h = await startEmptyWorkspace(tester);
    addTearDown(h.dispose);
    final eventId = (await tester.runAsync(() async {
      final created = await h
          .read(eventServiceProvider)
          .createEvent(
            const EventDraft(
              name: 'Bare market',
              scheduledDate: '2026-09-05',
              plannedExposure: 40,
            ),
          );
      final id = (created as Ok<String>).value;
      await h.read(eventServiceProvider).activate(id);
      return id;
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    expect(
      find.textContaining('This event has no planned items'),
      findsOneWidget,
    );
  });
}
