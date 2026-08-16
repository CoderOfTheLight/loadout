/// "Scan items in" widget tests over a fake [BarcodeScanService] (the real
/// channel needs a device): the overflow entry hides until the probe says
/// yes; a KNOWN barcode's sheet records a RECEIVE movement (note 'Scanned
/// in') asserted against the ledger; an UNKNOWN barcode's sheet creates the
/// item WITH the barcode, opening count, and chosen folder in one command;
/// 'camera_denied' points at Settings inline on the hub; a cancelled scan
/// lands on the hub silently.
library;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/widgets/folder_chip.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/application/barcode_scan_service.dart';
import 'package:loadout/features/catalog/presentation/item_list_screen.dart';
import 'package:loadout/features/catalog/presentation/scan_items_in_screen.dart';

import 'barcode_scan_support.dart';

void main() {
  testWidgets('overflow entry stays hidden when the probe says no', (
    tester,
  ) async {
    final h = await startWithScanner(tester, FakeBarcodeScanService());

    await h.pumpScreen(tester, const ItemListScreen());
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Delete all items…'), findsOneWidget);
    expect(find.text('Scan items in…'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets(
    'the entry shows when the probe says yes; a cancelled scan lands on '
    'the hub silently, and Done returns to the items list',
    (tester) async {
      // Empty script: every scan resolves null (owner cancelled).
      final fake = FakeBarcodeScanService(available: true);
      final h = await startWithScanner(tester, fake);
      await h.pumpApp(tester);
      await h.go(tester, '/items');

      await tapOverflowEntry(tester, 'Scan items in…');

      // Arrival opened the scanner once; the cancel landed on the hub with
      // no snackbar and no recorded rows.
      expect(fake.scanCalls, 1);
      expect(find.byType(ScanItemsInScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Nothing scanned in yet'), findsOneWidget);

      // The big 'Scan next' re-opens the scanner — a mis-dismissed scanner
      // never strands the owner.
      await tester.tap(find.byKey(const Key('scan-next')));
      await tester.pumpAndSettle();
      expect(fake.scanCalls, 2);
      expect(find.byType(ScanItemsInScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan-done')));
      await tester.pumpAndSettle();
      expect(find.byType(ItemListScreen), findsOneWidget);
      await h.flushTimers(tester);
    },
  );

  testWidgets(
    'a known barcode runs the restock sheet: identity + on-hand shown, '
    'submit records a receive movement noted "Scanned in"',
    (tester) async {
      final fake = FakeBarcodeScanService(
        available: true,
        script: [const BarcodeScan(payload: 'BAR-1', symbology: 'ean13')],
      );
      final h = await startWithScanner(tester, fake);
      late String itemId;
      await tester.runAsync(() async {
        final folders = await folderIdsByName(h);
        itemId = await seedItem(
          h,
          'Beef burgers',
          folderId: folders['Drinks'],
          openingWhole: 6,
          barcode: 'BAR-1',
        );
      });
      await h.pumpApp(tester);
      await h.go(tester, '/items');

      await tapOverflowEntry(tester, 'Scan items in…');

      // The sheet: name, FolderChip + folder name, current on-hand, and the
      // quantity field.
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Beef burgers')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(FolderChip)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Drinks')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('You have 6')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('scan-arrived-quantity')),
        '4',
      );
      await tester.tap(find.byKey(const Key('scan-add-next')));
      await tester.pumpAndSettle();

      // '& scan next' re-opened the scanner (script exhausted → cancel →
      // hub), the snackbar names the item, and the session summary carries
      // the running row.
      expect(fake.scanCalls, 2);
      expect(find.text('Added 4 × "Beef burgers"'), findsOneWidget);
      expect(find.byKey(ValueKey('session-row-$itemId')), findsOneWidget);

      // The ledger: exactly one receive, +4, noted 'Scanned in'.
      await tester.runAsync(() async {
        final db = h.read(appDatabaseProvider);
        expect(
          await db.ledgerDao.onHandMicros(itemId),
          Quantity.whole(10).micros,
        );
        final rows = await db
            .customSelect(
              'SELECT note, delta_micros FROM inventory_movements '
              "WHERE item_id = ?1 AND kind = 'receive'",
              variables: [Variable<String>(itemId)],
            )
            .get();
        expect(rows, hasLength(1));
        expect(rows.single.read<String>('note'), 'Scanned in');
        expect(rows.single.read<int>('delta_micros'), Quantity.whole(4).micros);
      });

      await expireSnackbars(tester);
      await h.flushTimers(tester);
    },
  );

  testWidgets(
    'an unknown barcode runs the New item sheet: created WITH the barcode, '
    'the opening count, and the chosen folder; Done returns to items',
    (tester) async {
      final fake = FakeBarcodeScanService(
        available: true,
        script: [const BarcodeScan(payload: 'NEW-9', symbology: 'ean13')],
      );
      final h = await startWithScanner(tester, fake);
      await h.pumpApp(tester);
      await h.go(tester, '/items');

      await tapOverflowEntry(tester, 'Scan items in…');
      expect(find.text('New item'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('scan-new-name')),
        'Lemonade',
      );
      await tester.enterText(find.byKey(const Key('scan-new-quantity')), '12');
      await tester.tap(find.byKey(const Key('scan-new-folder')));
      await tester.pumpAndSettle();
      await tapFolderPickerEntry(tester, 'Drinks');

      await tester.tap(find.byKey(const Key('sheet-done')));
      await tester.pumpAndSettle();

      // Done: no re-scan, back on the items list, named snackbar.
      expect(fake.scanCalls, 1);
      expect(find.byType(ItemListScreen), findsOneWidget);
      expect(find.text('Created "Lemonade"'), findsOneWidget);

      await tester.runAsync(() async {
        final item = await h
            .read(catalogServiceProvider)
            .itemByBarcode('NEW-9');
        expect(item, isNotNull);
        expect(item!.name, 'Lemonade');
        final folders = await folderIdsByName(h);
        expect(item.folderId?.value, folders['Drinks']);
        expect(
          await h
              .read(appDatabaseProvider)
              .ledgerDao
              .onHandMicros(item.id.value),
          Quantity.whole(12).micros,
        );
      });

      await expireSnackbars(tester);
      await h.flushTimers(tester);
    },
  );

  testWidgets('camera_denied shows the inline Settings pointer on the hub', (
    tester,
  ) async {
    final fake = FakeBarcodeScanService(
      available: true,
      script: [const BarcodeScanException('camera_denied')],
    );
    final h = await startWithScanner(tester, fake);
    await h.pumpApp(tester);
    await h.go(tester, '/items');

    await tapOverflowEntry(tester, 'Scan items in…');

    expect(find.byKey(const Key('camera-denied-note')), findsOneWidget);
    expect(
      find.text('Camera access is off. Turn it on in Settings to scan.'),
      findsOneWidget,
    );
    // Inline, not a snackbar — and never the channel code.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('camera_denied'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('other failure codes say so content-free in a snackbar', (
    tester,
  ) async {
    final fake = FakeBarcodeScanService(
      available: true,
      script: [const BarcodeScanException('camera_failed')],
    );
    final h = await startWithScanner(tester, fake);
    await h.pumpApp(tester);
    await h.go(tester, '/items');

    await tapOverflowEntry(tester, 'Scan items in…');

    expect(find.text("Couldn't open the camera. Try again."), findsOneWidget);
    expect(find.byKey(const Key('camera-denied-note')), findsNothing);
    expect(find.textContaining('camera_failed'), findsNothing);

    await expireSnackbars(tester);
    await h.flushTimers(tester);
  });
}
