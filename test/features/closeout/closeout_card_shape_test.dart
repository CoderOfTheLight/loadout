/// The shape of the rebuilt closeout card, pinned.
///
/// The audit measured this screen as the app's worst: ~120 controls over
/// 6–10 screens to do a job that is "for each thing, type how many are
/// left". Yesterday's rebuild got a card down to two boxes and eight
/// controls; the owner's verdict was that it is STILL too complicated. What
/// is pinned here is the answer to that:
///
///  * a default card carries exactly ONE number box and three words —
///    `All gone`, `None used`, `More`. Four controls, not eight;
///  * `Loaded` is a quiet line of text, prefilled from the plan, editable
///    through More — and comes back as a box only on a line the plan says
///    nothing about, where a leftover count would have nothing to subtract
///    from;
///  * More holds the four things that are not the one number;
///  * `Ran out` is a QUESTION that appears only once the line reads empty,
///    and never blocks the line from confirming;
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

/// The text currently in the box labelled [label].
String _boxText(WidgetTester tester, String label) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, label),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

void main() {
  testWidgets('a default card is one number box and three words: the two '
      'shortcuts and More — four controls where there were eight', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    final card = find.byType(CloseoutLineCard);
    Finder inCard(Finder matching) =>
        find.descendant(of: card, matching: matching);

    // ONE box. That is the job.
    expect(inCard(find.byType(TextFormField)), findsOneWidget);
    expect(
      inCard(find.widgetWithText(TextFormField, 'How many are left?')),
      findsOneWidget,
    );

    // Loaded is a quiet line of text, not a box.
    expect(find.widgetWithText(TextFormField, 'Loaded'), findsNothing);
    expect(inCard(find.text('Loaded 12')), findsOneWidget);

    // The three words: two shortcuts and the overflow.
    for (final label in ['All gone', 'None used', 'More']) {
      expect(inCard(find.text(label)), findsOneWidget, reason: label);
    }

    // Everything the card used to carry on its face, by name.
    for (final gone in [
      'Everything left',
      'None left',
      'Ran out',
      'Did you run out?',
      'Skip',
      'Some was thrown out',
      'Estimate',
      'Skip item',
      "Didn't count it",
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.textContaining('Worksheet'), findsNothing);
    expect(find.textContaining('loaded − left'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('More holds the four things that are not the one number', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await _tap(tester, find.text('More'));
    for (final item in [
      'Change what was loaded',
      'Some was thrown out',
      'Enter what was used instead',
      'Skip this item',
    ]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    // Exactly those four — nothing else hides in there.
    expect(
      find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      findsNWidgets(4),
    );
    await tester.tapAt(const Offset(4, 4)); // dismiss the menu
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('Loaded reads as text and is edited through More, which puts '
      'the box back', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    // The plan's 12 is on the card as a sentence, and the count derives
    // from it without anybody touching a Loaded box.
    expect(find.text('Loaded 12'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 10'), findsOneWidget);

    // The crate held 20, not 12: More → Change what was loaded.
    await _tap(tester, find.text('More'));
    await _tap(tester, find.text('Change what was loaded'));
    final loadedBox = find.widgetWithText(TextFormField, 'Loaded');
    expect(loadedBox, findsOneWidget);
    // The box opens on the number the sentence was reading.
    expect(_boxText(tester, 'Loaded'), '12');
    expect(find.text('Loaded 12'), findsNothing); // not said twice

    await tester.enterText(loadedBox, '20');
    await tester.pumpAndSettle();
    expect(find.text('Used: 18'), findsOneWidget);

    // Once it is open the overflow stops offering to open it.
    await _tap(tester, find.text('More'));
    expect(find.text('Change what was loaded'), findsNothing);
    expect(find.text('Skip this item'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft!.lines.single.loaded!.micros, 20000000);
    expect(draft.lines.single.depletion!.micros, 18000000);
    await h.flushTimers(tester);
  });

  testWidgets('a line the plan says nothing about keeps the Loaded box on '
      'the card, because a leftover count needs it', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester, plannedLoad: false);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    final card = find.byType(CloseoutLineCard);
    Finder inCard(Finder matching) =>
        find.descendant(of: card, matching: matching);

    // Two boxes here and nowhere else — and no "Loaded" sentence, because
    // there is no plan figure to read out.
    expect(inCard(find.byType(TextFormField)), findsNWidgets(2));
    expect(
      inCard(find.widgetWithText(TextFormField, 'Loaded')),
      findsOneWidget,
    );
    expect(
      inCard(find.widgetWithText(TextFormField, 'How many are left?')),
      findsOneWidget,
    );
    expect(find.textContaining('Loaded 1'), findsNothing);

    // The shortcuts still mean what they say, and the overflow drops the
    // item that would only duplicate the box already on the card.
    expect(inCard(find.text('All gone')), findsOneWidget);
    expect(inCard(find.text('None used')), findsOneWidget);
    await _tap(tester, find.text('More'));
    expect(find.text('Change what was loaded'), findsNothing);
    expect(find.text('Some was thrown out'), findsOneWidget);
    expect(find.text('Enter what was used instead'), findsOneWidget);
    expect(find.text('Skip this item'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    // And it counts: 9 loaded, 4 left, 5 used.
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '9');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '4',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 5'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });

  testWidgets('"Did you run out?" appears only once the line reads empty, '
      'and never blocks the line from confirming', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    // Absent on an untouched card, and on a card with something left.
    expect(find.text('Did you run out?'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 10'), findsOneWidget);
    expect(find.text('Did you run out?'), findsNothing);

    // A hand-typed 0 makes the line read empty: the question arrives.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '0',
    );
    await tester.pumpAndSettle();
    expect(find.text('Did you run out?'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Yes'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'No'), findsOneWidget);
    // Neither answer yet …
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Yes'))
          .selected,
      isFalse,
    );
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'No')).selected,
      isFalse,
    );
    // … and yet the line confirms: the question asks, it never gates.
    expect(find.text('Used: 12'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);

    // Answering it puts the flag on the draft and lets the card fold away.
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Yes'));
    expect(find.text('Did you run out?'), findsNothing); // folded
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft!.lines.single.stockout, isTrue);
    expect(draft.lines.single.depletion!.micros, 12000000);

    // Re-opening shows the answer rather than hiding it again.
    await _tap(tester, find.text('Tortillas'));
    expect(find.text('Did you run out?'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Yes'))
          .selected,
      isTrue,
    );
    // And it can be taken back: enough went round, nothing was censored.
    await _tap(tester, find.widgetWithText(ChoiceChip, 'No'));
    await _tap(tester, find.text('Tortillas'));
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'No')).selected,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final after = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(after!.lines.single.stockout, isFalse);
    await h.flushTimers(tester);
  });

  testWidgets('thrown out stays off the card, defaults to 0, and is still '
      'written when nobody looks at it', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    expect(find.widgetWithText(TextFormField, 'Thrown out'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
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
    await _tap(tester, find.text('More'));
    await _tap(tester, find.text('Some was thrown out'));
    final box = find.widgetWithText(TextFormField, 'Thrown out');
    expect(box, findsOneWidget);
    expect(_boxText(tester, 'Thrown out'), '0');
    // And the overflow does not offer it twice.
    await _tap(tester, find.text('More'));
    expect(find.text('Some was thrown out'), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
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

    await _tap(tester, find.text('All gone'));

    // One row: the name, what it says was used, and the state word. No
    // box, no chips — this is the scrolling win.
    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('Used: 12'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget); // exposure only
    expect(find.text('Did you run out?'), findsNothing);

    // Tapping it puts everything back — including the answer 'All gone'
    // gave on the way past.
    await _tap(tester, find.text('Tortillas'));
    expect(
      find.widgetWithText(TextFormField, 'How many are left?'),
      findsOneWidget,
    );
    expect(find.text('Did you run out?'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Yes'))
          .selected,
      isTrue,
    );

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
    await _revealByJump(tester, find.widgetWithText(TextFormField, 'Loaded'));
    expect(find.widgetWithText(TextFormField, 'Loaded'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'How many are left?'),
      findsOneWidget,
    );

    // And the counting still works at this size.
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '9');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '4',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 5'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    // The question lays out at this size too — it is a Wrap, so the two
    // answers take another line rather than overflowing.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '0',
    );
    await tester.pumpAndSettle();
    await _revealByJump(tester, find.text('Did you run out?'));
    expect(find.widgetWithText(ChoiceChip, 'Yes'), findsOneWidget);

    // The overflow opens and lays out at this size as well. This line has
    // no plan figure, so its Loaded box is already on the card and the menu
    // carries the other three.
    await _revealByJump(tester, find.text('More'));
    await _tap(tester, find.text('More'));
    expect(find.text('Some was thrown out'), findsOneWidget);
    expect(find.text('Enter what was used instead'), findsOneWidget);
    expect(find.text('Skip this item'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

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
