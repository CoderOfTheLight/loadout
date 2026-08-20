/// CloseoutScreen arithmetic display + confirm (§11.3). The card asks one
/// question — "How many are left?" — and derives used as `loaded − left −
/// thrown out` live, with a blank thrown-out counting as 0. On a line the
/// plan says nothing about, Loaded is the second box on the card, because a
/// leftover count has nothing to subtract from without it. A negative line
/// blocks confirm with a warning; confirm closes the event and writes the
/// consume/waste movements atomically, deletes the draft, and surfaces
/// NEGATIVE_ON_HAND as a non-blocking snackbar. Also the overflow's "used
/// instead" mode, zero used (no consume row), Skip (records no line), and
/// the stockout question.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/features/closeout/presentation/closeout_line_card.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

/// Opens a card's overflow and picks [item] from it.
Future<void> _fromMore(WidgetTester tester, String item) async {
  await tester.ensureVisible(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the leftover count derives used live; confirm writes '
      'movements', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String itemId;
    late String eventId;
    await tester.runAsync(() async {
      itemId = await seedItem(h); // Tortillas: a counted thing
      eventId = await seedEvent(
        h,
        name: 'Market',
        date: '2026-08-10',
        exposure: 150,
        itemIds: [itemId],
      );
      await activateEvent(h, eventId);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    // Exposure prefilled from the planned estimate, with the caption.
    expect(find.text('150'), findsOneWidget);
    expect(find.textContaining('Estimate was 150'), findsOneWidget);
    expect(find.text('0 of 1 confirmed'), findsOneWidget);

    // The leftover question, plus Loaded — this line has no plan figure, so
    // its Loaded box is on the card rather than reading as a sentence. The
    // "Worksheet (loaded − left over − waste)" disclosure is gone, and so
    // is the third Used field behind it.
    expect(find.widgetWithText(TextFormField, 'Loaded'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'How many are left?'),
      findsOneWidget,
    );
    expect(find.textContaining('Worksheet'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Used'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Thrown out'), findsNothing);
    expect(find.text('Estimate'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();

    // The leftover count completes the line on its own: a blank thrown-out
    // counts as 0, used derives read-only, and the card confirms.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 8'), findsOneWidget);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);
    // No prose about precedence: the arithmetic is the read-out.
    expect(find.textContaining('excludes waste'), findsNothing);

    // Thrown out lives in the overflow, and shows the defaulted 0 when it
    // is asked for; typing over it re-derives live.
    await _fromMore(tester, 'Some was thrown out');
    final thrownOut = find.widgetWithText(TextFormField, 'Thrown out');
    expect(thrownOut, findsOneWidget);
    await tester.enterText(thrownOut, '1');
    await tester.pumpAndSettle();
    expect(find.text('Used: 7'), findsOneWidget);

    // Live recompute; numbers that cannot add up warn and block confirm.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '12',
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('more than was loaded — check the numbers'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Finish closeout'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 7'), findsOneWidget);

    // Confirm via the confirmation sheet.
    await tester.tap(find.text('Finish closeout'));
    await tester.pumpAndSettle();
    expect(
      find.text('This becomes the history your forecasts learn from.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm'));
    // The one per-session celebration (spec §4): the check disc and one
    // line of owner-register copy, then it dismisses itself.
    for (
      var i = 0;
      i < 60 && find.textContaining('All squared away').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.text('All squared away — 1 of 1 accounted for.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('All squared away'), findsNothing);

    // The worksheet is replaced by its report — the artifact the count
    // produced. Negative on-hand (nothing was ever received) still warns in
    // the receipt snackbar without blocking (§5).
    expect(find.text('Closeout report'), findsOneWidget);
    expect(find.textContaining('negative on-hand'), findsOneWidget);

    // Back leads to the event, not into the finished worksheet.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Closed on'), findsOneWidget);
    expect(find.text('Finish closeout'), findsNothing);

    await tester.runAsync(() async {
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      expect(revisions, hasLength(1));
      final line = revisions.single.lines.single;
      expect(line.loaded!.micros, 10000000);
      expect(line.returned!.micros, 2000000);
      expect(line.waste!.micros, 1000000);
      expect(line.depletion.micros, 7000000);
      expect(line.consumptionMovementId, isNotNull);
      expect(line.wasteMovementId, isNotNull);

      final movements = await h
          .read(inventoryLedgerProvider)
          .movements(event: EventId(eventId));
      expect(movements, hasLength(2));
      final consume = movements.singleWhere(
        (m) => m.kind == MovementKind.consume,
      );
      expect(consume.deltaMicros, -7000000);
      final waste = movements.singleWhere((m) => m.kind == MovementKind.waste);
      expect(waste.deltaMicros, -1000000);

      final position = await h
          .read(inventoryLedgerProvider)
          .position(ItemId(itemId));
      expect(position.onHandMicros, -8000000);

      // The applier deleted the autosaved draft on confirm.
      final draft = await h.read(closeoutServiceProvider).loadDraft(eventId);
      expect(draft, isNull);
    });
  });

  testWidgets('the overflow records what was used instead; zero used, Skip, '
      'stockout flag', (tester) async {
    // Tall enough that all three cards are laid out at once — laziness has
    // its own test.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String itemA;
    late String itemB;
    late String itemC;
    late String eventId;
    await tester.runAsync(() async {
      itemA = await seedItem(h, name: 'Al pastor');
      itemB = await seedItem(h, name: 'Barbacoa');
      itemC = await seedItem(h, name: 'Carnitas');
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-09',
        exposure: 60,
        itemIds: [itemA, itemB, itemC],
      );
      await activateEvent(h, eventId);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId/closeout');

    final cards = find.byType(CloseoutLineCard);
    expect(cards, findsNWidgets(3));

    Finder inCard(int index, Finder matching) =>
        find.descendant(of: cards.at(index), matching: matching);

    // Nothing on any card asks for "used" until somebody says leftovers
    // make no sense here.
    expect(find.widgetWithText(TextFormField, 'Used'), findsNothing);

    // Card 0: the overflow's used-instead mode swaps the boxes for one.
    await tester.tap(inCard(0, find.text('More')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter what was used instead'));
    await tester.pumpAndSettle();
    expect(
      inCard(0, find.widgetWithText(TextFormField, 'Used')),
      findsOneWidget,
    );
    expect(
      inCard(0, find.widgetWithText(TextFormField, 'How many are left?')),
      findsNothing,
    );
    await tester.enterText(
      inCard(0, find.widgetWithText(TextFormField, 'Used')),
      '3',
    );
    await tester.pumpAndSettle();
    // A used figure entered directly says nothing about running out, so the
    // question is asked there rather than derived — and it stays reachable.
    expect(inCard(0, find.text('Did you run out?')), findsOneWidget);
    await tester.tap(inCard(0, find.widgetWithText(ChoiceChip, 'Yes')));
    await tester.pumpAndSettle();

    // Card 1: a confirmed zero is a legal label (§5) — one shortcut does it.
    await tester.tap(inCard(1, find.text('None used')));
    await tester.pumpAndSettle();

    // Card 2: skipped — records no line, and folds to its one-row summary.
    await tester.tap(inCard(2, find.text('More')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip this item'));
    await tester.pumpAndSettle();
    expect(inCard(2, find.text('Skipped')), findsOneWidget);
    // Both counters now speak of the same population: the two lines that
    // still needed counting.
    expect(find.text('2 of 2 confirmed'), findsOneWidget);

    await tester.tap(find.text('Finish closeout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final revisions = await h
          .read(closeoutServiceProvider)
          .watchRevisions(eventId)
          .first;
      final lines = revisions.single.lines;
      expect(lines, hasLength(2)); // the skipped item recorded nothing
      final lineA = lines.singleWhere((l) => l.itemId as String == itemA);
      expect(lineA.depletion.micros, 3000000);
      expect(lineA.stockout, isTrue);
      final lineB = lines.singleWhere((l) => l.itemId as String == itemB);
      expect(lineB.depletion.micros, 0);
      expect(lines.any((l) => l.itemId as String == itemC), isFalse);

      // Zero used writes NO movement; only item A consumed.
      final movements = await h
          .read(inventoryLedgerProvider)
          .movements(event: EventId(eventId));
      expect(movements, hasLength(1));
      expect(movements.single.kind, MovementKind.consume);
      expect(movements.single.deltaMicros, -3000000);
      expect(movements.single.itemId as String, itemA);
    });
  });
}
