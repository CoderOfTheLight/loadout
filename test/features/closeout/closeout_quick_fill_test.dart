/// Quick-fill chips on the closeout line card — the fastest path, and with
/// Loaded now prefilled from the plan, usually a whole line in ONE tap.
/// 'Everything left' writes left = loaded (else the planned load) and the
/// one leftover rule derives a used of 0; with neither number on record
/// nothing-used needs no count — the chip writes a direct used of 0. 'None
/// left' writes left = 0 and flips the stockout flag ON, deriving used from
/// loaded or the planned load the same way; with neither on record it
/// invents nothing — it focuses Loaded, the one number that then determines
/// the line. Both ride the same debounced autosave path typing does, and a
/// chip that FINISHES a line folds the card down to its one-row summary.
/// Chips hide on skipped lines.
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

/// Scrolls [finder] clear of the docked confirm bar, then taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps a folded-down card open again (the name is on its summary row).
Future<void> _reopen(WidgetTester tester, String itemName) =>
    _tap(tester, find.text(itemName));

bool _ranOutSelected(WidgetTester tester) => tester
    .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ran out'))
    .selected;

void main() {
  testWidgets("'Everything left' with nothing on record needs no count: a "
      'direct used of 0 confirms, folds the card, and rides the autosave', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

    await _tap(tester, find.text('Everything left'));

    // Nothing used IS depletion 0 — a legal label (§5) with no leftover
    // count invented; the card flips confirmed and folds to one row.
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Left'), findsNothing);
    expect(find.text('Everything left'), findsNothing);

    // Reopening brings the whole card back, untouched.
    await _reopen(tester, 'Tortillas');
    expect(find.widgetWithText(TextFormField, 'Left'), findsOneWidget);
    // 'Everything left' never touches the stockout flag.
    expect(_ranOutSelected(tester), isFalse);

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

    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Everything left'));

    // left = loaded, thrown out counts as 0: used derives to 0 and confirms.
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

  testWidgets("'Everything left' on a prefilled line is the whole count in "
      'one tap', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester, plannedLoad: true);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await _tap(tester, find.text('Everything left'));

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

    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();

    await _tap(tester, find.text('None left'));

    expect(find.text('Used: 10'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    // All gone means demand was probably censored: 'Ran out' flips ON.
    await _reopen(tester, 'Tortillas');
    expect(_ranOutSelected(tester), isTrue);

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

  testWidgets("'None left' on a prefilled line derives from the plan", (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester, plannedLoad: true);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await _tap(tester, find.text('None left'));

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

  testWidgets("'None left' with neither number records the zero and focuses "
      'Loaded — which then completes the line', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await _tap(tester, find.text('None left'));

    // left = 0 is a real count, but alone it cannot say how many were
    // used: the line is NOT confirmed, so the card stays open.
    expect(find.text('0 of 1 confirmed'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
    expect(_ranOutSelected(tester), isTrue);
    final leftEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Left'),
        matching: find.byType(EditableText),
      ),
    );
    expect(leftEditable.controller.text, '0');
    // Focus landed on Loaded — the one number that now determines the line.
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

    // Typing the load completes the story: thrown out counts as 0, used =
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

  testWidgets('quick fills hide on skipped lines', (tester) async {
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

    // The per-event soap line starts skipped and folded: no chips there —
    // only the per-person tortillas card shows them.
    expect(find.text('Everything left'), findsOneWidget);
    expect(find.text('None left'), findsOneWidget);

    // The folded soap card carries no chips at all, so the only Skip on
    // screen is the tortillas card's. Skipping it hides its chips too.
    expect(find.text('Skip'), findsOneWidget);
    await _tap(tester, find.text('Skip'));
    expect(find.text('Everything left'), findsNothing);
    expect(find.text('None left'), findsNothing);

    // Reopening the soap card and unticking Skip brings its chips out.
    await _reopen(tester, 'Dish soap');
    await _tap(tester, find.widgetWithText(FilterChip, 'Skip'));
    expect(find.text('Everything left'), findsOneWidget);
    expect(find.text('None left'), findsOneWidget);

    // Let the debounced autosave fire before the test ends.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });
}
