/// Leftover-first entry on the closeout card (owner feedback: ask how much
/// is LEFT, not how much was used): the lead "How many are left?" field
/// writes the `returned` count, and THE one leftover rule — shared with
/// the scan-to-count sheet — fills a blank loaded from the planned load
/// and counts a blank waste as 0 once loaded is known, so a leftover count
/// alone can complete a line. Used stays the derived depletion: loaded −
/// left over − waste, and the captions say which rule is in force.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

void main() {
  testWidgets('a leftover count with only a planned load completes the '
      'line: loaded fills, waste counts as 0', (tester) async {
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
    expect(find.textContaining('Planned load was 12'), findsOneWidget);
    // The caption announces the rule before the count lands.
    expect(
      find.text('Waste counts as 0 unless you set it in the worksheet.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
    await tester.pumpAndSettle();

    // Loaded filled from the planned load, waste defaulted to 0: used
    // derives 12 − 2 − 0 and the line confirms.
    expect(find.text('Used: 10'), findsOneWidget);
    expect(
      find.text('Used excludes waste — derived from the worksheet.'),
      findsOneWidget,
    );
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

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

  testWidgets('a leftover count alone stays in progress; adding loaded '
      'later completes it the same way', (tester) async {
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

    // No loaded value and no planned load: the caption points at the
    // worksheet instead of promising a completion that cannot happen.
    expect(
      find.text('Add loaded in the worksheet to work out what was used.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '4',
    );
    await tester.pumpAndSettle();

    // Partial must never look like done (§4).
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

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

    // Loaded arriving after the leftover count lands identically: the
    // blank waste counts as 0 and the line confirms.
    await tester.ensureVisible(find.textContaining('Worksheet'));
    await tester.tap(find.textContaining('Worksheet'));
    await tester.pumpAndSettle();
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
