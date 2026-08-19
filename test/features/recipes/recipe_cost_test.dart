/// What a recipe costs (v7 money), on both recipe screens.
///
/// The pins:
///  * the DETAIL screen prices one batch of the CURRENT revision at TODAY's
///    prices, under the yield, with the per-portion figure beside it where
///    dividing the yield is honest arithmetic;
///  * an ingredient with no price — unlinked, or linked to an unpriced item
///    — contributes nothing and is COUNTED in one plain note;
///  * a recipe with nothing priced shows no money at all, never a $0;
///  * the figure is LIVE: repricing an ingredient moves it, and an
///    immutable old revision is never costed at today's prices;
///  * the LIST screen carries the same figure caption-tier, saying "from"
///    when it is a floor rather than a total.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/recipes/domain/recipe_cost.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';
import 'package:loadout/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:loadout/features/recipes/presentation/recipe_list_screen.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

const Key batchCostKey = Key('recipe-batch-cost');

Future<AppHarness> startWorkspace(WidgetTester tester) async => (await tester
    .runAsync(() => AppHarness.start(state: AppHarnessState.workspace)))!;

Future<String> seedPricedItem(AppHarness h, String name, int cents) async =>
    unwrap(
      await h
          .read(catalogServiceProvider)
          .createItem(ItemDraft(name: name, unitPrice: Money.fromCents(cents))),
    );

Future<void> reprice(
  AppHarness h,
  String itemId,
  String name,
  int cents,
) async {
  final result = await h
      .read(catalogServiceProvider)
      .updateItem(
        itemId: itemId,
        draft: ItemDraft(name: name, unitPrice: Money.fromCents(cents)),
      );
  expect(result, isA<Ok<void>>());
}

