/// §9 `/recipes/:recipeId` — RecipeDetailScreen widget tests: current
/// revision (yield, table-like ingredient lines, source badge), immutable
/// revision history with verbatim rendering of prior revisions,
/// archive/unarchive, and the v5 decoupled states — ingredient lines read
/// amount-first ("0.5 tsp · Secret spice"), a standalone recipe offers
/// "Add to my items" (and hides "Scale to event"), a bound recipe shows
/// where it lives instead.
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
    // amount first, then name.
    expect(find.text('Taco kit build'), findsOneWidget);
    expect(find.text('Makes 12 per batch — “12 kits”'), findsOneWidget);
    expect(find.text('24 · Tortillas'), findsOneWidget);
    expect(find.text('v2 method'), findsOneWidget);
    // Source badge: seeded via the form path; picker + 2 history entries.
    expect(find.text('Entered by hand'), findsNWidgets(3));
    // Immutable history, newest first.
    expect(find.text('Revision 2'), findsOneWidget);
    expect(find.text('Revision 1'), findsOneWidget);

    // Select revision 1 from the history — rendered verbatim.
    await tapVisible(tester, find.text('Revision 1'));
    expect(find.text('Makes 10 per batch — “10 kits”'), findsOneWidget);
    expect(find.text('20 · Tortillas'), findsOneWidget);
    expect(find.textContaining('Viewing revision 1'), findsOneWidget);

    // Back to current.
    await tapVisible(tester, find.text('View current'));
    expect(find.text('24 · Tortillas'), findsOneWidget);
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

    // A labeled word in the app bar, not an icon-only glyph (spec §2).
    expect(find.text('Archive'), findsOneWidget);
    await tester.tap(find.byKey(const Key('archive-action')));
    await tester.pumpAndSettle();
    // Drift publishes query-stream updates on a zero-duration timer that
    // pumpAndSettle does not wait for.
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    expect(find.textContaining('This recipe is archived'), findsOneWidget);
    final archived = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(archived.recipe.isArchived, isTrue);

    // The same slot flips to the unarchive word (still two labeled
    // buttons: this one, and the banner's own "Unarchive" action).
    await tester.tap(find.byKey(const Key('archive-action')));
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    expect(find.textContaining('This recipe is archived'), findsNothing);
    final unarchived = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(unarchived.recipe.isArchived, isFalse);
  });
}
