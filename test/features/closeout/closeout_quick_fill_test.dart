/// Quick-fill chips on the closeout line card ("a faster way to check what
/// was used"): 'Nothing used' confirms a depletion of 0 through the same
/// debounced autosave path typing rides; 'All gone' takes the loaded value,
/// else the planned-load prefill, and flips the stockout flag ON — and with
/// neither number on record it invents nothing: it only flags the stockout
/// and focuses the depletion field. Chips hide on skipped lines.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/presentation/closeout_line_card.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

void main() {
  testWidgets("'Nothing used' confirms with depletion 0 and rides the "
      'debounced autosave', (tester) async {
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
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

    await tester.ensureVisible(find.text('Nothing used'));
    await tester.tap(find.text('Nothing used'));
    await tester.pumpAndSettle();

    // A confirmed zero is a legal label (§5) — the card flips confirmed.
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    // 'Nothing used' never touches the stockout flag.
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ran out'))
          .selected,
      isFalse,
    );

    // The chip flows through the same handler typing does: the debounced
    // draft carries the zero.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft!.lines.single.depletion!.micros, 0);
    expect(draft.lines.single.stockout, isFalse);
    await h.flushTimers(tester);
  });

  testWidgets("'All gone' with a loaded value uses it and flags the "
      'stockout', (tester) async {
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

    await tester.ensureVisible(find.textContaining('Worksheet'));
    await tester.tap(find.textContaining('Worksheet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('All gone'));
    await tester.tap(find.text('All gone'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    // All gone means demand was probably censored: 'Ran out' flips ON.
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ran out'))
          .selected,
      isTrue,
    );

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    final line = draft!.lines.single;
    expect(line.depletion!.micros, 10000000);
    expect(line.loaded!.micros, 10000000);
    expect(line.stockout, isTrue);
    await h.flushTimers(tester);
  });

  testWidgets("'All gone' with only a planned load uses the prefill", (
    tester,
  ) async {
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

    await tester.ensureVisible(find.text('All gone'));
    await tester.tap(find.text('All gone'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft!.lines.single.depletion!.micros, 12000000);
    expect(draft.lines.single.stockout, isTrue);
    await h.flushTimers(tester);
  });

  testWidgets("'All gone' with neither number invents nothing: stockout on, "
      'depletion focused and empty', (tester) async {
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

    await tester.ensureVisible(find.text('All gone'));
    await tester.tap(find.text('All gone'));
    await tester.pumpAndSettle();

    // No number was invented: the line is NOT confirmed.
    expect(find.text('0 of 1 confirmed'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ran out'))
          .selected,
      isTrue,
    );
    // The depletion field (the card's only text field) took the focus.
    final depletionEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(CloseoutLineCard),
        matching: find.byType(EditableText),
      ),
    );
    expect(depletionEditable.focusNode.hasFocus, isTrue);
    expect(depletionEditable.controller.text, isEmpty);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft!.lines.single.depletion, isNull);
    expect(draft.lines.single.stockout, isTrue);
    await h.flushTimers(tester);
  });

  testWidgets('quick fills hide on skipped lines — both skip flavors', (
    tester,
  ) async {
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

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // The per-event soap line starts "didn't count it": no chips there —
    // only the per-person tortillas card shows them.
    expect(find.text('Nothing used'), findsOneWidget);
    expect(find.text('All gone'), findsOneWidget);

    // Skipping the per-person line hides its chips too.
    await tester.ensureVisible(find.text('Skip item'));
    await tester.tap(find.text('Skip item'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing used'), findsNothing);
    expect(find.text('All gone'), findsNothing);

    // Unticking "didn't count it" brings the soap card's chips out.
    await tester.ensureVisible(
      find.widgetWithText(FilterChip, "Didn't count it"),
    );
    await tester.tap(find.widgetWithText(FilterChip, "Didn't count it"));
    await tester.pumpAndSettle();
    expect(find.text('Nothing used'), findsOneWidget);
    expect(find.text('All gone'), findsOneWidget);

    // Let the debounced autosave fire before the test ends.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });
}
