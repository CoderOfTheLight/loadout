/// "Scan items in" price entry (v7): the UNKNOWN-barcode "New item" sheet
/// carries an optional 'Price each' field, and the one-command create
/// stores it as exact cents alongside the barcode and opening count. The
/// KNOWN-item restock sheet asks no price — restocking is not repricing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/features/catalog/application/barcode_scan_service.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';

import 'barcode_scan_support.dart';

void main() {
  testWidgets('the new-item sheet creates the item WITH the typed price', (
    tester,
  ) async {
    final fake = FakeBarcodeScanService(
      available: true,
      script: [const BarcodeScan(payload: 'NEW-9', symbology: 'ean13')],
    );
    final h = await startWithScanner(tester, fake);
    await h.pumpApp(tester);
    await h.go(tester, '/items/scan-in');

    // The unknown barcode opened the New item sheet with the price field.
    expect(find.text('New item'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('scan-new-name')), 'Cold brew');
    await tester.enterText(find.byKey(const Key('scan-new-quantity')), '3');
    await tester.enterText(find.byKey(const Key('scan-new-price')), '4.25');
    await tester.tap(find.byKey(const Key('sheet-done')));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    final summary = items!.single;
    expect(summary.item.name, 'Cold brew');
    expect(summary.item.unitPrice, Money.fromCents(425));
    expect(summary.item.barcode, 'NEW-9');
    expect(summary.onHandMicros, 3000000);

    await expireSnackbars(tester);
    await h.flushTimers(tester);
  });

  testWidgets('the price is optional: a blank field creates an unpriced '
      'item', (tester) async {
    final fake = FakeBarcodeScanService(
      available: true,
      script: [const BarcodeScan(payload: 'NEW-10', symbology: 'ean13')],
    );
    final h = await startWithScanner(tester, fake);
    await h.pumpApp(tester);
    await h.go(tester, '/items/scan-in');

    await tester.enterText(find.byKey(const Key('scan-new-name')), 'Stickers');
    await tester.tap(find.byKey(const Key('sheet-done')));
    await tester.pumpAndSettle();

    final items = await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    );
    expect(items!.single.item.unitPrice, isNull);

    await expireSnackbars(tester);
    await h.flushTimers(tester);
  });
}
