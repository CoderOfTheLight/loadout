/// HomeScreen widget tests (design §9 `/home`, §11.3): fresh-workspace
/// empty state, dashboard priority content (closeout nudge, next-event
/// card, quick actions, data health, recent movements), and the 200 %
/// text-scale accessibility pass on a 320 dp viewport.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/router.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';
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

Future<String> _seedItem(AppHarness h, WidgetTester tester) async {
  final result = await tester.runAsync(
    () => h
        .read(catalogServiceProvider)
        .createItem(
          ItemDraft(
            name: 'Tortillas',
            unit: ItemUnit.kg,
            packSize: Quantity.whole(1),
          ),
        ),
  );
  return result!.fold((id) => id, (error) => throw StateError(error.code));
}

/// Item with −2 kg on hand, an active event held yesterday (closeout
/// pending), and a planned event tomorrow (the next event).
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
  testWidgets('fresh workspace shows the empty state with add-item action', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);

    expect(
      find.text('Start by adding the items you bring to events'),
      findsOneWidget,
    );
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemEditScreen), findsOneWidget);
    expect(
      tester.widget<ItemEditScreen>(find.byType(ItemEditScreen)).itemId,
      isNull,
      reason: 'the empty state opens the create form, not an edit form',
    );
  });

  testWidgets('dashboard surfaces nudges, data health, and recent activity', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    await h.pumpApp(tester);

    // (1) Pending-closeout nudge for the active event past its date.
    expect(find.text('Close out Taco Night'), findsOneWidget);
    // (2) Next-event card for the planned event, with forecast readiness.
    expect(find.text('Street Fair'), findsOneWidget);
    expect(find.textContaining('No forecast yet'), findsOneWidget);
    // (3) Quick actions.
    expect(find.text('Record purchase'), findsOneWidget);
    expect(find.text('Count stock'), findsOneWidget);
    // (4) Data health: negative on-hand, signed, with the count CTA.
    expect(
      find.textContaining('Tortillas shows −2 kg — record a count to fix'),
      findsOneWidget,
    );
    // (5) Recent movements + See all.
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.textContaining('Waste'), findsWidgets);
  });

  testWidgets('closeout nudge and quick actions navigate', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    await h.pumpApp(tester);
    await tester.tap(find.text('Record purchase'));
    await tester.pumpAndSettle();
    expect(find.text('Record movement'), findsOneWidget);
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
    await tester.tap(
      find.textContaining('Tortillas shows −2 kg'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    final countEntry = tester.widget<MovementEntryScreen>(
      find.byType(MovementEntryScreen),
    );
    expect(countEntry.kind, 'count');
    expect(countEntry.itemId, isNotNull);
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
}
