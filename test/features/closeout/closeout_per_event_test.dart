/// Closeout for per-event lines (proposal §3 + owner's Question 3 answer):
/// the worksheet inherits the folder sections, and "about the same every
/// event" lines start SKIPPED — because a made-up number would become
/// permanent history. A skipped line records nothing and teaches nothing,
/// the closeout confirms without it, and the forecast afterwards rests only
/// on real counts. Skip is one word and one control on every card now, so
/// there is nothing per-basis left to learn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

/// Scrolls [finder] clear of the docked confirm bar, then taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a supply line starts skipped, the closeout confirms without '
      'it, and the forecast uses only real counts', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String soap;
    late String tortillas;
    late String eventId;
    await tester.runAsync(() async {
      final cleaning = await folderIdByName(h, 'Cleaning & setup');
      soap = await seedItem(h, name: 'Dish soap', folderId: cleaning);
      tortillas = await seedItem(h, name: 'Tortillas');
      // One REAL soap count on record: 2 used at a 200-person event.
      final earlier = await seedEvent(
        h,
        name: 'Small event',
        date: '2026-07-01',
        exposure: 200,
        itemIds: [soap],
      );
      await activateEvent(h, earlier);
      await confirmCloseout(
        h,
        earlier,
        exposure: 200,
        lines: [
          CloseoutFormLine(
            itemId: soap,
            depletion: Quantity.fromMicros(2000000),
          ),
        ],
      );
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 150,
        itemIds: [tortillas, soap],
      );
      await activateEvent(h, eventId);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // The worksheet inherits the sections. The skipped supply section is
    // already handled, so its header fraction has morphed into the filled
    // "Done" chip (spec §4); the uncounted Unfiled section shows its
    // fraction.
    expect(find.text('Cleaning & setup'), findsOneWidget);
    expect(find.text('Unfiled'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget); // Cleaning & setup
    expect(find.text('0 of 1'), findsOneWidget); // Unfiled

    // The per-event line starts skipped — the recommended default — and
    // folds straight down to its one-row summary, so it costs one line of
    // screen rather than a card full of controls nobody will use.
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Some was thrown out'), findsOneWidget); // tortillas only
    // The header and the confirm bar count the SAME population: the one
    // line that still needs counting. They used to disagree out loud.
    expect(find.text('0 of 1 confirmed'), findsOneWidget);
    expect(find.text('1 item not confirmed yet'), findsOneWidget);
    // One word, one control, both bases.
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Skip item'), findsNothing);
    expect(find.text("Didn't count it"), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Left'), findsOneWidget);

    // Count the tortillas the ordinary way; the soap stays uncounted.
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Left'), '7');
    await tester.pumpAndSettle();
    expect(find.text('Used: 3'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    // Confirms without the supply line.
    await _tap(tester, find.text('Finish closeout'));
    await _tap(tester, find.text('Confirm'));
    // The worksheet is replaced by its report (the skipped supply line is
    // simply not in it — a skip records nothing).
    expect(find.text('Closeout report'), findsOneWidget);
    expect(find.text('Dish soap'), findsNothing);

    // Tear the tree down before the service-level verification: a live
    // fake-zone drift stream can wedge the executor against real-zone
    // database work inside runAsync — the same pattern the draft test uses
    // for process death.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() async {
      // The skipped line recorded nothing.
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      final lines = revisions.single.lines;
      expect(lines, hasLength(1));
      expect(lines.single.itemId as String, tortillas);
    });
    await h.flushTimers(tester);
  });

  testWidgets('the forecast after a skipped supply line rests only on real '
      'counts', (tester) async {
    // No widgets on purpose: this verifies the data pipeline the UI test
    // above feeds — a skip records nothing, so the next forecast's median
    // comes from the counted events alone, with no phantom zero.
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final cleaning = await folderIdByName(h, 'Cleaning & setup');
      final soap = await seedItem(h, name: 'Dish soap', folderId: cleaning);
      final tortillas = await seedItem(h, name: 'Tortillas');
      // Event 1: soap counted — 2 used at a 200-person event.
      final counted = await seedEvent(
        h,
        name: 'Small event',
        date: '2026-07-01',
        exposure: 200,
        itemIds: [soap],
      );
      await activateEvent(h, counted);
      await confirmCloseout(
        h,
        counted,
        exposure: 200,
        lines: [
          CloseoutFormLine(
            itemId: soap,
            depletion: Quantity.fromMicros(2000000),
          ),
        ],
      );
      // Event 2: soap planned but skipped — only the tortillas line
      // confirms, exactly what the UI test's confirm sends.
      final skipped = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 150,
        itemIds: [tortillas, soap],
      );
      await activateEvent(h, skipped);
      await confirmCloseout(
        h,
        skipped,
        exposure: 150,
        lines: [
          CloseoutFormLine(
            itemId: soap,
            depletion: Quantity.fromMicros(2000000),
            skipped: true,
          ),
          CloseoutFormLine(
            itemId: tortillas,
            depletion: Quantity.fromMicros(3000000),
          ),
        ],
      );
      final nextEvent = await seedEvent(
        h,
        name: 'Autumn fair',
        date: '2026-09-01',
        exposure: 2000,
        itemIds: [soap],
      );
      final view =
          (await h.read(forecastServiceProvider).generateSnapshot(nextEvent))
              .fold((v) => v, (e) => fail('${e.code}: ${e.message}'));
      final line = view.lines.single;
      expect(line.demandBasis, DemandBasis.perEvent);
      expect(
        line.evidence,
        hasLength(1),
        reason: 'the skipped event taught nothing',
      );
      expect(line.expectedUseMicros, 2000000, reason: 'median of real counts');
    });
  });

  testWidgets('unskipping a supply line opens the counting body, and the '
      "overflow's used-instead path confirms it", (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final cleaning = await folderIdByName(h, 'Cleaning & setup');
      final soap = await seedItem(h, name: 'Dish soap', folderId: cleaning);
      eventId = await seedEvent(
        h,
        name: 'Fete',
        date: '2026-08-11',
        exposure: 100,
        itemIds: [soap],
      );
      await activateEvent(h, eventId);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // Starts skipped and folded: no boxes, nothing to confuse.
    expect(find.widgetWithText(TextFormField, 'Left'), findsNothing);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('0 of 0 confirmed'), findsOneWidget);

    // This time somebody counted. Tap the folded card open, untick Skip.
    await _tap(tester, find.text('Dish soap'));
    await _tap(tester, find.widgetWithText(FilterChip, 'Skip'));
    expect(find.widgetWithText(TextFormField, 'Left'), findsOneWidget);
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

    // Nobody counts leftover soap, so the overflow's used-instead mode
    // swaps the two boxes for the one number that means something here.
    await _tap(tester, find.text('More'));
    await _tap(tester, find.text('Enter what was used instead'));
    expect(find.widgetWithText(TextFormField, 'Left'), findsNothing);
    expect(find.text('What was used or sold.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Used'), '1');
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    await _tap(tester, find.text('Finish closeout'));
    await _tap(tester, find.text('Confirm'));

    await tester.runAsync(() async {
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      expect(revisions.single.lines.single.depletion.micros, 1000000);
    });
    await h.flushTimers(tester);
  });
}
