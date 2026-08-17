/// CloseoutScreen worksheet arithmetic display + confirm (§11.3),
/// leftover-first: the card leads with "How many are left?" (the
/// `returned` count), and used is derived live as loaded − left over −
/// waste (excludes waste) once the worksheet determines it. A leftover
/// count with a loaded value completes the line — a blank waste counts as
/// 0 through the one leftover rule. A negative worksheet blocks confirm
/// with a warning; confirm closes the event and writes the consume/waste
/// movements atomically, deletes the draft, and surfaces NEGATIVE_ON_HAND
/// as a non-blocking snackbar. Also the direct "Used" alternative in the
/// worksheet, zero used (no consume row), skip (records no line), and the
/// stockout flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/features/closeout/presentation/closeout_line_card.dart';
import 'package:loadout/features/inventory/domain/movement.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

void main() {
  testWidgets('a leftover count with loaded derives used live; confirm '
      'writes movements', (tester) async {
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

    // The card leads with the leftover question.
    expect(
      find.widgetWithText(TextFormField, 'How many are left?'),
      findsOneWidget,
    );

    // Open the worksheet and record the load.
    await tester.ensureVisible(find.textContaining('Worksheet'));
    await tester.tap(find.textContaining('Worksheet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Loaded'), '10');
    await tester.pumpAndSettle();

    // The leftover count completes the line: blank waste counts as 0 (the
    // one leftover rule), and used derives read-only — the direct field
    // disappears behind the completed worksheet.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Used: 8'), findsOneWidget);
    expect(find.textContaining('Used excludes waste'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Used'), findsNothing);
    expect(find.text('1 of 1 confirmed'), findsOneWidget);

    // Setting waste explicitly overrides the defaulted 0, live.
    await tester.enterText(find.widgetWithText(TextFormField, 'Waste'), '1');
    await tester.pumpAndSettle();
    expect(find.text('Used: 7'), findsOneWidget);

    // Live recompute; a negative worksheet warns and blocks confirm.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many are left?'),
      '12',
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Left over and waste exceed loaded'),
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

    // Popped back to the detail screen; the event is closed. Negative
    // on-hand (nothing was ever received) warns without blocking (§5).
    expect(find.textContaining('Closed on'), findsOneWidget);
    expect(find.textContaining('negative on-hand'), findsOneWidget);

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

  testWidgets('direct path: used entered directly, zero used, skip, '
      'stockout flag', (tester) async {
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

    // The direct alternative lives in the worksheet expansion now — the
    // collapsed card leads with leftovers.
    expect(find.widgetWithText(TextFormField, 'Used'), findsNothing);

    // Card 0: direct used + "Ran out".
    await tester.ensureVisible(inCard(0, find.textContaining('Worksheet')));
    await tester.tap(inCard(0, find.textContaining('Worksheet')));
    await tester.pumpAndSettle();
    await tester.enterText(
      inCard(0, find.widgetWithText(TextFormField, 'Used')),
      '3',
    );
    await tester.ensureVisible(inCard(0, find.text('Ran out')));
    await tester.tap(inCard(0, find.text('Ran out')));
    await tester.pump();
    // Card 1: a confirmed zero is a legal label (§5).
    await tester.ensureVisible(inCard(1, find.textContaining('Worksheet')));
    await tester.tap(inCard(1, find.textContaining('Worksheet')));
    await tester.pumpAndSettle();
    await tester.enterText(
      inCard(1, find.widgetWithText(TextFormField, 'Used')),
      '0',
    );
    // Card 2: skipped — records no line.
    await tester.ensureVisible(inCard(2, find.text('Skip item')));
    await tester.tap(inCard(2, find.text('Skip item')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('nothing will be recorded for this item'),
      findsOneWidget,
    );
    expect(find.text('2 of 3 confirmed'), findsOneWidget);

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
