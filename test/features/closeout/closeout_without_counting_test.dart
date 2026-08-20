/// Finishing an event WITHOUT counting it (owner: "needs the option to
/// closeout without doing inventory").
///
/// This is not a special write path: `CommandValidator._closeoutShared`
/// requires only a confirmed exposure in 1..1000000 and validates each line
/// if present, so a closeout with an EMPTY line list is a real closeout. The
/// screen therefore submits one through the ordinary
/// `CloseoutService.confirm`, and everything downstream — the closed event,
/// the deleted draft, the report — behaves as it always did.
///
/// What is pinned here: where the way out lives (the app-bar overflow, not a
/// second big button), that it confirms first in words that say what is
/// gained and lost, that it takes the headcount rather than sending her back
/// for it, that Cancel changes nothing, that the record it writes is a real
/// closeout with zero lines, that the report says so honestly, and that a
/// PARTIAL count can still be finished in one tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/features/closeout/presentation/closeout_report_screen.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';
import 'package:loadout/features/events/domain/event.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

/// An active event with [itemNames] planned on it.
Future<String> _seedEvent(
  AppHarness h,
  WidgetTester tester, {
  List<String> itemNames = const ['Tortillas'],
  int? exposure = 150,
}) async {
  late String eventId;
  await tester.runAsync(() async {
    final itemIds = <String>[];
    for (final name in itemNames) {
      itemIds.add(await seedItem(h, name: name));
    }
    eventId = await seedEvent(
      h,
      name: 'Market',
      date: '2026-08-10',
      exposure: exposure,
      itemIds: itemIds,
    );
    await activateEvent(h, eventId);
  });
  return eventId;
}

