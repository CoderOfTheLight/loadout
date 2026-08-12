/// MovementEntryScreen widget tests (design §9 `/movements/new`, §11.3):
/// record purchase / waste / count — the count computes the signed adjust
/// through the service, the negative-on-hand warning is shown but never
/// blocks, and waste defaults its event association to the active event.
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

    expect(find.text('Record movement'), findsOneWidget);
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

  testWidgets('count computes the signed adjustment via the service', (
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
              quantity: Quantity.whole(12),
            ),
          ),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/movements/new?kind=count&itemId=$itemId');

    expect(find.text('On hand now (derived): 12 kg'), findsOneWidget);
    await _enterQuantity(tester, '10.5');
    expect(find.text('Will record −1.5 kg adjustment'), findsOneWidget);

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

  testWidgets('waste defaults its event association to the active event', (
    tester,
  ) async {
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

    // The association dropdown resolved to the active event.
    expect(find.text('Taco Night'), findsOneWidget);
    await _enterQuantity(tester, '1');
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);

    final views = await _movements(h, tester);
    expect(views.first.movement.kind, MovementKind.waste);
    expect(views.first.movement.eventId as String?, eventId);
  });
}
