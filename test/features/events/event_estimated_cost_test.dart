/// "Estimated cost" on `/events/:eventId` — the owner's question ("how much
/// will this event cost?") answered while she can still do something about
/// it, i.e. for PLANNED and ACTIVE events only.
///
/// Two figures, never compared by the app: the hero is her packing list at
/// today's prices, and under it the history line is what events like this
/// one usually cost, read off confirmed closeouts. Both obey the same
/// honesty rules — an unpriced item is counted out loud, one or two past
/// events are called thin evidence rather than a pattern, unpriced history
/// makes the prediction a floor, and an absent answer is absent rather than
/// a zero or an empty state.
///
/// Most cases drive the two cost providers directly: the copy and the
/// branches are this screen's contract, and pinning them to a seeded
/// database would really be testing the cost service twice. One case takes
/// the real path end to end so the wiring itself is proven.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/events/presentation/event_detail_screen.dart';
import 'package:loadout/features/forecasting/domain/event_cost.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

/// The detail screen with the two cost answers supplied directly. Nested
/// under the harness's own scope, so everything else on the screen (the
/// event, the workspace, the snapshot tile) still comes off the real
/// database.
Widget screenWithCost(
  String eventId, {
  PlannedCost? planned,
  EventCostPrediction? prediction,
}) => ProviderScope(
  // A fresh scope per pump: re-pumping the same screen with DIFFERENT
  // overrides otherwise updates the widget in place and keeps the first
  // container's already-resolved values.
  key: UniqueKey(),
  overrides: [
    plannedCostProvider(
      eventId,
    ).overrideWith((ref) => Stream.value(planned ?? noPlannedCost)),
    eventCostPredictionProvider(
      eventId,
    ).overrideWith((ref) => Stream.value(prediction)),
  ],
  child: EventDetailScreen(eventId: eventId),
);

const noPlannedCost = PlannedCost(
  total: Money.zero,
  pricedItemCount: 0,
  unpricedItemCount: 0,
);

EventCostEvidence evidence({
  required String name,
  required int totalCents,
  required int exposure,
  int unpricedLines = 0,
}) => EventCostEvidence(
  eventId: name,
  eventName: name,
  total: Money.fromCents(totalCents),
  confirmedExposure: exposure,
  unpricedLineCount: unpricedLines,
);

EventCostPrediction prediction({
  required int perPersonCents,
  required int totalCents,
  required int exposure,
  required List<EventCostEvidence> from,
}) => EventCostPrediction(
  perPerson: Money.fromCents(perPersonCents),
  total: Money.fromCents(totalCents),
  evidence: from,
  exposure: exposure,
);

/// A planned event with one priced item on its list.
Future<String> plannedEvent(
  AppHarness h, {
  int exposure = 100,
  bool priced = true,
}) async {
  final cups = await seedItem(
    h,
    name: 'Cups',
    servesPerUnit: Quantity.whole(4),
    unitPrice: priced ? Money.fromCents(200) : null,
  );
  return seedEvent(
    h,
    name: 'Street fair',
    date: '2026-09-10',
    exposure: exposure,
    itemIds: [cups],
  );
}

