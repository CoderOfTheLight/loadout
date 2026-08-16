/// Shared fake scanner + seeding helpers for the barcode widget tests
/// (`scan_items_in_test.dart`, `item_edit_barcode_test.dart`), mirroring
/// the fake-service pattern of `recipe_scan_ingredients_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/application/barcode_scan_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';

import '../../support/app_harness.dart';

/// Scripted [BarcodeScanService]: each `scanOne` pops the next entry —
/// a [BarcodeScan] (detected), a [BarcodeScanException] (thrown), or null
/// (owner cancelled). An exhausted script always cancels, so a re-opened
/// scanner ends every test back on the hub.
final class FakeBarcodeScanService implements BarcodeScanService {
  FakeBarcodeScanService({
    this.available = false,
    List<Object?> script = const [],
  }) : _script = List.of(script);

  final bool available;
  final List<Object?> _script;
  int scanCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BarcodeScan?> scanOne() async {
    scanCalls++;
    if (_script.isEmpty) return null;
    final next = _script.removeAt(0);
    if (next is BarcodeScanException) throw next;
    return next as BarcodeScan?;
  }
}

/// Unwraps an [Ok] or fails the test with the error's code + message.
T unwrap<T>(Result<T> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => fail('expected Ok, got ${error.code}: ${error.message}'),
};

/// Boots a workspace harness with [fake] installed over the scan channel.
/// Call inside the test body — `AppHarness.start` runs in `runAsync` here.
Future<AppHarness> startWithScanner(
  WidgetTester tester,
  FakeBarcodeScanService fake,
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

/// Creates an item through the real [CatalogService] — optionally with an
/// opening count and a linked barcode (the one-command create). Returns the
/// itemId. Call inside `tester.runAsync`.
Future<String> seedItem(
  AppHarness h,
  String name, {
  String? folderId,
  int openingWhole = 0,
  String? barcode,
}) async => unwrap(
  await h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(name: name, folderId: folderId),
        openingCount: Quantity.whole(openingWhole),
        barcode: barcode,
      ),
);

/// Fresh workspaces seed the eight starter folders; this maps their names
/// (and any added later) to ids.
Future<Map<String, String>> folderIdsByName(AppHarness h) async {
  final folders = await h.read(catalogServiceProvider).watchFolders().first;
  return {for (final folder in folders) folder.name: folder.id.value};
}

/// Opens the Items screen's app-bar overflow and taps [entry].
Future<void> tapOverflowEntry(WidgetTester tester, String entry) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

/// Scrolls the OPEN folder-picker sheet until [label] is visible and taps
/// it (the starter folders push later entries below the sheet's fold).
Future<void> tapFolderPickerEntry(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.dragUntilVisible(
    target,
    find.byType(ListView).last,
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}

/// Lets an on-screen snackbar's timer expire so the test ends clean.
Future<void> expireSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}
