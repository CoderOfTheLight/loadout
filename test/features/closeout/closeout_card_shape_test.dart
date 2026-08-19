/// The shape of the rebuilt closeout card, pinned.
///
/// The audit measured this screen as the app's worst: ~120 controls over
/// 6–10 screens to do a job that is "for each thing, type how many are
/// left". What is pinned here is the answer to that:
///
///  * exactly TWO number boxes on a card, both always visible — no
///    disclosure, no third Used field, no algebra used as a button label;
///  * thrown-out kept but off the face: hidden until asked for, defaulting
///    to 0, and still written to the draft when nobody ever looked at it;
///  * a done card folded down to one row, tappable to reopen — the
///    scrolling win — including a line that was already done when the
///    screen opened;
///  * 200 % system text on a 320 dp phone, which is what this audience
///    actually runs;
///  * a sixty-item worksheet that builds the handful of cards on screen
///    rather than all sixty.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/presentation/closeout_line_card.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

/// One planned Tortillas line on an active event, with a planned load of 12
/// on the latest snapshot when [plannedLoad] is set.
Future<String> _seedLine(
  AppHarness h,
  WidgetTester tester, {
  bool plannedLoad = true,
}) async {
  late String eventId;
  await tester.runAsync(() async {
    final item = await seedItem(h);
    eventId = await seedEvent(
      h,
      name: 'Market',
      date: '2026-08-10',
      exposure: 150,
      itemIds: [item],
    );
    await activateEvent(h, eventId);
    if (plannedLoad) {
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
    }
  });
  return eventId;
}

/// Walks the worksheet from the top in 100 dp steps until [finder] is
/// built, laying out everything it passes on the way.
///
/// Driven off the [ScrollPosition] rather than by dragging: at 200 % text on
/// a 320 dp phone the scrolling area is 159 dp tall, and a synthetic drag
/// that long starts inside a text field and stalls.
Future<void> _revealByJump(WidgetTester tester, Finder finder) async {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  for (var offset = 0.0; ; offset += 100) {
    position.jumpTo(
      offset > position.maxScrollExtent ? position.maxScrollExtent : offset,
    );
    await tester.pumpAndSettle();
    if (finder.evaluate().isNotEmpty) return;
    if (offset >= position.maxScrollExtent) {
      fail('scrolled the whole worksheet without finding $finder');
    }
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a card carries exactly two number boxes and eight controls, '
      'none of them behind a disclosure', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    final card = find.byType(CloseoutLineCard);
    Finder inCard(Finder matching) =>
        find.descendant(of: card, matching: matching);

    // TWO boxes. Not three, not four, and nothing folded away.
    expect(inCard(find.byType(TextFormField)), findsNWidgets(2));
    expect(find.widgetWithText(TextFormField, 'Loaded'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Left'), findsOneWidget);

    // The gone ones, by name.
    expect(find.textContaining('Worksheet'), findsNothing);
    expect(find.textContaining('loaded − left'), findsNothing);
    expect(find.text('Estimate'), findsNothing);
    expect(find.textContaining('Used excludes waste'), findsNothing);
    expect(find.text('Skip item'), findsNothing);
    expect(find.text("Didn't count it"), findsNothing);

    // The controls that remain, all of them words.
    for (final label in [
      'Everything left',
      'None left',
      'Ran out',
      'Skip',
      'Some was thrown out',
      'More',
    ]) {
      expect(inCard(find.text(label)), findsOneWidget, reason: label);
    }
    await h.flushTimers(tester);
  });

  testWidgets('thrown out stays hidden, defaults to 0, and is still written '
      'when nobody looks at it', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    expect(find.widgetWithText(TextFormField, 'Thrown out'), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'Left'), '2');
    await tester.pumpAndSettle();
    // Still hidden after a count that quietly treated it as 0.
    expect(find.widgetWithText(TextFormField, 'Thrown out'), findsNothing);
    expect(find.text('Used: 10'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    // CloseoutFormDraft keeps writing waste exactly as it always did.
    expect(draft!.lines.single.waste!.micros, 0);

    // Asking for it shows the default rather than an empty box.
    await _tap(tester, find.text('Some was thrown out'));
    final box = find.widgetWithText(TextFormField, 'Thrown out');
    expect(box, findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: box, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      '0',
    );
    // And the control does not sit there twice.
    expect(find.text('Some was thrown out'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('a confirmed card folds to one row and taps back open; a line '
      'already confirmed on arrival opens folded', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await _tap(tester, find.text('None left'));

    // One row: the name, what it says was used, and the state word. No
    // boxes, no chips — this is the scrolling win.
    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Used: 12'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget); // exposure only
    expect(find.text('Ran out'), findsNothing);

    // Tapping it puts everything back.
    await _tap(tester, find.text('Tortillas'));
    expect(find.widgetWithText(TextFormField, 'Loaded'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Left'), findsOneWidget);
    expect(find.text('Ran out'), findsOneWidget);

    // Let the draft land, then come back to it: a line that is already done
    // when the screen opens is folded from the first frame.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    expect(find.text('Used: 12'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget); // exposure only
    await h.flushTimers(tester);
  });

  testWidgets('the worksheet renders at 200 % text scale on a 320 dp '
      'viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final cleaning = await folderIdByName(h, 'Cleaning & setup');
      final soap = await seedItem(h, name: 'Dish soap', folderId: cleaning);
      final tortillas = await seedItem(h, name: 'Tortillas');
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-11',
        exposure: 100,
        itemIds: [tortillas, soap],
      );
      await activateEvent(h, eventId);
    });

    // An overflow at 200 % throws and fails the test — and scrolling the
    // whole worksheet through the viewport is what lays every part of it
    // out at this size.
    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    expect(find.text('0 of 1 confirmed'), findsOneWidget);
    await _revealByJump(tester, find.text('Note (optional)'));
    // The two boxes stack rather than squeezing two labels into 288 dp.
    await _revealByJump(tester, find.widgetWithText(TextFormField, 'Loaded'));
    expect(find.widgetWithText(TextFormField, 'Loaded'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Left'), findsOneWidget);

    // And the counting still works at this size.
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '9');
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Left'), '4');
    await tester.pumpAndSettle();
    expect(find.text('Used: 5'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });

  testWidgets('a sixty-item worksheet builds only the cards on screen', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final itemIds = <String>[];
      for (var i = 0; i < 60; i++) {
        itemIds.add(
          await seedItem(h, name: 'Item ${i.toString().padLeft(2, '0')}'),
        );
      }
      eventId = await seedEvent(
        h,
        name: 'Big market',
        date: '2026-08-12',
        exposure: 400,
        itemIds: itemIds,
      );
      await activateEvent(h, eventId);
    });

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    // All sixty lines are on the worksheet …
    expect(find.text('0 of 60 confirmed'), findsOneWidget);
    expect(find.text('60 items not confirmed yet'), findsOneWidget);
    // … but the tree holds only what the viewport (plus its cache extent)
    // needs. The old SingleChildScrollView > Column built every one.
    final built = find.byType(CloseoutLineCard).evaluate().length;
    expect(built, greaterThan(0));
    expect(
      built,
      lessThan(15),
      reason: 'a 600 dp viewport cannot need 15 cards; got $built of 60',
    );

    // Scrolling brings later ones in without ever holding all sixty.
    await _revealByJump(tester, find.text('Item 20'));
    expect(find.byType(CloseoutLineCard).evaluate().length, lessThan(15));
    await h.flushTimers(tester);
  });
}