void main() {
  testWidgets('a planned event costs its list at today\'s prices, through '
      'the real cost provider', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h);
      // The planned quantity is the forecast's load; without a snapshot
      // there is nothing to price.
      await h.read(forecastServiceProvider).generateSnapshot(eventId);
    });

    await h.pumpScreen(tester, EventDetailScreen(eventId: eventId));

    expect(find.text('Estimated cost'), findsOneWidget);
    expect(
      find.text("What you're bringing, at today's prices."),
      findsOneWidget,
    );
    // 100 people, 1 cup serves 4, balanced policy → the snapshot's load of
    // 28 cups, at $2.00 each. The figure is the forecast's own, priced —
    // never a second opinion about how much to bring.
    expect(find.text(r'$56'), findsOneWidget);
    // The closed-event section stays where it belongs.
    expect(find.text('Spent'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('no forecast yet means no planned quantity to price, so the '
      'section does not render — never a \$0', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h);
    });

    await h.pumpScreen(tester, EventDetailScreen(eventId: eventId));
    expect(find.text('Estimated cost'), findsNothing);
    expect(find.textContaining(r'$0'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('mixed pricing shows the total AND says what it left out', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h);
    });

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        planned: PlannedCost(
          total: Money.fromCents(28450),
          pricedItemCount: 9,
          unpricedItemCount: 3,
        ),
      ),
    );
    expect(find.text(r'$284.50'), findsOneWidget);
    expect(
      find.text('3 items have no price yet — not counted.'),
      findsOneWidget,
    );
    await h.flushTimers(tester);
  });

  testWidgets('one unpriced item says so in the singular, and a fully priced '
      'list says nothing at all', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h);
    });

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        planned: PlannedCost(
          total: Money.fromCents(1200),
          pricedItemCount: 4,
          unpricedItemCount: 1,
        ),
      ),
    );
    expect(find.text('1 item has no price yet — not counted.'), findsOneWidget);

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        planned: PlannedCost(
          total: Money.fromCents(1200),
          pricedItemCount: 5,
          unpricedItemCount: 0,
        ),
      ),
    );
    expect(find.text(r'$12'), findsOneWidget);
    expect(find.textContaining('no price yet'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('nothing priced and no history: the whole section disappears', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h, priced: false);
    });

    await h.pumpScreen(tester, screenWithCost(eventId));
    expect(find.text('Estimated cost'), findsNothing);
    expect(find.textContaining('Events like this'), findsNothing);
    expect(find.textContaining('no price yet'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('the history line carries the rate it was scaled at and how '
      'many events it read', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h, exposure: 150);
    });

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        planned: PlannedCost(
          total: Money.fromCents(28450),
          pricedItemCount: 9,
          unpricedItemCount: 0,
        ),
        prediction: prediction(
          perPersonCents: 210,
          totalCents: 31500,
          exposure: 150,
          from: [
            for (var i = 1; i <= 4; i++)
              evidence(name: 'Fete $i', totalCents: 30000, exposure: 150),
          ],
        ),
      ),
    );

    // Both figures, side by side, with no editorial about the gap.
    expect(find.text(r'$284.50'), findsOneWidget);
    expect(
      find.text(r'Events like this usually cost about $315'),
      findsOneWidget,
    );
    expect(find.text(r'$2.10 a person × 150'), findsOneWidget);
    expect(find.text('from 4 past events'), findsOneWidget);
    expect(find.textContaining('pattern'), findsNothing);
    expect(find.textContaining('floor'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('one or two past events are called thin evidence, not a '
      'pattern', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h);
    });

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        prediction: prediction(
          perPersonCents: 210,
          totalCents: 21000,
          exposure: 100,
          from: [evidence(name: 'Fete', totalCents: 21000, exposure: 100)],
        ),
      ),
    );
    expect(
      find.text(
        'from 1 past event — one event is a data point, not a '
        'pattern.',
      ),
      findsOneWidget,
    );

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        prediction: prediction(
          perPersonCents: 210,
          totalCents: 21000,
          exposure: 100,
          from: [
            evidence(name: 'Fete', totalCents: 21000, exposure: 100),
            evidence(name: 'Market', totalCents: 21000, exposure: 100),
          ],
        ),
      ),
    );
    expect(
      find.text('from 2 past events — two is thin evidence, not a pattern.'),
      findsOneWidget,
    );
    await h.flushTimers(tester);
  });

  testWidgets('history with unpriced lines is called a floor', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h);
    });

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        prediction: prediction(
          perPersonCents: 210,
          totalCents: 21000,
          exposure: 100,
          from: [
            evidence(name: 'Fete', totalCents: 21000, exposure: 100),
            evidence(name: 'Market', totalCents: 20000, exposure: 100),
            evidence(
              name: 'Fair',
              totalCents: 19000,
              exposure: 100,
              unpricedLines: 2,
            ),
          ],
        ),
      ),
    );
    expect(
      find.text(
        'Some of those events had items with no price, so this is a floor.',
      ),
      findsOneWidget,
    );
    expect(find.text('from 3 past events'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('no prediction: the estimate stands alone, with no empty state '
      'where the history would be', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h);
    });

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        planned: PlannedCost(
          total: Money.fromCents(28450),
          pricedItemCount: 9,
          unpricedItemCount: 0,
        ),
      ),
    );
    expect(find.text(r'$284.50'), findsOneWidget);
    expect(find.textContaining('Events like this'), findsNothing);
    expect(find.textContaining('past event'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('an active event gets the section too, and history alone is '
      'enough to render it', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h);
      await activateEvent(h, eventId);
    });

    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        prediction: prediction(
          perPersonCents: 210,
          totalCents: 21000,
          exposure: 100,
          from: [
            for (var i = 1; i <= 3; i++)
              evidence(name: 'Fete $i', totalCents: 21000, exposure: 100),
          ],
        ),
      ),
    );
    expect(find.text('Estimated cost'), findsOneWidget);
    expect(
      find.text(r'Events like this usually cost about $210'),
      findsOneWidget,
    );
    // No planned cost: the hero and its label are simply absent.
    expect(find.textContaining("What you're bringing"), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('a closed event keeps Spent and never shows the estimate', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final cups = await seedItem(
        h,
        name: 'Cups',
        unitPrice: Money.fromCents(200),
      );
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [cups],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [CloseoutFormLine(itemId: cups, depletion: Quantity.whole(30))],
      );
    });

    await h.pumpScreen(tester, EventDetailScreen(eventId: eventId));
    expect(find.text('Spent'), findsOneWidget);
    expect(find.text(r'$60'), findsOneWidget);
    expect(find.text('Estimated cost'), findsNothing);
    expect(find.textContaining('Events like this'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('both answers survive 200 % text scale, in both brightnesses', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await plannedEvent(h, exposure: 150);
    });

    // An overflow at 200 % scale throws and fails the test here.
    await h.pumpScreen(
      tester,
      screenWithCost(
        eventId,
        planned: PlannedCost(
          total: Money.fromCents(28450),
          pricedItemCount: 9,
          unpricedItemCount: 3,
        ),
        prediction: prediction(
          perPersonCents: 210,
          totalCents: 31500,
          exposure: 150,
          from: [
            evidence(
              name: 'Fete',
              totalCents: 31500,
              exposure: 150,
              unpricedLines: 1,
            ),
          ],
        ),
      ),
    );
    expect(find.text(r'$284.50'), findsOneWidget);
    expect(find.text(r'$2.10 a person × 150'), findsOneWidget);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text(r'$284.50'), findsOneWidget);
    await h.flushTimers(tester);
  });
}