void main() {
  group('recipeBatchCost', () {
    test('prices only the lines that carry a price, and counts the rest', () {
      final cost = recipeBatchCost([
        (quantityMicros: 3000000, unitPrice: Money.fromCents(200)),
        (quantityMicros: 2000000, unitPrice: Money.fromCents(150)),
        (quantityMicros: 1000000, unitPrice: null),
      ]);
      expect(cost.total, Money.fromCents(900));
      expect(cost.pricedLineCount, 2);
      expect(cost.unpricedLineCount, 1);
      expect(cost.isEmpty, isFalse);
      expect(cost.isPartial, isTrue);
    });

    test('nothing priced is empty, not zero-worth', () {
      final cost = recipeBatchCost([
        (quantityMicros: 3000000, unitPrice: null),
      ]);
      expect(cost.isEmpty, isTrue);
      expect(cost.isPartial, isFalse);
    });

    test('fractional amounts stay exact (BigInt, truncating at the cent)', () {
      final cost = recipeBatchCost([
        // 1.5 units at $0.03 is 4 cents, not 5 — Money's documented rule.
        (quantityMicros: 1500000, unitPrice: Money.fromCents(3)),
      ]);
      expect(cost.total, Money.fromCents(4));
    });

    test('a per-portion figure only where dividing the yield is honest', () {
      final cost = recipeBatchCost([
        (quantityMicros: 1000000, unitPrice: Money.fromCents(1000)),
      ]);
      // 24 portions of a $10 batch, rounded half-up once: 41.66… → 42c.
      expect(cost.perYieldUnit(Quantity.whole(24)), Money.fromCents(42));
      // A yield of one says the same thing twice.
      expect(cost.perYieldUnit(Quantity.whole(1)), isNull);
      // Half a batch of something is not a number of portions.
      expect(cost.perYieldUnit(Quantity.fromMicros(2500000)), isNull);
      expect(cost.perYieldUnit(Quantity.zero), isNull);
    });
  });

  testWidgets('the detail screen prices one batch under the yield, with the '
      'per-portion figure beside it', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final flour = await seedPricedItem(h, 'Flour', 200);
      final sugar = await seedPricedItem(h, 'Sugar', 150);
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Scones',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
          RecipeFormLine(itemId: sugar, quantityPerBatch: Quantity.whole(2)),
        ],
      );
    });

    await h.pumpScreen(tester, RecipeDetailScreen(recipeId: recipeId));

    // 3 × $2.00 + 2 × $1.50 = $9.00, over a yield of 10.
    expect(find.byKey(batchCostKey), findsOneWidget);
    expect(find.text(r'$9 a batch · $0.90 each'), findsOneWidget);
    expect(find.text("At today's item prices."), findsOneWidget);
    expect(find.textContaining('not counted'), findsNothing);
    // It sits under the yield, so it reads as "this batch costs X".
    expect(
      tester.getTopLeft(find.text('Makes 10 per batch')).dy,
      lessThan(tester.getTopLeft(find.byKey(batchCostKey)).dy),
    );
    await h.flushTimers(tester);
  });

  testWidgets('unlinked and unpriced ingredients are counted in the note, '
      'never in the total', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final flour = await seedPricedItem(h, 'Flour', 200);
      final butter = await seedItem(h, 'Butter'); // linked, never priced
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Scones',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
          RecipeFormLine(itemId: butter, quantityPerBatch: Quantity.whole(1)),
          // A free line: no catalog link at all.
          const RecipeFormLine(name: 'Salt', quantityPerBatch: Quantity.one),
        ],
      );
    });

    await h.pumpScreen(tester, RecipeDetailScreen(recipeId: recipeId));

    // Only the flour: $6.00, not a cent more for the two unpriced lines.
    expect(find.text(r'$6 a batch · $0.60 each'), findsOneWidget);
    expect(
      find.text('2 ingredients have no price — not counted.'),
      findsOneWidget,
    );
    await h.flushTimers(tester);
  });

  testWidgets('one unpriced ingredient is said in the singular', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final flour = await seedPricedItem(h, 'Flour', 200);
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Scones',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
          const RecipeFormLine(name: 'Salt', quantityPerBatch: Quantity.one),
        ],
      );
    });

    await h.pumpScreen(tester, RecipeDetailScreen(recipeId: recipeId));

    expect(
      find.text('1 ingredient has no price — not counted.'),
      findsOneWidget,
    );
    expect(find.textContaining('ingredients have no price'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('a recipe with nothing priced shows no cost at all', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final butter = await seedItem(h, 'Butter');
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Scones',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: butter, quantityPerBatch: Quantity.whole(1)),
          const RecipeFormLine(name: 'Salt', quantityPerBatch: Quantity.one),
        ],
      );
    });

    await h.pumpScreen(tester, RecipeDetailScreen(recipeId: recipeId));

    expect(find.byKey(batchCostKey), findsNothing);
    expect(find.text(r'$0'), findsNothing);
    expect(find.textContaining('not counted'), findsNothing);
    expect(find.textContaining("At today's item prices"), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('the cost follows a price change — live, never a snapshot', (
    tester,
  ) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String recipeId;
    late String flour;
    await tester.runAsync(() async {
      flour = await seedPricedItem(h, 'Flour', 200);
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Scones',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
        ],
      );
    });

    await h.pumpScreen(tester, RecipeDetailScreen(recipeId: recipeId));
    expect(find.text(r'$6 a batch · $0.60 each'), findsOneWidget);

    await tester.runAsync(() => reprice(h, flour, 'Flour', 300));
    await tester.pumpAndSettle();
    expect(find.text(r'$9 a batch · $0.90 each'), findsOneWidget);

    // Clearing the price takes the figure away entirely.
    await tester.runAsync(() async {
      final result = await h
          .read(catalogServiceProvider)
          .updateItem(
            itemId: flour,
            draft: const ItemDraft(name: 'Flour'),
          );
      expect(result, isA<Ok<void>>());
    });
    await tester.pumpAndSettle();
    expect(find.byKey(batchCostKey), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('only the current revision is costed — an immutable older one '
      'is never priced at the prices of today', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final flour = await seedPricedItem(h, 'Flour', 200);
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Scones',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
        ],
      );
      unwrap(
        await h
            .read(recipeServiceProvider)
            .reviseRecipe(
              recipeId: recipeId,
              draft: RecipeFormDraft(
                name: 'Scones',
                yieldQuantity: Quantity.whole(10),
                lines: [
                  RecipeFormLine(
                    itemId: flour,
                    quantityPerBatch: Quantity.whole(4),
                  ),
                ],
              ),
            ),
      );
    });

    await h.pumpScreen(tester, RecipeDetailScreen(recipeId: recipeId));
    // Revision 2 is current: 4 × $2.00.
    expect(find.text(r'$8 a batch · $0.80 each'), findsOneWidget);

    // Earlier versions live behind ONE overflow entry now.
    await tapRecipeMenuItem(tester, 'earlier-versions');
    await tapVisible(tester, find.byKey(const ValueKey('version-1')));
    expect(find.text('Makes 10 per batch'), findsOneWidget);
    expect(find.byKey(batchCostKey), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('a yield of one gets no per-portion figure — it would say the '
      'same thing twice', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final flour = await seedPricedItem(h, 'Flour', 200);
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Big tray',
        yieldWhole: 1,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
        ],
      );
    });

    await h.pumpScreen(tester, RecipeDetailScreen(recipeId: recipeId));

    expect(find.text(r'$6 a batch'), findsOneWidget);
    expect(find.textContaining('each'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('the recipe list carries the same figure, and says "from" when '
      'it is only a floor', (tester) async {
    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final flour = await seedPricedItem(h, 'Flour', 200);
      final sugar = await seedPricedItem(h, 'Sugar', 150);
      await seedStandaloneRecipe(
        h,
        name: 'Fully priced',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
          RecipeFormLine(itemId: sugar, quantityPerBatch: Quantity.whole(2)),
        ],
      );
      await seedStandaloneRecipe(
        h,
        name: 'Partly priced',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
          const RecipeFormLine(name: 'Salt', quantityPerBatch: Quantity.one),
        ],
      );
      await seedStandaloneRecipe(
        h,
        name: 'Never priced',
        yieldWhole: 10,
        lines: [
          const RecipeFormLine(name: 'Salt', quantityPerBatch: Quantity.one),
        ],
      );
    });

    await h.pumpScreen(tester, const RecipeListScreen());

    expect(find.text(r'Makes 10 · 2 ingredients · $9 a batch'), findsOneWidget);
    expect(
      find.text(r'Makes 10 · 2 ingredients · from $6 a batch'),
      findsOneWidget,
    );
    // Nothing priced → no money on the row at all, never a $0.
    expect(find.text('Makes 10 · 1 ingredient'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('the list row survives 200 % text scale on a 320 dp viewport, '
      'in both brightnesses', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final flour = await seedPricedItem(h, 'Flour', 200);
      await seedStandaloneRecipe(
        h,
        name: 'Scones',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
          const RecipeFormLine(name: 'Salt', quantityPerBatch: Quantity.one),
        ],
      );
    });

    // An overflow at 200 % scale would throw and fail the test here.
    await h.pumpScreen(tester, const RecipeListScreen());
    expect(find.textContaining(r'from $6 a batch'), findsOneWidget);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.textContaining(r'from $6 a batch'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('the batch cost survives 200 % text scale in both '
      'brightnesses', (tester) async {
    // 320 dp at 200 % scale: the app-bar actions row and the revision
    // picker that used to overflow here without any money on the screen are
    // both fixed (the picker is gone; the bar collapses "Revise" into its
    // menu at this size).
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await startWorkspace(tester);
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final flour = await seedPricedItem(h, 'Flour', 200);
      recipeId = await seedStandaloneRecipe(
        h,
        name: 'Scones',
        yieldWhole: 10,
        lines: [
          RecipeFormLine(itemId: flour, quantityPerBatch: Quantity.whole(3)),
          const RecipeFormLine(name: 'Salt', quantityPerBatch: Quantity.one),
        ],
      );
    });

    await h.pumpScreen(tester, RecipeDetailScreen(recipeId: recipeId));
    expect(find.text(r'$6 a batch · $0.60 each'), findsOneWidget);
    expect(
      find.text('1 ingredient has no price — not counted.'),
      findsOneWidget,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text(r'$6 a batch · $0.60 each'), findsOneWidget);
    await h.flushTimers(tester);
  });
}
