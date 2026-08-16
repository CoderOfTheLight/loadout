/// Item picker sheet (v5 amount ruling): the inline on-hand amount wears
/// the item's display unit label — "12 packages" — while a label-less item
/// stays a bare number and a legacy measured row keeps its REAL unit
/// (never masked by a label).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/inventory/presentation/item_picker_sheet.dart';

import '../../support/app_harness.dart';

class _SheetHost extends StatelessWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showItemPickerSheet(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('amounts wear their display labels; legacy units win', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final service = h.read(catalogServiceProvider);
      final labeled = await service.createItem(
        const ItemDraft(name: 'Snack packs', unitLabel: 'packages'),
        openingCount: Quantity.whole(12),
      );
      expect(labeled, isA<Ok<String>>());
      final bare = await service.createItem(
        const ItemDraft(name: 'Rolls'),
        openingCount: Quantity.whole(3),
      );
      expect(bare, isA<Ok<String>>());
      // A migrated schema-v1 measured row that also carries a label: the
      // real unit stays glued to the number — never masked.
      final legacy = await service.createItem(
        const ItemDraft(name: 'Mince', unit: ItemUnit.kg, unitLabel: 'bags'),
        openingCount: Quantity.whole(5),
      );
      expect(legacy, isA<Ok<String>>());
    });

    await h.pumpScreen(tester, const _SheetHost());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('12 packages'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5 kg'), findsOneWidget);
    expect(find.textContaining('bags'), findsNothing);

    // Close the sheet so its providers dispose before the test ends.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });
}
