/// The two shortcuts on the closeout line card — the fastest path, and with
/// Loaded prefilled from the plan, usually a whole line in ONE tap. They are
/// the plainest words for the two answers a volunteer actually gives:
/// 'None used' writes left = loaded (else the planned load) and the one
/// leftover rule derives a used of 0; with neither number on record
/// nothing-used needs no count — it writes a direct used of 0. 'All gone'
/// writes left = 0 and answers "did you run out?" with Yes, deriving used
/// from loaded or the planned load the same way; with neither on record it
/// invents nothing — it focuses Loaded, the one number that then determines
/// the line. Both ride the same debounced autosave path typing does, and a
/// shortcut that FINISHES a line folds the card down to its one-row summary.
/// Shortcuts hide on skipped lines.
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

/// Whether the card's "did you run out?" question is answered Yes. The
/// question is only on screen when the line reads empty.
bool _ranOut(WidgetTester tester) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Yes')).selected;

/// Opens a card's overflow and picks [item] from it.
Future<void> _fromMore(WidgetTester tester, String item) async {
  await _tap(tester, find.text('More'));
  await _tap(tester, find.text(item));
}

void main() {
  testWidgets("'None used' with nothing on record needs no count: a "
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

    await _tap(tester, find.text('None used'));

    // Nothing used IS depletion 0 — a legal label (§5) with no leftover
    // count invented; the card flips confirmed and folds to one row.
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'How many are left?'),
      findsNothing,
    );
    expect(find.text('None used'), findsNothing);

    // Reopening brings the whole card back, untouched.
    await _reopen(tester, 'Tortillas');
    expect(
      find.widgetWithText(TextFormField, 'How many are left?'),
      findsOneWidget,
    );
    // 'None used' never raises the stockout question — nothing ran out.
    expect(find.text('Did you run out?'), findsNothing);

    // The shortcut flows through the same handler typing does: the debounced
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

  testWidgets("'None used' with a loaded value counts them all back", (
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

    await _tap(tester, find.text('None used'));

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

  testWidgets("'None used' on a prefilled line is the whole count in "
      'one tap', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester, plannedLoad: true);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await _tap(tester, find.text('None used'));

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

  testWidgets("'All gone' with a loaded value derives used = loaded and "
      'answers the stockout question', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();

    await _tap(tester, find.text('All gone'));

    expect(find.text('Used: 10'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    // All gone means demand was probably censored: the question is answered
    // Yes on the way past, and it is right there to be taken back.
    await _reopen(tester, 'Tortillas');
    expect(find.text('Did you run out?'), findsOneWidget);
    expect(_ranOut(tester), isTrue);

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

  testWidgets("'All gone' on a prefilled line derives from the plan", (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester, plannedLoad: true);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await _tap(tester, find.text('All gone'));

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

  testWidgets("'All gone' with neither number records the zero and focuses "
      'Loaded — which then completes the line', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final eventId = await _seedLine(h, tester);

    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    await _tap(tester, find.text('All gone'));

    // left = 0 is a real count, but alone it cannot say how many were
    // used: the line is NOT confirmed, so the card stays open.
    expect(find.text('0 of 1 confirmed'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
    expect(_ranOut(tester), isTrue);
    final leftEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'How many are left?'),
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

  testWidgets('shortcuts hide on skipped lines', (tester) async {
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

    // The per-event soap line starts skipped and folded: no shortcuts there
    // — only the per-person tortillas card shows them.
    expect(find.text('All gone'), findsOneWidget);
    expect(find.text('None used'), findsOneWidget);

    // The folded soap card carries no controls at all, so the only More on
    // screen is the tortillas card's. Skipping it hides its shortcuts too.
    await _fromMore(tester, 'Skip this item');
    expect(find.text('All gone'), findsNothing);
    expect(find.text('None used'), findsNothing);

    // Reopening the soap card and counting it after all brings its
    // shortcuts out.
    await _reopen(tester, 'Dish soap');
    await _fromMore(tester, 'Count this item after all');
    expect(find.text('All gone'), findsOneWidget);
    expect(find.text('None used'), findsOneWidget);

    // Let the debounced autosave fire before the test ends.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await h.flushTimers(tester);
  });
}
