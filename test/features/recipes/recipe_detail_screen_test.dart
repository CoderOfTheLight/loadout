/// §9 `/recipes/:recipeId` — RecipeDetailScreen widget tests: current
/// revision (yield, lines, source badge), immutable revision history with
/// verbatim rendering of prior revisions, archive/unarchive.
library;

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

    // Current revision (2) by default.
    expect(find.text('Taco kit build'), findsOneWidget);
    expect(find.text('Makes 12 each per batch — “12 kits”'), findsOneWidget);
    expect(find.text('Tortillas'), findsOneWidget);
    expect(find.text('24 each'), findsOneWidget);
    expect(find.text('v2 method'), findsOneWidget);
    // Source badge: seeded via the form path; picker + 2 history entries.
    expect(find.text('Entered by hand'), findsNWidgets(3));
    // Immutable history, newest first.
    expect(find.text('Revision 2'), findsOneWidget);
    expect(find.text('Revision 1'), findsOneWidget);

    // Select revision 1 from the history — rendered verbatim.
    await tapVisible(tester, find.text('Revision 1'));
    expect(find.text('Makes 10 each per batch — “10 kits”'), findsOneWidget);
    expect(find.text('20 each'), findsOneWidget);
    expect(find.textContaining('Viewing revision 1'), findsOneWidget);

    // Back to current.
    await tapVisible(tester, find.text('View current'));
    expect(find.text('24 each'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Archive recipe'));
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

    await tester.tap(find.byTooltip('Unarchive recipe'));
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
