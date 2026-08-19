/// "Scale to event" (proposal §3): pure arithmetic pins for
/// `RecipeBatchPlan` (ceil batches, spare, and the one-sentence answer) and
/// the end-to-end widget flow — the sheet reads the event's PERSISTED
/// packing-list number and shows whole batches plus each ingredient. The
/// saved recipe never changes.
///
/// The sentence is the product ruling: "Make 3 batches. That's 30 — you
/// need 22." The old "Needs 2.2 batches (arrow) make 3 — about 8 spare
/// portions" is gone, and with it the multiplier pill and the "Makes 30"
/// glance figure that said the same thing twice more.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/unit_ratio.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';
import 'package:loadout/features/recipes/presentation/recipe_scale_math.dart';
import 'package:loadout/features/recipes/presentation/recipe_scale_sheet.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  group('RecipeBatchPlan arithmetic (integer micros only)', () {
    test('fractional need rounds up and says so: 34 needed, yield 10', () {
      final plan = RecipeBatchPlan(
        needMicros: Quantity.whole(34).micros,
        yieldMicros: Quantity.whole(10).micros,
      );
      expect(plan.batches, 4);
      expect(plan.spareMicros, Quantity.whole(6).micros);
      expect(plan.verdict, "Make 4 batches. That's 40 — you need 34.");
    });

    test('exact multiple: 30 needed, yield 10', () {
      final plan = RecipeBatchPlan(
        needMicros: Quantity.whole(30).micros,
        yieldMicros: Quantity.whole(10).micros,
      );
      expect(plan.batches, 3);
      expect(plan.spareMicros, 0);
      expect(plan.verdict, "Make 3 batches. That's 30 — you need 30.");
    });

    test('single batch reads in the singular', () {
      final plan = RecipeBatchPlan(
        needMicros: Quantity.whole(10).micros,
        yieldMicros: Quantity.whole(10).micros,
      );
      expect(plan.verdict, "Make 1 batch. That's 10 — you need 10.");
    });

    test('nothing needed means no batches', () {
      final plan = RecipeBatchPlan(
        needMicros: 0,
        yieldMicros: Quantity.whole(10).micros,
      );
      expect(plan.batches, 0);
      expect(
        plan.verdict,
        'The packing list says none are needed. Make no batches.',
      );
    });

    test('a part-batch need still reads as a whole-batch instruction', () {
      // 1 needed, yield 3: a third of a batch, which nobody can cook.
      final plan = RecipeBatchPlan(
        needMicros: Quantity.whole(1).micros,
        yieldMicros: Quantity.whole(3).micros,
      );
      expect(plan.batches, 1);
      expect(plan.spareMicros, Quantity.whole(2).micros);
      expect(plan.verdict, "Make 1 batch. That's 3 — you need 1.");
    });

    test('a forecast residue is display-rounded, never spelled out', () {
      // 21.999999 needed off the engine, yield 10: the sentence says 22.
      final plan = RecipeBatchPlan(
        needMicros: 21999999,
        yieldMicros: Quantity.whole(10).micros,
      );
      expect(plan.batches, 3);
      expect(plan.verdict, "Make 3 batches. That's 30 — you need 22.");
    });

    test('scaledIngredientTotal multiplies exactly', () {
      expect(scaledIngredientTotal(Quantity.whole(3), 3), '9');
      expect(scaledIngredientTotal(Quantity.fromMicros(2500000), 3), '7.5');
      expect(scaledIngredientTotal(Quantity.whole(3), 0), '0');
    });
  });

  testWidgets('scales the current revision against the stored packing list', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      // "1 per 10 people" → 200 attendance × 1/10 = 20 expected, +10 %
      // balanced reserve = 22 to bring: the effective load the sheet must
      // read (never recompute).
      final chilli = unwrap(
        await h
            .read(catalogServiceProvider)
            .createItem(
              ItemDraft(name: 'Chilli', perPersonRatio: UnitRatio(1, 10)),
            ),
      );
      final beans = await seedItem(h, 'Beans');
      final tomatoes = await seedItem(h, 'Tomatoes');
      recipeId = unwrap(
        await h
            .read(recipeServiceProvider)
            .createRecipe(
              RecipeFormDraft(
                name: 'Chilli batch',
                outputItemId: chilli,
                yieldQuantity: Quantity.whole(10),
                yieldLabel: '10 portions',
                lines: [
                  RecipeFormLine(
                    itemId: beans,
                    quantityPerBatch: Quantity.whole(3),
                  ),
                  RecipeFormLine(
                    itemId: tomatoes,
                    quantityPerBatch: Quantity.fromMicros(2500000), // 2.5
                  ),
                  // v5: a FREE line (no catalog link) with a display-only
                  // unit label scales exactly like a linked one.
                  RecipeFormLine(
                    name: 'Secret spice',
                    unitLabel: 'tsp',
                    quantityPerBatch: Quantity.fromMicros(500000), // 0.5
                  ),
                ],
              ),
            ),
      );
      final eventId = unwrap(
        await h
            .read(eventServiceProvider)
            .createEvent(
              EventDraft(
                name: 'Village fair',
                scheduledDate: '2026-09-01',
                plannedExposure: 200,
                plannedItemIds: [chilli],
              ),
            ),
      );
      unwrap(await h.read(forecastServiceProvider).generateSnapshot(eventId));
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');

    await tapVisible(tester, find.byKey(const Key('scale-to-event')));

    // The only upcoming event is preselected; the sheet reads the STORED
    // load (22) and says the rounding out loud with exact numbers:
    // ceil(22 / 10) = 3 batches, 30 − 22 = 8 spare.
    expect(find.textContaining('Village fair · 2026-09-01'), findsWidgets);
    expect(
      find.textContaining("From this event's packing list for 200 attendance"),
      findsOneWidget,
    );
    final verdict = tester.widget<Text>(find.byKey(const Key('scale-verdict')));
    expect(verdict.data, "Make 3 batches. That's 30 — you need 22.");

    // Cold-start honesty travels with the number.
    expect(
      find.textContaining('An estimate — nothing confirmed yet'),
      findsOneWidget,
    );

    // The multiplier pill and the "Makes 30" glance figure are gone: the
    // sentence above already carries both numbers.
    Finder inSheet(Finder finder) =>
        find.descendant(of: find.byType(RecipeScaleSheet), matching: finder);
    expect(inSheet(find.textContaining('×3')), findsNothing);
    expect(inSheet(find.text('Makes 30')), findsNothing);

    // Each ingredient row: the scaled total is the big figure, the
    // per-batch amount reads as its caption — both exact.
    expect(inSheet(find.text('Beans')), findsOneWidget);
    expect(inSheet(find.text('3 per batch')), findsOneWidget);
    expect(inSheet(find.text('9')), findsOneWidget); // for all batches
    expect(inSheet(find.text('Tomatoes')), findsOneWidget);
    expect(inSheet(find.text('2.5 per batch')), findsOneWidget);
    expect(inSheet(find.text('7.5')), findsOneWidget);
    // The free line scales under its own name with its display-only label.
    expect(inSheet(find.text('Secret spice')), findsOneWidget);
    expect(inSheet(find.text('0.5 tsp per batch')), findsOneWidget);
    expect(inSheet(find.text('1.5 tsp')), findsOneWidget);

    // A view only: the saved recipe did not change.
    final detail = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(detail.revisions, hasLength(1));
    expect(detail.revisions.first.yieldQuantity, Quantity.whole(10));

    // Close the sheet so its providers dispose cleanly.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('an event without a packing list is said, not guessed', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final soup = await seedItem(h, 'Soup');
      final carrots = await seedItem(h, 'Carrots');
      recipeId = await seedRecipe(
        h,
        name: 'Soup base',
        outputItemId: soup,
        lines: {carrots: 4},
      );
      unwrap(
        await h
            .read(eventServiceProvider)
            .createEvent(
              const EventDraft(
                name: 'Match day',
                scheduledDate: '2026-09-08',
                plannedExposure: 300,
              ),
            ),
      );
      // No snapshot generated on purpose.
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');
    await tapVisible(tester, find.byKey(const Key('scale-to-event')));

    expect(
      find.textContaining('No packing list for this event yet'),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('one batch drops the "per batch" column: the two figures are '
      'the same number', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final recipeId = (await tester.runAsync(() async {
      // 200 attendance × 1/10 = 20, +10 % balanced reserve = 22 to bring;
      // one 30-portion batch covers it.
      final chilli = unwrap(
        await h
            .read(catalogServiceProvider)
            .createItem(
              ItemDraft(name: 'Chilli', perPersonRatio: UnitRatio(1, 10)),
            ),
      );
      final beans = await seedItem(h, 'Beans');
      final id = unwrap(
        await h
            .read(recipeServiceProvider)
            .createRecipe(
              RecipeFormDraft(
                name: 'Big chilli',
                outputItemId: chilli,
                yieldQuantity: Quantity.whole(30),
                lines: [
                  RecipeFormLine(
                    itemId: beans,
                    quantityPerBatch: Quantity.whole(3),
                  ),
                ],
              ),
            ),
      );
      final eventId = unwrap(
        await h
            .read(eventServiceProvider)
            .createEvent(
              EventDraft(
                name: 'Village fair',
                scheduledDate: '2026-09-01',
                plannedExposure: 200,
                plannedItemIds: [chilli],
              ),
            ),
      );
      unwrap(await h.read(forecastServiceProvider).generateSnapshot(eventId));
      return id;
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');
    await tapVisible(tester, find.byKey(const Key('scale-to-event')));

    final verdict = tester.widget<Text>(find.byKey(const Key('scale-verdict')));
    expect(verdict.data, "Make 1 batch. That's 30 — you need 22.");

    Finder inSheet(Finder finder) =>
        find.descendant(of: find.byType(RecipeScaleSheet), matching: finder);
    expect(inSheet(find.text('3')), findsOneWidget); // the amount to buy
    expect(
      inSheet(find.textContaining('per batch')),
      findsNothing,
      reason: 'at one batch the second column repeats the first',
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('the scale sheet survives 200 % text scale on a 320 dp '
      'viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final recipeId = (await tester.runAsync(() async {
      final chilli = unwrap(
        await h
            .read(catalogServiceProvider)
            .createItem(
              ItemDraft(name: 'Chilli', perPersonRatio: UnitRatio(1, 10)),
            ),
      );
      final beans = await seedItem(h, 'Beans');
      final id = await seedRecipe(
        h,
        name: 'Chilli batch',
        outputItemId: chilli,
        yieldWhole: 10,
        lines: {beans: 3},
      );
      final eventId = unwrap(
        await h
            .read(eventServiceProvider)
            .createEvent(
              EventDraft(
                name: 'Village fair',
                scheduledDate: '2026-09-01',
                plannedExposure: 200,
                plannedItemIds: [chilli],
              ),
            ),
      );
      unwrap(await h.read(forecastServiceProvider).generateSnapshot(eventId));
      return id;
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');
    // An overflow at 200 % scale would throw and fail the test here.
    await tapVisible(tester, find.byKey(const Key('scale-to-event')));
    final verdict = tester.widget<Text>(find.byKey(const Key('scale-verdict')));
    expect(verdict.data, "Make 3 batches. That's 30 — you need 22.");

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });
}
