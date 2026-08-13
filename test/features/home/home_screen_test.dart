/// HomeScreen widget tests (design §9 `/home`, §11.3).
///
/// Covers the two states the owner actually meets — a brand-new workspace
/// that has to explain what the app is for, and a working one that has to
/// lead with what needs doing — plus forecast readiness (which now reads
/// `ForecastBasis`, so a serves-baseline line is never announced as "no
/// history"), and the 200 % text-scale pass on a 320 dp viewport.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/router.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';
import 'package:loadout/features/events/presentation/event_edit_screen.dart';
import 'package:loadout/features/home/presentation/home_screen.dart';
import 'package:loadout/features/inventory/presentation/movement_entry_screen.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../../support/app_harness.dart';

String _date(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Imperative pushes land beyond `currentConfiguration.uri`, which keeps
/// reporting the shell location — assert on the destination screen instead.

/// The dashboard is a phone-shaped scrolling column, and the default
/// 800x600 test window is shorter than any real phone: content below the
/// fold is never built, so finders miss it and taps land on nothing. Use a
/// phone-width, generously tall surface instead.
void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<String> _seedItem(
  AppHarness h,
  WidgetTester tester, {
  String name = 'Tortillas',
  Quantity? servesPerUnit,
}) async {
  final result = await tester.runAsync(
    () => h
        .read(catalogServiceProvider)
        .createItem(ItemDraft(name: name, servesPerUnit: servesPerUnit)),
  );
  return result!.fold((id) => id, (error) => throw StateError(error.code));
}

/// Item with −2 on hand, an active event held yesterday (closeout pending),
/// and a planned event tomorrow (the next event).
Future<void> _seedDashboard(AppHarness h, WidgetTester tester) async {
  final itemId = await _seedItem(h, tester);
  await tester.runAsync(() async {
    final inventory = h.read(inventoryServiceProvider);
    await inventory.record(
      MovementFormDraft(
        itemId: itemId,
        kind: MovementKind.waste,
        quantity: Quantity.whole(2),
      ),
    );
    final events = h.read(eventServiceProvider);
    final yesterday = await events.createEvent(
      EventDraft(
        name: 'Taco Night',
        scheduledDate: _date(DateTime.now().subtract(const Duration(days: 1))),
        plannedItemIds: [itemId],
      ),
    );
    final yesterdayId = yesterday.fold(
      (id) => id,
      (error) => throw StateError(error.code),
    );
    await events.activate(yesterdayId);
    await events.createEvent(
      EventDraft(
        name: 'Street Fair',
        scheduledDate: _date(DateTime.now().add(const Duration(days: 1))),
        plannedItemIds: [itemId],
      ),
    );
  });
}

void main() {
  testWidgets('a brand-new workspace explains what the app is for', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);

    // The promise, then the loop, in the owner's words — not one bare
    // "Add item" button with no explanation (owner feedback #5).
    expect(find.text('Bring the right amount to every event.'), findsOneWidget);
    expect(find.text('Add what you sell'), findsOneWidget);
    expect(find.text('Plan an event'), findsWidgets);
    expect(find.text('Say what you used'), findsOneWidget);

    await tester.tap(find.text('Add my first item'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemEditScreen), findsOneWidget);
    expect(
      tester.widget<ItemEditScreen>(find.byType(ItemEditScreen)).itemId,
      isNull,
      reason: 'the first step opens the create form, not an edit form',
    );
  });

  testWidgets('the first run offers planning an event as the second step', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Plan an event'));
    await tester.pumpAndSettle();
    expect(find.byType(EventEditScreen), findsOneWidget);
  });

  testWidgets('dashboard leads with what needs doing', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    await h.pumpApp(tester);

    // The screen answers "is there anything for me?" before anything else.
    expect(find.text('What needs doing'), findsOneWidget);
    // (1) Pending-closeout nudge for the active event past its date.
    expect(find.text('Close out Taco Night'), findsOneWidget);
    // (2) Next-event card, dated in plain words, with forecast readiness.
    expect(find.text('Street Fair'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.textContaining('No forecast yet'), findsOneWidget);
    // (3) Quick actions.
    expect(find.text('Record a purchase'), findsOneWidget);
    expect(find.text('Count stock'), findsOneWidget);
    // (4) Data health: negative on-hand, signed, and with no unit — an item
    // is a name and a count now.
    expect(find.text('Tortillas is showing −2'), findsOneWidget);
    // (5) Recent movements + See all.
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.textContaining('Waste'), findsWidgets);
  });

  testWidgets('an empty calendar says so and offers the next move', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedItem(h, tester);

    await h.pumpApp(tester);

    expect(find.text("You're up to date"), findsOneWidget);
    expect(find.text('No event coming up'), findsOneWidget);
  });

  testWidgets('closeout nudge and quick actions navigate', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    await h.pumpApp(tester);
    await tester.tap(find.text('Record a purchase'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MovementEntryScreen>(find.byType(MovementEntryScreen)).kind,
      'receive',
    );

    h.read(routerProvider).go('/home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close out Taco Night'));
    await tester.pumpAndSettle();
    expect(find.byType(CloseoutScreen), findsOneWidget);

    h.read(routerProvider).go('/home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tortillas is showing −2'), warnIfMissed: false);
    await tester.pumpAndSettle();
    final countEntry = tester.widget<MovementEntryScreen>(
      find.byType(MovementEntryScreen),
    );
    expect(countEntry.kind, 'count');
    expect(countEntry.itemId, isNotNull);
  });

  testWidgets('a serves-baseline forecast is not reported as no history', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    // "1 pizza serves 4" and no closeout anywhere: the engine has no
    // evidence, but the line still carries a number.
    final itemId = await _seedItem(
      h,
      tester,
      name: 'Pizza',
      servesPerUnit: Quantity.whole(4),
    );
    await tester.runAsync(() async {
      final events = h.read(eventServiceProvider);
      final created = await events.createEvent(
        EventDraft(
          name: 'Street Fair',
          scheduledDate: _date(DateTime.now().add(const Duration(days: 2))),
          plannedExposure: 100,
          plannedItemIds: [itemId],
        ),
      );
      final eventId = created.fold(
        (id) => id,
        (error) => throw StateError(error.code),
      );
      await h.read(forecastServiceProvider).generateSnapshot(eventId);
    });

    await h.pumpApp(tester);

    expect(
      find.textContaining('1 estimated, not yet proven'),
      findsOneWidget,
      reason: 'a baseline line has a number and must not read as no history',
    );
    expect(find.textContaining('nothing to go on'), findsNothing);
  });

  testWidgets('renders at 200% text scale on a 320 dp viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    // Overflow at 200 % scale would throw and fail the test here.
    await h.pumpApp(tester);
    expect(find.text('Close out Taco Night'), findsOneWidget);
  });

  testWidgets('the first run also renders at 200% text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
