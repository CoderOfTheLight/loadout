/// MovementDetailScreen widget tests (design §9 `/movements/:id`): when it
/// happened, the single "Correct this entry" action, and the refused states
/// — closeout-written rows, reversal rows, and already-corrected rows
/// surface the state instead of offering the action.
///
/// Deliberately superseded pins: the "Source command" row and its
/// 20-character id are gone (pure model leakage), and "Recorded" only shows
/// when it differs from "Occurred".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
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

Future<String> _seedPurchase(
  AppHarness h,
  WidgetTester tester,
  String itemId,
) async {
  final result = await tester.runAsync(
    () => h
        .read(inventoryServiceProvider)
        .record(
          MovementFormDraft(
            itemId: itemId,
            kind: MovementKind.receive,
            quantity: Quantity.whole(3),
          ),
        ),
  );
  return result!.fold(
    (receipt) => receipt.createdRecordIds.first,
    (error) => throw StateError(error.code),
  );
}

void main() {
  testWidgets('form movement shows provenance and the correct action', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    final movementId = await _seedPurchase(h, tester, itemId);

    await h.pumpApp(tester);
    await h.go(tester, '/movements/$movementId');

    expect(find.text('Purchase'), findsOneWidget);
    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('+3 kg'), findsOneWidget);
    expect(find.text('Occurred'), findsOneWidget);
    // Recorded when it happened, so the second identical timestamp is not a
    // row she has to read to learn nothing.
    expect(find.text('Recorded'), findsNothing);
    // The internal command id is model leakage — never on her screen.
    expect(find.text('Source command'), findsNothing);
    expect(find.text('Correct this entry'), findsOneWidget);
  });

  testWidgets('closeout-written movement surfaces the refusal state', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    await _seedPurchase(h, tester, itemId);
    final consumeId = await tester.runAsync(() async {
      final events = h.read(eventServiceProvider);
      final created = await events.createEvent(
        EventDraft(
          name: 'Taco Night',
          scheduledDate: '2026-08-10',
          plannedExposure: 50,
          plannedItemIds: [itemId],
        ),
      );
      final eventId = created.fold(
        (id) => id,
        (error) => throw StateError(error.code),
      );
      await events.activate(eventId);
      final confirmed = await h
          .read(closeoutServiceProvider)
          .confirm(
            CloseoutFormDraft(
              eventId: eventId,
              confirmedExposure: 40,
              lines: [
                CloseoutFormLine(itemId: itemId, depletion: Quantity.whole(2)),
              ],
            ),
          );
      confirmed.fold((_) {}, (error) => throw StateError(error.code));
      final views = await h
          .read(inventoryServiceProvider)
          .watchMovements(const MovementFilter(kinds: {MovementKind.consume}))
          .first;
      return views.single.movement.id as String;
    });

    await h.pumpApp(tester);
    await h.go(tester, '/movements/$consumeId');

    expect(find.textContaining('written by an event closeout'), findsOneWidget);
    expect(find.text('Open closeout'), findsOneWidget);
    expect(find.text('Correct this entry'), findsNothing);
  });

  testWidgets('corrected original and its reversal surface their states', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    final movementId = await _seedPurchase(h, tester, itemId);
    final reversalId = await tester.runAsync(() async {
      final result = await h
          .read(inventoryServiceProvider)
          .correct(movementId: movementId, reason: 'typo');
      return result.fold(
        (receipt) => receipt.createdRecordIds.first,
        (error) => throw StateError(error.code),
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/movements/$movementId');
    expect(find.text('Corrected by a later entry'), findsOneWidget);
    expect(find.textContaining('already been corrected'), findsOneWidget);
    expect(find.text('Correct this entry'), findsNothing);

    await h.go(tester, '/movements/$reversalId');
    expect(find.text('Corrects an earlier entry'), findsOneWidget);
    expect(find.textContaining('cannot be corrected again'), findsOneWidget);
    expect(find.text('Correct this entry'), findsNothing);
  });
}
