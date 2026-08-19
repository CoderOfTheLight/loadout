/// MovementEntryScreen widget tests (design §9 `/movements/new`, §11.3).
///
/// The screen is THREE plain screens now, one per `?kind=`: "Count what you
/// have", "Something arrived", "Something was thrown out". Pinned here: each
/// route shows its own title and NO kind picker (the three-way segmented
/// control the owner had to set before the form made sense is gone), the
/// count computes the signed adjust through the service and previews it in
/// plain words ("That's 1.5 kg fewer than before"), the negative-on-hand
/// warning is shown but never blocks, waste still associates itself with the
/// active event — silently, with no dropdown to read — and every one of the
/// three survives 200 % text scale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/quantity_form_field.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/inventory/presentation/movement_entry_screen.dart';

import '../../support/app_harness.dart';

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

Future<List<MovementView>> _movements(AppHarness h, WidgetTester tester) async {
  final views = await tester.runAsync(
    () => h
        .read(inventoryServiceProvider)
        .watchMovements(const MovementFilter())
        .first,
  );
  return views!;
}

Future<void> _enterQuantity(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(QuantityFormField),
      matching: find.byType(TextFormField),
    ),
    text,
  );
  await tester.pump();
}

void main() {
  testWidgets('each kind is its own plain screen, with no kind picker', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);

    await h.pumpApp(tester);

    for (final entry in {
      '/movements/new?kind=count&itemId=$itemId': 'Count what you have',
      '/movements/new?kind=receive&itemId=$itemId': 'Something arrived',
      '/movements/new?kind=waste&itemId=$itemId': 'Something was thrown out',
    }.entries) {
      // go_router reuses the page when only the query changes; leave first.
      await h.go(tester, '/items');
      await h.go(tester, entry.key);
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      // The three-way control that had to be set before the form made
      // sense — and the jargon title over it — are gone.
      expect(find.byType(SegmentedButton<MovementKind>), findsNothing);
      expect(find.text('Record movement'), findsNothing);
      // So is the date row: today unless she says otherwise.
      expect(find.text('Occurred'), findsNothing);
      // And the privacy note that lives on the Settings privacy card.
      expect(find.text('Stored encrypted, never logged'), findsNothing);
    }

    // No kind at all still lands somewhere sensible.
    await h.go(tester, '/items');
    await h.go(tester, '/movements/new');
    expect(find.text('Something arrived'), findsOneWidget);
  });

  testWidgets('records a purchase with kind and item prefilled', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);

    await h.pumpApp(tester);
    await h.go(tester, '/movements/new?kind=receive&itemId=$itemId');

    expect(find.text('Something arrived'), findsOneWidget);
    expect(find.textContaining('Tortillas'), findsOneWidget);
    await _enterQuantity(tester, '3');
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);

    expect(find.text('Recorded.'), findsOneWidget);
    final views = await _movements(h, tester);
    expect(views, hasLength(1));
    expect(views.single.movement.kind, MovementKind.receive);
    expect(views.single.movement.deltaMicros, 3000000);
  });

  testWidgets('count computes the signed adjustment via the service, and '
      'says what it will do in plain words', (tester) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    await tester.runAsync(
      () => h
          .read(inventoryServiceProvider)
          .record(
            MovementFormDraft(
              itemId: itemId,
              kind: MovementKind.receive,
              quantity: Quantity.whole(12),
            ),
          ),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/movements/new?kind=count&itemId=$itemId');

    // "Loadout has 12 kg" said the app's name back to her; this says hers.
    expect(find.text('You have 12 kg'), findsOneWidget);
    await _enterQuantity(tester, '10.5');
    expect(find.text("That's 1.5 kg fewer than before"), findsOneWidget);
    await _enterQuantity(tester, '14');
    expect(find.text("That's 2 kg more than before"), findsOneWidget);
    await _enterQuantity(tester, '10.5');

    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);

    final views = await _movements(h, tester);
    expect(views, hasLength(2));
    expect(views.first.movement.kind, MovementKind.adjust);
    expect(views.first.movement.deltaMicros, -1500000);
  });

  testWidgets('count equal to derived on-hand records nothing', (tester) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    await tester.runAsync(
      () => h
          .read(inventoryServiceProvider)
          .record(
            MovementFormDraft(
              itemId: itemId,
              kind: MovementKind.receive,
              quantity: Quantity.whole(12),
            ),
          ),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/movements/new?kind=count&itemId=$itemId');
    await _enterQuantity(tester, '12');
    expect(find.text('No change to record.'), findsOneWidget);

    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);

    expect(find.text('On hand already matches your count.'), findsOneWidget);
    expect(await _movements(h, tester), hasLength(1));
  });

  testWidgets('negative on-hand warning is shown and never blocks', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    await tester.runAsync(
      () => h
          .read(inventoryServiceProvider)
          .record(
            MovementFormDraft(
              itemId: itemId,
              kind: MovementKind.receive,
              quantity: Quantity.whole(2),
            ),
          ),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/movements/new?kind=waste&itemId=$itemId');
    await _enterQuantity(tester, '5');
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);

    // Warned, not blocked: the movement was appended anyway (§5).
    expect(find.textContaining('below zero'), findsOneWidget);
    final views = await _movements(h, tester);
    expect(views, hasLength(2));
    expect(views.first.movement.kind, MovementKind.waste);
    expect(views.first.movement.deltaMicros, -5000000);
  });

  testWidgets('waste still associates itself with the active event — '
      'silently, with no dropdown to read', (tester) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    final eventId = await tester.runAsync(() async {
      final events = h.read(eventServiceProvider);
      final created = await events.createEvent(
        EventDraft(
          name: 'Taco Night',
          scheduledDate: '2026-08-11',
          plannedItemIds: [itemId],
        ),
      );
      final id = created.fold(
        (id) => id,
        (error) => throw StateError(error.code),
      );
      await events.activate(id);
      return id;
    });

    await h.pumpApp(tester);
    await h.go(tester, '/movements/new?kind=waste&itemId=$itemId');

    // The dropdown is gone; its default behaviour is not.
    expect(find.text('Event (optional)'), findsNothing);
    expect(find.text('Taco Night'), findsNothing);
    await _enterQuantity(tester, '1');
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);

    final views = await _movements(h, tester);
    expect(views.first.movement.kind, MovementKind.waste);
    expect(views.first.movement.eventId as String?, eventId);
  });

  testWidgets('all three survive 200% text scale on a 320 dp viewport', (
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
    final itemId = await _seedItem(h, tester);
    await tester.runAsync(
      () => h
          .read(inventoryServiceProvider)
          .record(
            MovementFormDraft(
              itemId: itemId,
              kind: MovementKind.receive,
              quantity: Quantity.whole(12),
            ),
          ),
    );

    // An overflow at this scale throws and fails the test here.
    for (final entry in {
      'count': 'Count what you have',
      'receive': 'Something arrived',
      'waste': 'Something was thrown out',
    }.entries) {
      // A unique key per pump: the same widget type at the same spot
      // reuses its State, and this screen reads its kind once in initState.
      await h.pumpScreen(
        tester,
        MovementEntryScreen(key: UniqueKey(), kind: entry.key, itemId: itemId),
      );
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    await h.flushTimers(tester);
  });
}
