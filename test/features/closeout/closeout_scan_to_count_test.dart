/// Scan-to-count on the closeout over a fake [BarcodeScanService] (the
/// real one needs a device camera): the app-bar action hides when the
/// probe says no; a scan resolves the item, opens the "How many came
/// back?" sheet, and saves through the SAME edit path typing uses — the
/// planned load fills a blank loaded, waste defaults to 0 only on a sheet
/// save, and the draft carries it all; a barcode nobody linked and an item
/// not on this event's list each say so and re-open the scanner; scanner
/// failures speak content-free, with 'camera_denied' pointing at Settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/application/barcode_scan_service.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

final class _FakeBarcodeScanService implements BarcodeScanService {
  _FakeBarcodeScanService({
    this.available = true,
    this.payloads = const [],
    this.failure,
  });

  final bool available;

  /// What successive scans deliver, in order; a null entry — or running
  /// past the end — is the owner cancelling.
  final List<String?> payloads;

  /// When set, every scan throws this instead.
  final BarcodeScanException? failure;

  int scanCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BarcodeScan?> scanOne() async {
    final index = scanCalls++;
    final failure = this.failure;
    if (failure != null) throw failure;
    final payload = index < payloads.length ? payloads[index] : null;
    return payload == null
        ? null
        : BarcodeScan(payload: payload, symbology: 'org.gs1.EAN-13');
  }
}

Future<AppHarness> _startWith(
  WidgetTester tester,
  _FakeBarcodeScanService fake,
) async {
  final h = (await tester.runAsync(
    () => AppHarness.start(
      state: AppHarnessState.workspace,
      overrides: [barcodeScanServiceProvider.overrideWithValue(fake)],
    ),
  ))!;
  addTearDown(h.dispose);
  return h;
}

/// One planned Tortillas line on an active event; returns (item, event).
Future<(String, String)> _seedPlannedLine(
  AppHarness h,
  WidgetTester tester, {
  String? barcode,
}) async {
  late String item;
  late String eventId;
  await tester.runAsync(() async {
    item = await seedItem(h);
    if (barcode != null) {
      await unwrap(
        h
            .read(catalogServiceProvider)
            .setItemBarcode(itemId: item, barcode: barcode),
      );
    }
    eventId = await seedEvent(
      h,
      name: 'Market',
      date: '2026-08-10',
      exposure: 150,
      itemIds: [item],
    );
    await activateEvent(h, eventId);
  });
  return (item, eventId);
}

