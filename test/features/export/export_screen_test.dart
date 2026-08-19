/// `/settings/export`: four rows and a sentence, each row saving one CSV
/// through the same [FileGateway] seam the backup flow uses — and the one
/// export that has to ask a question first asking it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/backup/presentation/file_gateway.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/export/presentation/export_screen.dart';

import '../../support/app_harness.dart';
import '../backup/backup_test_support.dart';
import 'export_test_support.dart';

Future<void> expireSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists all four exports with a labelled button each', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpScreen(tester, const ExportScreen());

    for (final title in const [
      'Items',
      'Events',
      "One event's count",
      'Recipes',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    // No icon-only actions (§9): every export has words on its button, and
    // they differ, so four buttons in a row are four distinct destinations.
    for (final label in const [
      'Save items…',
      'Save events…',
      'Choose an event…',
      'Save recipes…',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('saving items hands a dated CSV to the gateway and cleans up', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(
      () => seedItem(
        h,
        name: 'Lemonade',
        unitPrice: Money.fromCents(250),
        openingCount: Quantity.whole(12),
      ),
    );

    final gateway = FakeFileGateway();
    final container = containerWith(h, [
      fileGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    await pumpScreenWith(tester, container, const ExportScreen());

    await tapVisible(tester, find.text('Save items…'));
    // Waits for the CONFIRMATION, not just the hand-off: the scratch
    // session is disposed between the two, and that is what the last
    // expectation below is about.
    await settleUntil(
      tester,
      () => visible(find.textContaining('Saved as loadout-items-')),
      reason: 'items file saved confirmation',
    );

    final save = gateway.saves.single;
    expect(
      save.suggestedName,
      matches(RegExp(r'^loadout-items-\d{4}-\d{2}-\d{2}\.csv$')),
    );
    // The bytes Excel reads: BOM first, then the header, CRLF-terminated.
    expect(save.bytes.take(3), [0xEF, 0xBB, 0xBF]);
    // (Dart's UTF-8 decoder eats the BOM, which is why the check above is
    // on the raw bytes.)
    final text = utf8.decode(save.bytes);
    expect(text, startsWith('Folder,Item,Amount on hand,'));
    expect(text, contains('Lemonade,12,,2.50,30.00'));
    expect(text, contains('\r\n'));
    // The scratch session went with the hand-off: no CSV is left in app
    // storage after the dialog closes.
    expect(File(save.sourcePath).existsSync(), isFalse);
    await expireSnackbars(tester);
  });

  testWidgets('a cancelled save leaves nothing behind and says so', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    final gateway = FakeFileGateway()..cancelSave = true;
    final container = containerWith(h, [
      fileGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    await pumpScreenWith(tester, container, const ExportScreen());

    await tapVisible(tester, find.text('Save recipes…'));
    await settleUntil(
      tester,
      () => visible(find.text('Nothing was saved.')),
      reason: 'cancelled-save notice',
    );
    expect(gateway.saves, isEmpty);
    await expireSnackbars(tester);
  });

  testWidgets('the count export asks which event, then names the file for it', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final cups = await seedItem(
        h,
        name: 'Cups',
        unitPrice: Money.fromCents(200),
      );
      final eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [cups],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [CloseoutFormLine(itemId: cups, depletion: Quantity.whole(30))],
      );
    });

    final gateway = FakeFileGateway();
    final container = containerWith(h, [
      fileGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    await pumpScreenWith(tester, container, const ExportScreen());

    await tapVisible(tester, find.text('Choose an event…'));
    await tester.pumpAndSettle();
    expect(find.text('Which event?'), findsOneWidget);
    await tapVisible(tester, find.text('Street fair'));
    await tester.pumpAndSettle();
    await settleUntil(
      tester,
      () => gateway.saves.isNotEmpty,
      reason: 'count file handed to the save dialog',
    );

    final save = gateway.saves.single;
    // Named for the event and the day it describes: a count file that says
    // neither is an orphan the moment it is emailed on.
    expect(save.suggestedName, 'loadout-count-street-fair-2026-08-10.csv');
    expect(save.bytes.take(3), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(save.bytes);
    expect(
      text,
      startsWith('Item,Counted,Expected,Variance,Price each,Line cost\r\n'),
    );
    expect(text, contains('Cups,30,,,2.00,60.00'));
    await expireSnackbars(tester);
  });

  testWidgets('with nothing counted the count export says so and saves none', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    final gateway = FakeFileGateway();
    final container = containerWith(h, [
      fileGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    await pumpScreenWith(tester, container, const ExportScreen());

    await tapVisible(tester, find.text('Choose an event…'));
    await tester.pumpAndSettle();
    expect(find.text('Which event?'), findsNothing);
    expect(
      find.text(
        'No event has been counted yet, so there is nothing to '
        'export.',
      ),
      findsOneWidget,
    );
    expect(gateway.saves, isEmpty);
    await expireSnackbars(tester);
  });
}
