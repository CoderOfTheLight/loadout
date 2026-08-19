/// Leftover-first entry on the closeout card (owner feedback: ask how much
/// is LEFT, not how much was used), now with the plan's load already IN the
/// Loaded box rather than printed beside it as dead text. So the whole job
/// per line is typing one number — Left — and THE one leftover rule (shared
/// with the scan-to-count sheet) counts a blank thrown-out as 0 so that one
/// number completes the line. Used stays the derived depletion: loaded −
/// left − thrown out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

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
  testWidgets('the planned load is prefilled INTO Loaded, stays editable, '
      'and one number finishes the line', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
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
      // A snapshot with an owner override gives the line its planned load.
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

    // The 12 is IN the box, not in a caption beside it — and the card says
    // out loud that it is only a starting value.
    expect(_boxText(tester, 'Loaded'), '12');
    expect(find.textContaining('Planned load was'), findsNothing);
    expect(
      find.text(
        'Loaded comes from your plan — change any that were different.',
      ),
      findsOneWidget,
    );
    // A prefill is not progress: an untouched line still looks untouched.
    expect(find.text('In progress'), findsNothing);
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Left'), '2');
    await tester.pumpAndSettle();

    // Thrown out defaulted to 0: used derives 12 − 2 − 0 and the line
    // confirms off ONE typed number.
    expect(find.text('Used: 10'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    // Still editable: overtyping the plan's number re-derives.
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '20');
    await tester.pumpAndSettle();
    expect(find.text('Used: 18'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '12');
    await tester.pumpAndSettle();

    // The count rode the same debounced autosave typing does.
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
    await h.flushTimers(tester);
  });

  testWidgets('with no forecast Loaded starts empty; a Left count alone '
      'stays in progress until Loaded is filled in', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
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
    });

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    // Nothing to prefill from, so nothing is invented.
    expect(_boxText(tester, 'Loaded'), isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Left'), '4');
    await tester.pumpAndSettle();

    // Partial must never look like done (§4), and the card says which of
    // the two numbers is missing.
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('0 of 1 confirmed'), findsOneWidget);
    expect(
      find.text('Fill in Loaded to work out what was used.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    var draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    var line = draft!.lines.single;
    expect(line.returned!.micros, 4000000);
    expect(line.loaded, isNull);
    expect(line.waste, isNull);
    expect(line.depletion, isNull);

    // Loaded arriving after the Left count lands identically: the blank
    // thrown-out counts as 0 and the line confirms.
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();
    expect(find.text('Used: 6'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    line = draft!.lines.single;
    expect(line.loaded!.micros, 10000000);
    expect(line.waste!.micros, 0);
    expect(line.depletion!.micros, 6000000);
    await h.flushTimers(tester);
  });
}
