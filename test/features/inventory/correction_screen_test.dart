/// CorrectionScreen widget tests (design §9 `/movements/:id/correct`,
/// §11.3 correction row): atomic reversal + optional replacement in one
/// command, reverse-only toggle, required reason, and the refusal state
/// for targets the applier rejects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/quantity_form_field.dart';
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

Future<String> _seedPurchase(
  AppHarness h,
  WidgetTester tester,
  String itemId, {
  int whole = 10,
}) async {
  final result = await tester.runAsync(
    () => h
        .read(inventoryServiceProvider)
        .record(
          MovementFormDraft(
            itemId: itemId,
            kind: MovementKind.receive,
            quantity: Quantity.whole(whole),
          ),
        ),
  );
  return result!.fold(
    (receipt) => receipt.createdRecordIds.first,
    (error) => throw StateError(error.code),
  );
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

void main() {
  testWidgets('records reversal plus replacement in one command', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    final movementId = await _seedPurchase(h, tester, itemId);

    await h.pumpApp(tester);
    await h.go(tester, '/movements/$movementId/correct');

    // Replacement prefilled from the target.
    expect(find.text('10'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'typo',
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(QuantityFormField),
        matching: find.byType(TextFormField),
      ),
      '8',
    );
    await tester.tap(find.text('Record correction'));
    await tester.pumpAndSettle();

    expect(find.text('Correction recorded.'), findsOneWidget);
    final views = await _movements(h, tester);
    expect(views, hasLength(3));
    final byKind = {for (final v in views) v.movement.kind: v.movement};
    expect(byKind[MovementKind.reversal]!.deltaMicros, -10000000);
    expect(byKind[MovementKind.reversal]!.reverses as String?, movementId);
    // Replacement is the newer receive row.
    final replacement = views
        .where(
          (v) =>
              v.movement.kind == MovementKind.receive &&
              v.movement.id as String != movementId,
        )
        .single;
    expect(replacement.movement.deltaMicros, 8000000);
    // One command wrote both.
    expect(
      replacement.movement.sourceCommandId,
      byKind[MovementKind.reversal]!.sourceCommandId,
    );
    // Original struck through in the log (reversedBy set).
    final original = views
        .where((v) => v.movement.id as String == movementId)
        .single;
    expect(original.reversedByMovementId, isNotNull);
  });

  testWidgets('reverse only skips the replacement', (tester) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    final movementId = await _seedPurchase(h, tester, itemId);

    await h.pumpApp(tester);
    await h.go(tester, '/movements/$movementId/correct');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'never happened',
    );
    await tester.tap(find.text('Reverse only (no replacement)'));
    await tester.pumpAndSettle();
    expect(find.byType(QuantityFormField), findsNothing);

    await tester.tap(find.text('Record correction'));
    await tester.pumpAndSettle();

    final views = await _movements(h, tester);
    expect(views, hasLength(2));
    expect(views.first.movement.kind, MovementKind.reversal);
    expect(views.first.movement.deltaMicros, -10000000);
  });

  testWidgets('a reason is required', (tester) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    final movementId = await _seedPurchase(h, tester, itemId);

    await h.pumpApp(tester);
    await h.go(tester, '/movements/$movementId/correct');

    await tester.tap(find.text('Record correction'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a reason for the correction'), findsOneWidget);
    expect(await _movements(h, tester), hasLength(1));
  });

  testWidgets('already-corrected target gets the state, not the form', (
    tester,
  ) async {
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    final movementId = await _seedPurchase(h, tester, itemId);
    await tester.runAsync(
      () => h
          .read(inventoryServiceProvider)
          .correct(movementId: movementId, reason: 'typo'),
    );

    await h.pumpApp(tester);
    await h.go(tester, '/movements/$movementId/correct');

    expect(find.textContaining('already been corrected'), findsOneWidget);
    expect(find.text('Record correction'), findsNothing);
  });
}
