/// Seeding helpers for the export tests, deliberately self-contained: the
/// export feature has no business breaking because another feature's shared
/// fixtures moved. Everything goes through the REAL services (the single
/// write path) and must run inside `tester.runAsync`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/unit_ratio.dart';
import 'package:loadout/features/approval/domain/proposal.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../../support/app_harness.dart';

/// Unwraps a service [Result]; fails the test on an unexpected error.
Future<T> unwrap<T>(Future<Result<T>> future) async {
  final result = await future;
  return result.fold(
    (value) => value,
    (error) => fail('unexpected ${error.code}: ${error.message}'),
  );
}

Future<String> seedItem(
  AppHarness h, {
  required String name,
  Money? unitPrice,
  String? unitLabel,
  String? folderId,
  Quantity? servesPerUnit,
  UnitRatio? perPersonRatio,
  Quantity? perEventBaseline,
  Quantity openingCount = Quantity.zero,
  String? barcode,
}) => unwrap(
  h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(
          name: name,
          unitPrice: unitPrice,
          unitLabel: unitLabel,
          folderId: folderId,
          servesPerUnit: servesPerUnit,
          perPersonRatio: perPersonRatio,
          perEventBaseline: perEventBaseline,
        ),
        openingCount: openingCount,
        barcode: barcode,
      ),
);

Future<void> archiveItem(AppHarness h, String itemId) => unwrap(
  h.read(catalogServiceProvider).setArchived(itemId: itemId, archived: true),
);

/// Resolves one of the eight starter folders (or any created folder) by name.
Future<String> folderIdByName(AppHarness h, String name) async {
  final folders = await h.read(catalogServiceProvider).watchFolders().first;
  return folders.firstWhere((folder) => folder.name == name).id.value;
}

Future<String> seedEvent(
  AppHarness h, {
  required String name,
  required String date,
  int? exposure,
  List<String> itemIds = const [],
}) => unwrap(
  h
      .read(eventServiceProvider)
      .createEvent(
        EventDraft(
          name: name,
          scheduledDate: date,
          plannedExposure: exposure,
          plannedItemIds: itemIds,
        ),
      ),
);

Future<void> activateEvent(AppHarness h, String eventId) =>
    unwrap(h.read(eventServiceProvider).activate(eventId));

Future<void> generateForecast(AppHarness h, String eventId) =>
    unwrap(h.read(forecastServiceProvider).generateSnapshot(eventId));

/// Confirms revision 1 through the real service (event must be active).
Future<CommandReceipt> confirmCloseout(
  AppHarness h,
  String eventId, {
  required int exposure,
  List<CloseoutFormLine> lines = const [],
}) => unwrap(
  h
      .read(closeoutServiceProvider)
      .confirm(
        CloseoutFormDraft(
          eventId: eventId,
          confirmedExposure: exposure,
          lines: lines,
        ),
      ),
);

/// A v5 decoupled recipe: lines given verbatim, so free and linked lines mix.
Future<String> seedRecipe(
  AppHarness h, {
  required String name,
  required List<RecipeFormLine> lines,
  int yieldWhole = 10,
  String? yieldLabel,
}) => unwrap(
  h
      .read(recipeServiceProvider)
      .createRecipe(
        RecipeFormDraft(
          name: name,
          yieldQuantity: Quantity.whole(yieldWhole),
          yieldLabel: yieldLabel,
          lines: lines,
        ),
      ),
);

/// Splits a CSV document into its rows, BOM stripped and CRLF asserted.
///
/// Deliberately naive — it does not unquote — because these tests assert the
/// EXACT bytes a row was written as, quotes and all.
List<String> csvRows(String document) {
  expect(document.startsWith('\u{FEFF}'), isTrue, reason: 'missing BOM');
  final body = document.substring(1);
  expect(body.endsWith('\r\n'), isTrue, reason: 'missing final CRLF');
  return body.substring(0, body.length - 2).split('\r\n');
}