/// Opens the screen's app-bar overflow and picks [item] from it.
Future<void> _fromScreenOverflow(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const Key('closeout-overflow')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('"Close without counting" lives in the app-bar overflow, '
      'confirms in plain words, writes a closeout with zero lines and the '
      'right headcount, and lands on a report that says nothing was counted', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedEvent(h, tester);

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // It is NOT a second big button beside the one that finishes a count.
    expect(find.text('Finish closeout'), findsOneWidget);
    expect(find.text('Close without counting'), findsNothing);

    await _fromScreenOverflow(tester, 'Close without counting');

    // The confirmation says what is gained and what is lost, in her words.
    expect(find.text('Close this event without counting?'), findsOneWidget);
    expect(
      find.text(
        'It records that the event happened and how many people came. '
        "Loadout won't learn anything about what got used, so future "
        "packing lists won't improve from this one.",
      ),
      findsOneWidget,
    );
    // The headcount is already on the screen, so it is confirmed, not asked.
    expect(find.text('150 attendance will be recorded.'), findsOneWidget);
    expect(
      find.byKey(const Key('close-without-counting-exposure')),
      findsNothing,
    );
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Close without counting'),
    );
    await tester.pumpAndSettle();

    // It lands on the same artifact a full count produces, which says
    // plainly that there is nothing in it.
    expect(find.text('Closeout report'), findsOneWidget);
    expect(find.text('Nothing was counted for this event.'), findsOneWidget);
    expect(find.text('CONFIRMED ATTENDANCE'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    // No totals, no variance table, no item list — there is no count.
    expect(find.text('TOTAL SPENT'), findsNothing);
    expect(find.text('AGAINST THE FORECAST'), findsNothing);
    expect(find.text('WHAT YOU USED'), findsNothing);
    expect(find.text('Tortillas'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() async {
      // A real closeout: revision 1, the headcount, and no lines at all.
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      expect(revisions, hasLength(1));
      expect(revisions.single.revision, 1);
      expect(revisions.single.confirmedExposure, 150);
      expect(revisions.single.lines, isEmpty);

      // The event is closed, exactly as a counted one is.
      final detail = await h
          .read(eventServiceProvider)
          .watchEvent(eventId)
          .first;
      expect(detail.event.status, EventStatus.closed);

      // Nothing was counted, so nothing moved.
      final movements = await h
          .read(inventoryLedgerProvider)
          .movements(event: EventId(eventId));
      expect(movements, isEmpty);

      // And the autosaved draft died with the confirm, like any other.
      expect(await h.read(closeoutServiceProvider).loadDraft(eventId), isNull);
    });
  });

  testWidgets('cancelling changes nothing: no closeout, event still active, '
      'still on the worksheet', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedEvent(h, tester);

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    await _fromScreenOverflow(tester, 'Close without counting');
    expect(find.text('Close this event without counting?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Back on the worksheet, untouched.
    expect(find.text('Close this event without counting?'), findsNothing);
    expect(find.text('Finish closeout'), findsOneWidget);
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() async {
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      expect(revisions, isEmpty);
      final detail = await h
          .read(eventServiceProvider)
          .watchEvent(eventId)
          .first;
      expect(detail.event.status, EventStatus.active);
    });
  });

  testWidgets('with the headcount missing the dialog asks for it in place '
      'rather than sending her back', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    // No planned estimate, so the field on the screen starts empty.
    final eventId = await _seedEvent(h, tester, exposure: null);

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'Confirmed attendance'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      isEmpty,
    );

    await _fromScreenOverflow(tester, 'Close without counting');

    final field = find.byKey(const Key('close-without-counting-exposure'));
    expect(field, findsOneWidget);
    // Nothing to record yet, so there is nothing to press.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Close without counting'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(field, '90');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Close without counting'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Closeout report'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() async {
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      expect(revisions.single.confirmedExposure, 90);
      expect(revisions.single.lines, isEmpty);
    });
  });

  testWidgets('a partial count finishes from the same overflow: what was '
      'counted is recorded, the rest is skipped', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedEvent(
      h,
      tester,
      itemNames: ['Al pastor', 'Barbacoa', 'Carnitas'],
    );

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // Count one of the three the ordinary way.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Loaded').first,
      '10',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?').first,
      '4',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 6'), findsOneWidget);
    expect(find.text('1 of 3 confirmed'), findsOneWidget);

    // The button waits for every line, so stopping here needs the overflow.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Finish closeout'),
          )
          .onPressed,
      isNull,
    );

    await _fromScreenOverflow(tester, 'Skip the rest and finish');
    // It lands on the ordinary confirmation sheet, over the ordinary
    // population: one line counted, the other two skipped out of it.
    expect(find.text('Confirm this closeout?'), findsOneWidget);
    expect(find.textContaining('1 of 1 items confirmed'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Closeout report'), findsOneWidget);
    expect(find.text('Al pastor'), findsOneWidget);
    expect(find.text('Barbacoa'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() async {
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      final lines = revisions.single.lines;
      expect(lines, hasLength(1));
      expect(lines.single.depletion.micros, 6000000);
    });
  });

  testWidgets('"Skip the rest and finish" asks for the headcount before it '
      'skips anything', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedEvent(
      h,
      tester,
      itemNames: ['Al pastor', 'Barbacoa'],
      exposure: null,
    );

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    await _fromScreenOverflow(tester, 'Skip the rest and finish');
    expect(find.text('Enter the confirmed attendance first.'), findsOneWidget);
    // Nothing was skipped on the way to that refusal.
    expect(find.text('Skipped'), findsNothing);
    expect(find.text('0 of 2 confirmed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('"Skip the rest and finish" is not offered once every line is '
      'resolved', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedEvent(h, tester);

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    await tester.tap(find.byKey(const Key('closeout-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('Skip the rest and finish'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('None used'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('closeout-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('Skip the rest and finish'), findsNothing);
    expect(find.text('Close without counting'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });

  testWidgets('the confirmation and the nothing-counted report render at '
      '200 % text scale on a 320 dp viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedEvent(h, tester);

    // An overflow at 200 % throws and fails the test.
    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    await _fromScreenOverflow(tester, 'Close without counting');
    expect(find.text('Close this event without counting?'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Close without counting'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // The report for a closeout with nothing in it, at the same size.
    await tester.runAsync(() => confirmCloseout(h, eventId, exposure: 150));
    await h.pumpScreen(tester, CloseoutReportScreen(eventId: eventId));
    expect(find.text('Nothing was counted for this event.'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('an event nobody has closed out still says there is no report '
      'yet — a different thing from one closed without counting', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedEvent(h, tester);

    await h.pumpScreen(tester, CloseoutReportScreen(eventId: eventId));

    expect(
      find.text(
        'Nothing has been counted for this event yet, so there is no report '
        'to show.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nothing was counted for this event.'), findsNothing);
    await h.flushTimers(tester);
  });
}
