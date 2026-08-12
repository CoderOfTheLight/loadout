/// ActivityScreen widget tests (design §9 `/activity`): empty state,
/// day-grouped rows, kind filter chips, and corrected rows struck through
/// while staying visible (§11.3 correction row).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
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

Future<String> _record(
  AppHarness h,
  WidgetTester tester,
  String itemId,
  MovementKind kind,
  int wholeQuantity,
) async {
  final result = await tester.runAsync(
    () => h
        .read(inventoryServiceProvider)
        .record(
          MovementFormDraft(
            itemId: itemId,
            kind: kind,
            quantity: Quantity.whole(wholeQuantity),
          ),
        ),
  );
  return result!.fold(
    (receipt) => receipt.createdRecordIds.first,
    (error) => throw StateError(error.code),
  );
}

void main() {
  testWidgets('empty ledger shows the permanence copy', (tester) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);
    await h.go(tester, '/activity');

    expect(
      find.text(
        'Every purchase, waste, count, and closeout lands here — permanently.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('rows are day-grouped and filterable by kind', (tester) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    await _record(h, tester, itemId, MovementKind.receive, 3);
    await _record(h, tester, itemId, MovementKind.waste, 1);

    await h.pumpApp(tester);
    await h.go(tester, '/activity');

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('+3 kg'), findsOneWidget);
    expect(find.text('−1 kg'), findsOneWidget);

    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();
    expect(find.text('+3 kg'), findsOneWidget);
    expect(find.text('−1 kg'), findsNothing);
  });

  testWidgets('corrected rows stay visible, struck through, chipped', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    final movementId = await _record(
      h,
      tester,
      itemId,
      MovementKind.receive,
      3,
    );
    await tester.runAsync(
      () => h
          .read(inventoryServiceProvider)
          .correct(movementId: movementId, reason: 'typo'),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/activity');

    // Original row still present, marked corrected; reversal row labeled.
    expect(find.text('Corrected'), findsOneWidget);
    // The subtitle joins kind, event, and time, so match the kind alone.
    expect(
      find.textContaining('Correction of an earlier entry'),
      findsOneWidget,
    );
    expect(find.text('+3 kg'), findsOneWidget);
    expect(find.text('−3 kg'), findsOneWidget);
  });
}
