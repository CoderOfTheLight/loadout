/// §9 `/recipes/:recipeId` — RecipeDetailScreen widget tests: the current
/// revision (yield, table-like ingredient lines), prior revisions rendered
/// verbatim from behind ONE overflow entry, archive/unarchive from the same
/// overflow, and the v5 decoupled states — ingredient lines read
/// amount-first ("0.5 tsp · Secret spice"), a standalone recipe offers
/// "Add to my items" (and hides "Scale to event"), a bound recipe shows
/// where it lives instead.
///
/// Deliberately gone (owner feedback: the subpages are too complicated):
/// the standing "Viewing / Revision 2 · date" dropdown, the "Entered by
/// hand" / "Scanned" source badges, the revision-history list at the foot
/// of the screen, and the "Output" label over the recipe's own name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  testWidgets('shows current revision and renders prior ones verbatim', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final recipeId = (await tester.runAsync(() async {
      final kit = await seedItem(h, 'Taco kit');
      final tortillas = await seedItem(h, 'Tortillas');
      final id = await seedRecipe(
        h,
        name: 'Taco kit build',
        outputItemId: kit,
        yieldWhole: 10,
        yieldLabel: '10 kits',
        lines: {tortillas: 20},
      );
      // Append revision 2 through the real service.
      unwrap(
        await h
            .read(recipeServiceProvider)
            .reviseRecipe(
              recipeId: id,
              draft: RecipeFormDraft(
                name: 'Taco kit build',
                outputItemId: kit,
                yieldQuantity: Quantity.whole(12),
                yieldLabel: '12 kits',
                note: 'v2 method',
                lines: [
                  RecipeFormLine(
                    itemId: tortillas,
                    quantityPerBatch: Quantity.whole(24),
                  ),
                ],
              ),
            ),
      );
      return id;
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');

    // Current revision (2) by default; ingredient rows are table-like —
    // amount first, then name. Just the name: no "Output" label over it.
    expect(find.text('Taco kit build'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
    expect(find.text('Makes 12 per batch — “12 kits”'), findsOneWidget);
    expect(find.text('24 · Tortillas'), findsOneWidget);
    expect(find.text('v2 method'), findsOneWidget);

    // No revision machinery on the screen you visit to cook: no picker, no
    // source badge, no standing history list.
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.text('Viewing'), findsNothing);
    expect(find.text('Entered by hand'), findsNothing);
    expect(find.text('Scanned'), findsNothing);
    expect(find.text('Revision history'), findsNothing);
    expect(find.text('Revision 2'), findsNothing);
    expect(find.text('Revision 1'), findsNothing);

    // ONE overflow entry reaches every earlier version.
    await tapRecipeMenuItem(tester, 'earlier-versions');
    expect(find.text('Version 2 (the one you cook)'), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('version-1')));

    // Rendered verbatim, with the way back travelling with it.
    expect(find.text('Makes 10 per batch — “10 kits”'), findsOneWidget);
    expect(find.text('20 · Tortillas'), findsOneWidget);
    expect(find.textContaining('Reading version 1 from'), findsOneWidget);
    expect(find.textContaining('The one you cook is version 2'), findsWidgets);

    await tapVisible(tester, find.text('Back to current'));
    expect(find.text('24 · Tortillas'), findsOneWidget);
    expect(find.textContaining('Reading version 1'), findsNothing);
  });

  testWidgets('a standalone recipe renders free lines with their units, offers '
      '"Add to my items", and hides "Scale to event"', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final recipeId = (await tester.runAsync(() async {
      final beans = await seedItem(h, 'Beans');
      return seedStandaloneRecipe(
        h,
        name: 'Chilli batch',
        lines: [
          RecipeFormLine(itemId: beans, quantityPerBatch: Quantity.whole(3)),
          RecipeFormLine(
            name: 'Secret spice',
            unitLabel: 'tsp',
            quantityPerBatch: Quantity.fromMicros(500000), // 0.5
          ),
        ],
      );
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');

    // The output IS the recipe (nothing in the items list yet), so the
    // labeled action is offered and scaling is not (no packing list can
    // carry it).
    expect(find.byKey(const Key('add-to-items')), findsOneWidget);
    expect(find.text('Add to my items'), findsOneWidget);
    expect(find.byKey(const Key('scale-to-event')), findsNothing);
    expect(find.byKey(const Key('in-items-location')), findsNothing);

    // Table-like lines: the linked line as its live item, the free line
    // under its own name with its display-only unit label.
    expect(find.text('3 · Beans'), findsOneWidget);
    expect(find.text('0.5 tsp · Secret spice'), findsOneWidget);
  });

  testWidgets('archive and unarchive round-trip', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final recipeId = (await tester.runAsync(() async {
      final salsa = await seedItem(h, 'Salsa');
      final tomato = await seedItem(h, 'Tomato');
      return seedRecipe(
        h,
        name: 'Salsa base',
        outputItemId: salsa,
        lines: {tomato: 3},
      );
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');

    // Labeled words everywhere: "Revise" in the bar, "More" beside it —
    // never an icon on its own (spec §2).
    expect(find.text('Revise'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    // Archive is one level down, in the overflow.
    expect(find.text('Archive'), findsNothing);
    await tapRecipeMenuItem(tester, 'archive-action');
    // Drift publishes query-stream updates on a zero-duration timer that
    // pumpAndSettle does not wait for.
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    expect(find.textContaining('This recipe is archived'), findsOneWidget);
    final archived = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(archived.recipe.isArchived, isTrue);

    // The same overflow slot flips to the unarchive word (the banner's own
    // "Unarchive" action stays a labeled button on the screen itself).
    await tapRecipeMenuItem(tester, 'archive-action');
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    expect(find.textContaining('This recipe is archived'), findsNothing);
    final unarchived = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(unarchived.recipe.isArchived, isFalse);
  });

  testWidgets('renders at 200 % text scale on a 320 dp viewport, with every '
      'action still a word', (tester) async {
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
      final kit = await seedItem(h, 'Taco kit');
      final tortillas = await seedItem(h, 'Tortillas');
      final id = await seedRecipe(
        h,
        name: 'Taco kit build',
        outputItemId: kit,
        lines: {tortillas: 20},
      );
      unwrap(
        await h
            .read(recipeServiceProvider)
            .reviseRecipe(
              recipeId: id,
              draft: RecipeFormDraft(
                name: 'Taco kit build',
                outputItemId: kit,
                yieldQuantity: Quantity.whole(12),
                lines: [
                  RecipeFormLine(
                    itemId: tortillas,
                    quantityPerBatch: Quantity.whole(24),
                  ),
                ],
              ),
            ),
      );
      return id;
    }))!;

    // An overflow at 200 % scale would throw and fail the test here — the
    // app-bar actions row and the old revision picker both used to.
    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId');
    expect(find.text('24 · Tortillas'), findsOneWidget);

    // At this size "Revise" steps into the menu rather than overflowing the
    // bar — but it is still a WORD, never a bare glyph.
    expect(find.text('More'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('recipe-menu')));
    expect(find.text('Revise'), findsOneWidget);
    expect(find.text('Earlier versions'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });
}
