/// "Copy items from a previous event" (proposal §3): pick a past list,
/// confirm, done. The copy is ADDITIVE — what is already planned stays,
/// duplicates are counted rather than created, nothing is removed — and it
/// goes out through the ordinary create/update command, so these tests
/// finish by re-reading the saved event from the service.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/events/domain/event.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

/// Seeds three catalog items and a past event that planned all three.
Future<({String plates, String lemonade, String napkins, String eventId})>
_seedSpringFair(AppHarness h) async {
  final disposables = await folderIdByName(h, 'Disposables');
  final drinks = await folderIdByName(h, 'Drinks');
  final plates = await seedItem(h, name: 'Paper plates', folderId: disposables);
  final lemonade = await seedItem(h, name: 'Lemonade', folderId: drinks);
  final napkins = await seedItem(h, name: 'Napkins', folderId: disposables);
  final eventId = await seedEvent(
    h,
    name: 'Spring fair',
    date: '2026-05-01',
    itemIds: [plates, lemonade, napkins],
  );
  return (
    plates: plates,
    lemonade: lemonade,
    napkins: napkins,
    eventId: eventId,
  );
}

Future<void> _openCopySheet(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Copy items from a previous event'));
  await tester.tap(find.text('Copy items from a previous event'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('copying onto a new event brings the whole list over and '
      'reports what it added', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() => _seedSpringFair(h));

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Summer fair',
    );
    await _openCopySheet(tester);

    // The chooser says what each list is worth before it is chosen, and
    // marks the newest — the sort order becomes a suggestion.
    expect(
      find.text(
        'Its items are added to this event. '
        'Nothing already planned is removed.',
      ),
      findsOneWidget,
    );
    expect(find.text('2026-05-01 · 3 items · Most recent'), findsOneWidget);
    await tester.tap(find.text('Spring fair'));
    await tester.pumpAndSettle();

    // Pick, then confirm — the consequence is stated before the tap.
    expect(find.text('Copy from Spring fair?'), findsOneWidget);
    expect(find.text('Adds 3 items to this event.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Copy items'));
    await tester.pumpAndSettle();

    expect(find.text('Added 3 items'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Paper plates'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Lemonade'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Napkins'), findsOneWidget);

    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(find.text('Planned items (3)'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('copying onto an event that already has some of them adds only '
      'the rest, says so, and the merged list persists', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String summerId;
    await tester.runAsync(() async {
      final seeded = await _seedSpringFair(h);
      // Already planned by hand: the copy must not duplicate it.
      summerId = await seedEvent(
        h,
        name: 'Summer fair',
        date: '2026-08-20',
        itemIds: [seeded.plates],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$summerId/edit');
    await _openCopySheet(tester);
    await tester.tap(find.text('Spring fair'));
    await tester.pumpAndSettle();

    expect(
      find.text('Adds 2 items to this event. 1 is already on the list.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Copy items'));
    await tester.pumpAndSettle();

    expect(
      find.text('Added 2 items · 1 was already on the list'),
      findsOneWidget,
    );
    // Nothing was removed and nothing doubled.
    expect(find.widgetWithText(InputChip, 'Paper plates'), findsOneWidget);

    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();

    // Re-read from the service: the copy went out through UpdateEvent like
    // any other edit, so the saved event is the merged list in order.
    final detail = (await tester.runAsync(
      () => h.read(eventServiceProvider).watchEvent(summerId).first,
    ))!;
    expect(
      [for (final planned in detail.plannedItems) planned.name],
      ['Paper plates', 'Lemonade', 'Napkins'],
    );
    expect(detail.event.status, EventStatus.planned);
    await h.flushTimers(tester);
  });

  testWidgets('items archived since the old event are left behind and '
      'counted', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final seeded = await _seedSpringFair(h);
      await unwrap(
        h
            .read(catalogServiceProvider)
            .setArchived(itemId: seeded.napkins, archived: true),
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Summer fair',
    );
    await _openCopySheet(tester);

    // The chooser still describes the list as it WAS — three items.
    expect(find.text('2026-05-01 · 3 items · Most recent'), findsOneWidget);
    await tester.tap(find.text('Spring fair'));
    await tester.pumpAndSettle();

    expect(
      find.text('Adds 2 items to this event. 1 item no longer exists.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Copy items'));
    await tester.pumpAndSettle();

    expect(find.text('Added 2 items · 1 no longer exists'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Napkins'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('copying a list you already have explains instead of copying', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String summerId;
    await tester.runAsync(() async {
      final seeded = await _seedSpringFair(h);
      summerId = await seedEvent(
        h,
        name: 'Summer fair',
        date: '2026-08-20',
        itemIds: [seeded.plates, seeded.lemonade, seeded.napkins],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$summerId/edit');
    await _openCopySheet(tester);
    await tester.tap(find.text('Spring fair'));
    await tester.pumpAndSettle();

    expect(
      find.text('Everything on that list is already here.'),
      findsOneWidget,
    );
    // An explanation, not a failed action: there is nothing to confirm.
    expect(find.widgetWithText(TextButton, 'Copy items'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('a previous event with no items says so', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, name: 'Tortillas');
      await seedEvent(h, name: 'Rained-off picnic', date: '2026-04-02');
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await _openCopySheet(tester);
    expect(find.text('2026-04-02 · 0 items · Most recent'), findsOneWidget);
    await tester.tap(find.text('Rained-off picnic'));
    await tester.pumpAndSettle();

    expect(find.text('That event has no items to copy.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('with no previous event the offer is absent, not dead', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() => seedItem(h, name: 'Tortillas'));

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');

    expect(find.text('Copy items from a previous event'), findsNothing);
    // The rest of the planned-items section is untouched.
    expect(find.text('Add items'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('the chooser and its confirmation survive 200 % text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() => _seedSpringFair(h));

    await h.pumpApp(tester);
    await h.go(tester, '/events/new');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Summer fair',
    );
    // An overflow at 200 % scale throws and fails the test here.
    await _openCopySheet(tester);
    expect(find.text('2026-05-01 · 3 items · Most recent'), findsOneWidget);
    await tester.tap(find.text('Spring fair'));
    await tester.pumpAndSettle();

    expect(find.text('Adds 3 items to this event.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Copy items'));
    await tester.pumpAndSettle();
    expect(find.text('Added 3 items'), findsOneWidget);
    await h.flushTimers(tester);
  });
}
