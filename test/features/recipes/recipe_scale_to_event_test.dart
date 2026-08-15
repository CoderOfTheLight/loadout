/// "Scale to event" (proposal §3): pure arithmetic pins for
/// `RecipeBatchPlan` (ceil batches, spare, the said-out-loud rounding) and
/// the end-to-end widget flow — the sheet reads the event's PERSISTED
/// packing-list number and shows whole batches plus each ingredient in two
/// exact columns. The saved recipe never changes.
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
      expect(
        plan.verdict,
        'Needs 3.4 batches → make 4 — about 6 spare portions',
      );
    });

    test('exact multiple: 30 needed, yield 10', () {
      final plan = RecipeBatchPlan(
        needMicros: Quantity.whole(30).micros,
        yieldMicros: Quantity.whole(10).micros,
      );
      expect(plan.batches, 3);
      expect(plan.spareMicros, 0);
      expect(plan.verdict, 'Needs 3 batches → make 3 — nothing spare');
    });

    test('single batch reads in the singular', () {
      final plan = RecipeBatchPlan(
        needMicros: Quantity.whole(10).micros,
        yieldMicros: Quantity.whole(10).micros,
      );
      expect(plan.verdict, 'Needs 1 batch → make 1 — nothing spare');
    });

    test('nothing needed means no batches', () {
      final plan = RecipeBatchPlan(
        needMicros: 0,
        yieldMicros: Quantity.whole(10).micros,
      );
      expect(plan.batches, 0);
      expect(
        plan.verdict,
        'The packing list says none are needed — no batches.',
      );
    });

    test('a batch count beyond one decimal is honestly "about"', () {
      // 1 needed, yield 3: exactly 1/3 batch — floored to 0.3, flagged.
      final plan = RecipeBatchPlan(
        needMicros: Quantity.whole(1).micros,
        yieldMicros: Quantity.whole(3).micros,
      );
      expect(plan.batches, 1);
      expect(plan.spareMicros, Quantity.whole(2).micros);
      expect(
        plan.verdict,
        'Needs about 0.3 batches → make 1 — about 2 spare portions',
      );
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
    expect(find.textContaining('bring 22 for 200 attendance'), findsOneWidget);
    final verdict = tester.widget<Text>(find.byKey(const Key('scale-verdict')));
    expect(verdict.data, 'Needs 2.2 batches → make 3 — about 8 spare portions');

    // Cold-start honesty travels with the number.
    expect(
      find.textContaining('An estimate — nothing confirmed yet'),
      findsOneWidget,
    );

    // The scale header (spec §6): the multiplier as one prominent chip and
    // the resulting amount as the glance figure — 3 × 10 = 30, exact.
    Finder inSheet(Finder finder) =>
        find.descendant(of: find.byType(RecipeScaleSheet), matching: finder);
    expect(inSheet(find.text('×3 batches')), findsOneWidget);
    expect(inSheet(find.text('Makes 30')), findsOneWidget);

    // Each ingredient row: the scaled total is the big figure, the
    // per-batch amount reads as its caption — both exact.
    expect(inSheet(find.text('Beans')), findsOneWidget);
    expect(inSheet(find.text('3 per batch')), findsOneWidget);
    expect(inSheet(find.text('9')), findsOneWidget); // for all batches
    expect(inSheet(find.text('Tomatoes')), findsOneWidget);
    expect(inSheet(find.text('2.5 per batch')), findsOneWidget);
    expect(inSheet(find.text('7.5')), findsOneWidget);

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
}
