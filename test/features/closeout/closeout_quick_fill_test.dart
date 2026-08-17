/// Quick-fill chips on the closeout line card, in leftover language:
/// 'Everything left' writes left = loaded (else the planned load) and the
/// one leftover rule derives a used of 0; with neither number on record
/// nothing-used needs no count — the chip writes a direct used of 0.
/// 'None left' writes left = 0 and flips the stockout flag ON, deriving
/// used from loaded or the planned load the same way; with neither on
/// record it invents nothing — it opens the worksheet and focuses Loaded,
/// the one number that then determines the line. Both ride the same
/// debounced autosave path typing does. Chips hide on skipped lines.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

/// One planned line on an active event, optionally with a planned load of
/// 12 via a snapshot override.
Future<String> _seedLine(
  AppHarness h,
  WidgetTester tester, {
  bool plannedLoad = false,
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

void main() {
  testWidgets("'Everything left' with nothing on record needs no count: a "
      'direct used of 0 confirms and rides the autosave', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

    await tester.ensureVisible(find.text('Everything left'));
    await tester.tap(find.text('Everything left'));
    await tester.pumpAndSettle();

    // Nothing used IS depletion 0 — a legal label (§5) with no leftover
    // count invented; the card flips confirmed.
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    // 'Everything left' never touches the stockout flag.
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ran out'))
          .selected,
      isFalse,
    );

    // The chip flows through the same handler typing does: the debounced
    // draft carries the zero — directly, since there was nothing to count
    // against.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    final line = draft!.lines.single;
    expect(line.depletion!.micros, 0);
    expect(line.returned, isNull);
    expect(line.loaded, isNull);
    expect(line.stockout, isFalse);
    await h.flushTimers(tester);
  });

  testWidgets("'Everything left' with a loaded value counts them all back", (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.ensureVisible(find.textContaining('Worksheet'));
    await tester.tap(find.textContaining('Worksheet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Everything left'));
    await tester.tap(find.text('Everything left'));
    await tester.pumpAndSettle();

    // left = loaded, waste counts as 0: used derives to 0 and confirms.
    expect(find.text('Used: 0'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    final line = draft!.lines.single;
    expect(line.loaded!.micros, 10000000);
    expect(line.returned!.micros, 10000000);
    expect(line.waste!.micros, 0);
    expect(line.depletion!.micros, 0);
    expect(line.stockout, isFalse);
    await h.flushTimers(tester);
  });

  testWidgets("'Everything left' with only a planned load fills the "
      'worksheet from the prefill', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester, plannedLoad: true);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    expect(find.textContaining('Planned load was 12'), findsOneWidget);

    await tester.ensureVisible(find.text('Everything left'));
    await tester.tap(find.text('Everything left'));
    await tester.pumpAndSettle();

    expect(find.text('Used: 0'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    final line = draft!.lines.single;
    expect(line.loaded!.micros, 12000000);
    expect(line.returned!.micros, 12000000);
    expect(line.waste!.micros, 0);
    expect(line.depletion!.micros, 0);
    expect(line.stockout, isFalse);
    await h.flushTimers(tester);
  });

  testWidgets("'None left' with a loaded value derives used = loaded and "
      'flags the stockout', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.ensureVisible(find.textContaining('Worksheet'));
    await tester.tap(find.textContaining('Worksheet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('None left'));
    await tester.tap(find.text('None left'));
    await tester.pumpAndSettle();

    expect(find.text('Used: 10'), findsOneWidget);
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
    expect(line.loaded!.micros, 10000000);
    expect(line.returned!.micros, 0);
    expect(line.waste!.micros, 0);
    expect(line.depletion!.micros, 10000000);
    expect(line.stockout, isTrue);
    await h.flushTimers(tester);
  });

  testWidgets("'None left' with only a planned load derives from the "
      'prefill', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester, plannedLoad: true);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    expect(find.textContaining('Planned load was 12'), findsOneWidget);

    await tester.ensureVisible(find.text('None left'));
    await tester.tap(find.text('None left'));
    await tester.pumpAndSettle();

    expect(find.text('Used: 12'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    final line = draft!.lines.single;
    expect(line.loaded!.micros, 12000000);
    expect(line.returned!.micros, 0);
    expect(line.waste!.micros, 0);
    expect(line.depletion!.micros, 12000000);
    expect(line.stockout, isTrue);
    await h.flushTimers(tester);
  });

  testWidgets("'None left' with neither number records the zero, opens the "
      'worksheet, and focuses Loaded — which then completes the line', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.ensureVisible(find.text('None left'));
    await tester.tap(find.text('None left'));
    await tester.pumpAndSettle();

    // left = 0 is a real count, but alone it cannot say how many were
    // used: the line is NOT confirmed.
    expect(find.text('0 of 1 confirmed'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ran out'))
          .selected,
      isTrue,
    );
    final leftoverEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'How many are left?'),
        matching: find.byType(EditableText),
      ),
    );
    expect(leftoverEditable.controller.text, '0');
    // The worksheet opened on Loaded — the one number that now determines
    // the line — and handed it focus.
    final loadedEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Loaded'),
        matching: find.byType(EditableText),
      ),
    );
    expect(loadedEditable.focusNode.hasFocus, isTrue);
    expect(loadedEditable.controller.text, isEmpty);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    var draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft!.lines.single.returned!.micros, 0);
    expect(draft.lines.single.depletion, isNull);
    expect(draft.lines.single.stockout, isTrue);

    // Typing the load completes the story: waste counts as 0, used =
    // loaded, still flagged as a stockout.
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '8');
    await tester.pumpAndSettle();
    expect(find.text('Used: 8'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    draft = await tester.runAsync(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft!.lines.single.depletion!.micros, 8000000);
    expect(draft.lines.single.waste!.micros, 0);
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
    expect(find.text('Everything left'), findsOneWidget);
    expect(find.text('None left'), findsOneWidget);

    // Skipping the per-person line hides its chips too.
    await tester.ensureVisible(find.text('Skip item'));
    await tester.tap(find.text('Skip item'));
    await tester.pumpAndSettle();
    expect(find.text('Everything left'), findsNothing);
    expect(find.text('None left'), findsNothing);

    // Unticking "didn't count it" brings the soap card's chips out.
    await tester.ensureVisible(
      find.widgetWithText(FilterChip, "Didn't count it"),
    );
    await tester.tap(find.widgetWithText(FilterChip, "Didn't count it"));
    await tester.pumpAndSettle();
    expect(find.text('Everything left'), findsOneWidget);
    expect(find.text('None left'), findsOneWidget);

    // Let the debounced autosave fire before the test ends.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });
}