void main() {
  testWidgets('the scan action stays hidden when the probe says no', (
    tester,
  ) async {
    final fake = _FakeBarcodeScanService(available: false);
    final h = await _startWith(tester, fake);
    final (_, eventId) = await _seedPlannedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    expect(find.byKey(const Key('scan-to-count')), findsNothing);
    expect(fake.scanCalls, 0);
    await h.flushTimers(tester);
  });

  testWidgets('a scan-count with a planned load completes the line: loaded '
      'fills, waste defaults to 0, and the draft carries it', (tester) async {
    final fake = _FakeBarcodeScanService(payloads: ['B-1']);
    final h = await _startWith(tester, fake);
    final (item, eventId) = await _seedPlannedLine(h, tester, barcode: 'B-1');
    await tester.runAsync(() async {
      final view = await unwrap(
        h.read(forecastServiceProvider).generateSnapshot(eventId),
      );
      await unwrap(
        h
            .read(forecastServiceProvider)
            .setOverride(
              snapshotId: view.id.value,
              itemId: item,
              load: Quantity.whole(12),
              reason: 'counted the crate',
            ),
      );
    });

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    // The Unfiled section header still shows its fraction.
    expect(find.text('0 of 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-to-count')));
    await tester.pumpAndSettle();

    // The compact sheet: name, one count field, and the waste caption —
    // shown because this save can complete the line.
    expect(
      find.widgetWithText(TextFormField, 'How many came back?'),
      findsOneWidget,
    );
    expect(
      find.text('Waste counts as 0 unless you set it on the card.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many came back?'),
      '2',
    );
    await tester.pump();
    await tester.tap(find.text('Save & scan next'));
    await tester.pumpAndSettle();

    // The loop re-opened the scanner; the (fake) cancel ended it.
    expect(fake.scanCalls, 2);

    // Loaded filled from the planned load, waste defaulted to 0, so the
    // worksheet derives 12 − 2 − 0 and the line confirms — and the section
    // header flipped to Done through the normal mechanics.
    expect(find.text('Depletion: 10'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // The save rode the same debounced autosave typing does.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    final line = draft!.lines.single;
    expect(line.loaded!.micros, 12000000);
    expect(line.returned!.micros, 2000000);
    expect(line.waste!.micros, 0);
    expect(line.depletion!.micros, 10000000);
    expect(line.skipped, isFalse);
    await h.flushTimers(tester);
  });

  testWidgets('without a planned load the save sets returned only — the '
      "line stays in progress, and 'Done' ends the loop", (tester) async {
    final fake = _FakeBarcodeScanService(payloads: ['B-2']);
    final h = await _startWith(tester, fake);
    final (_, eventId) = await _seedPlannedLine(h, tester, barcode: 'B-2');

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.tap(find.byKey(const Key('scan-to-count')));
    await tester.pumpAndSettle();

    // No loaded value exists and none will fill: no waste caption.
    expect(find.textContaining('Waste counts as 0'), findsNothing);

    // The count field takes fractions.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many came back?'),
      '1 1/2',
    );
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // 'Done' saved and stopped — the scanner never re-opened.
    expect(fake.scanCalls, 1);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    final line = draft!.lines.single;
    expect(line.returned!.micros, 1500000);
    expect(line.loaded, isNull);
    expect(line.waste, isNull);
    expect(line.depletion, isNull);
    await h.flushTimers(tester);
  });

  testWidgets("an item that isn't planned on this event says so and "
      're-opens the scanner', (tester) async {
    final fake = _FakeBarcodeScanService(payloads: ['B-SALSA']);
    final h = await _startWith(tester, fake);
    final (_, eventId) = await _seedPlannedLine(h, tester);
    await tester.runAsync(() async {
      final salsa = await seedItem(h, name: 'Salsa');
      await unwrap(
        h
            .read(catalogServiceProvider)
            .setItemBarcode(itemId: salsa, barcode: 'B-SALSA'),
      );
    });

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.tap(find.byKey(const Key('scan-to-count')));
    await tester.pumpAndSettle();

    expect(find.text('"Salsa" isn\'t on this event\'s list.'), findsOneWidget);
    expect(find.text('How many came back?'), findsNothing);
    // The loop went back to the scanner; the cancel ended it.
    expect(fake.scanCalls, 2);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('a barcode nobody linked says so and re-opens the scanner', (
    tester,
  ) async {
    final fake = _FakeBarcodeScanService(payloads: ['UNKNOWN']);
    final h = await _startWith(tester, fake);
    final (_, eventId) = await _seedPlannedLine(h, tester, barcode: 'B-1');

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.tap(find.byKey(const Key('scan-to-count')));
    await tester.pumpAndSettle();

    expect(find.text("That barcode isn't linked to any item."), findsOneWidget);
    expect(fake.scanCalls, 2);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets("'camera_denied' points at Settings and stops the loop", (
    tester,
  ) async {
    final fake = _FakeBarcodeScanService(
      failure: const BarcodeScanException('camera_denied'),
    );
    final h = await _startWith(tester, fake);
    final (_, eventId) = await _seedPlannedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.tap(find.byKey(const Key('scan-to-count')));
    await tester.pumpAndSettle();

    expect(
      find.text('Camera access is off. Turn it on in Settings.'),
      findsOneWidget,
    );
    expect(fake.scanCalls, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('any other scanner failure speaks content-free', (tester) async {
    final fake = _FakeBarcodeScanService(
      failure: const BarcodeScanException('unavailable'),
    );
    final h = await _startWith(tester, fake);
    final (_, eventId) = await _seedPlannedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.tap(find.byKey(const Key('scan-to-count')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't open the camera. Try again."), findsOneWidget);
    // Never the channel code.
    expect(find.textContaining('unavailable'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });
}
