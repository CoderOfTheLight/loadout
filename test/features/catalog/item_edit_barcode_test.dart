/// ItemEditScreen barcode row (v6) over a fake [BarcodeScanService]:
/// 'Scan barcode' links immediately through `setItemBarcode` and shows the
/// payload as the owner's own caption; a payload another live item carries
/// surfaces the validator's refusal as a plain snackbar; 'Remove' clears
/// behind its confirm; with no barcode and no scanner there is no row at
/// all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/catalog/application/barcode_scan_service.dart';

import 'barcode_scan_support.dart';

void main() {
  testWidgets('Scan barcode links the payload and shows it as the caption', (
    tester,
  ) async {
    final fake = FakeBarcodeScanService(
      available: true,
      script: [const BarcodeScan(payload: 'EAN-1', symbology: 'ean13')],
    );
    final h = await startWithScanner(tester, fake);
    late String itemId;
    await tester.runAsync(() async {
      itemId = await seedItem(h, 'Cups');
    });
    await h.pumpApp(tester);
    await h.go(tester, '/items/$itemId/edit');

    final scanButton = find.byKey(const Key('scan-barcode'));
    await tester.ensureVisible(scanButton);
    await tester.pumpAndSettle();
    await tester.tap(scanButton);
    await tester.pumpAndSettle();

    // The row flips to linked (plus the confirming snackbar), the caption
    // shows the payload — her own data on her own screen.
    expect(find.text('Barcode linked'), findsWidgets);
    expect(find.byKey(const Key('barcode-caption')), findsOneWidget);
    expect(find.text('EAN-1'), findsOneWidget);
    expect(scanButton, findsNothing);

    await tester.runAsync(() async {
      final item = await h.read(catalogServiceProvider).itemByBarcode('EAN-1');
      expect(item?.id.value, itemId);
    });

    await expireSnackbars(tester);
    await h.flushTimers(tester);
  });

  testWidgets(
    'a payload another live item carries is refused with a plain snackbar',
    (tester) async {
      final fake = FakeBarcodeScanService(
        available: true,
        script: [const BarcodeScan(payload: 'DUP-1', symbology: 'ean13')],
      );
      final h = await startWithScanner(tester, fake);
      late String holderId;
      late String otherId;
      await tester.runAsync(() async {
        holderId = await seedItem(h, 'Plates', barcode: 'DUP-1');
        otherId = await seedItem(h, 'Napkins');
      });
      await h.pumpApp(tester);
      await h.go(tester, '/items/$otherId/edit');

      final scanButton = find.byKey(const Key('scan-barcode'));
      await tester.ensureVisible(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(scanButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Another item already has this barcode'),
        findsOneWidget,
      );
      // Still unlinked: the scan affordance stays, and the payload stays
      // with its original owner.
      expect(scanButton, findsOneWidget);
      expect(find.text('Barcode linked'), findsNothing);
      await tester.runAsync(() async {
        final item = await h
            .read(catalogServiceProvider)
            .itemByBarcode('DUP-1');
        expect(item?.id.value, holderId);
      });

      await expireSnackbars(tester);
      await h.flushTimers(tester);
    },
  );

  testWidgets(
    'Remove clears the barcode behind its confirm; with no barcode and no '
    'scanner the row disappears entirely',
    (tester) async {
      // Scanner unavailable: the linked row must still show (Remove never
      // needs a camera).
      final h = await startWithScanner(tester, FakeBarcodeScanService());
      late String itemId;
      await tester.runAsync(() async {
        itemId = await seedItem(h, 'Ice packs', barcode: 'GONE-1');
      });
      await h.pumpApp(tester);
      await h.go(tester, '/items/$itemId/edit');

      final removeButton = find.byKey(const Key('remove-barcode'));
      await tester.ensureVisible(removeButton);
      await tester.pumpAndSettle();
      expect(find.text('Barcode linked'), findsOneWidget);
      expect(find.text('GONE-1'), findsOneWidget);

      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      expect(find.text('Remove this barcode?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Barcode removed'), findsOneWidget);
      expect(find.text('Barcode linked'), findsNothing);
      // No barcode + no scanner = no row at all.
      expect(find.byKey(const Key('scan-barcode')), findsNothing);
      expect(removeButton, findsNothing);

      await tester.runAsync(() async {
        expect(
          await h.read(catalogServiceProvider).itemByBarcode('GONE-1'),
          isNull,
        );
      });

      await expireSnackbars(tester);
      await h.flushTimers(tester);
    },
  );
}
