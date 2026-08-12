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

Future<String> seedItem(
  AppHarness h, {
  String name = 'Tortillas',
  ItemUnit unit = ItemUnit.kg,
  Quantity? packSize,
}) => unwrap(
  h
      .read(catalogServiceProvider)
      .createItem(
        ItemDraft(
          name: name,
          unit: unit,
          packSize: packSize ?? Quantity.fromMicros(1000000),
        ),
      ),
);

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
