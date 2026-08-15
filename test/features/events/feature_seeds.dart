/// Shared seeding helpers for the events + closeout widget tests. All data
/// goes through the REAL application services (the single write path) —
/// call these inside `tester.runAsync`, per the AppHarness contract.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/approval/domain/proposal.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/events/domain/event.dart';

import '../../support/app_harness.dart';

/// Unwraps a service [Result]; fails the test on an unexpected error.
Future<T> unwrap<T>(Future<Result<T>> future) async {
  final result = await future;
  return result.fold(
    (value) => value,
    (error) => fail('unexpected ${error.code}: ${error.message}'),
  );
}

/// Seeds an item in the shape the forms now produce: a counted thing with
/// a name. [unit] and [packSize] exist only to stage a migrated schema-v1
/// row; nothing in the product asks for them. [folderId] files the item on
/// creation (null = Unfiled).
Future<String> seedItem(
  AppHarness h, {
  String name = 'Tortillas',
  Quantity? servesPerUnit,
  Quantity openingCount = Quantity.zero,
  ItemUnit unit = ItemUnit.each,
  Quantity? packSize,
  String? folderId,
}) => unwrap(
  h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(
          name: name,
          servesPerUnit: servesPerUnit,
          unit: unit,
          packSize: packSize ?? Quantity.one,
          folderId: folderId,
        ),
        openingCount: openingCount,
      ),
);

/// Resolves one of the seeded starter folders (fresh workspaces carry the
/// eight from the proposal) — or any folder the test created — by name.
Future<String> folderIdByName(AppHarness h, String name) async {
  final folders = await h.read(catalogServiceProvider).watchFolders().first;
  return folders.firstWhere((folder) => folder.name == name).id.value;
}

/// Marks a folder "comes along to every event" through the real command
/// path, so EventService.createEvent pre-adds its live items.
Future<void> markFolderAlwaysPlanned(AppHarness h, String folderName) async {
  final folderId = await folderIdByName(h, folderName);
  await unwrap(
    h
        .read(catalogServiceProvider)
        .setFolderBasis(folderId: folderId, alwaysPlanned: true),
  );
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

Future<void> cancelEvent(
  AppHarness h,
  String eventId, {
  String reason = 'rained out',
}) => unwrap(h.read(eventServiceProvider).cancel(eventId, reason: reason));

/// Confirms revision 1 through the real service (event must be active).
Future<CommandReceipt> confirmCloseout(
  AppHarness h,
  String eventId, {
  required int exposure,
  List<CloseoutFormLine> lines = const [],
  String note = '',
}) => unwrap(
  h
      .read(closeoutServiceProvider)
      .confirm(
        CloseoutFormDraft(
          eventId: eventId,
          confirmedExposure: exposure,
          note: note,
          lines: lines,
        ),
      ),
);
