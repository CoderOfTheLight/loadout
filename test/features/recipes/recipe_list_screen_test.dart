/// §9 `/recipes` — RecipeListScreen widget tests: empty state, live-recipe
/// tiles (output item, yield caption, ingredient count, "rev N"), and the
/// archived filter.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/recipes/presentation/recipe_list_screen.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  testWidgets('empty list shows the §9 empty state', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const RecipeListScreen());

    expect(
      find.text(
        'Recipes let Loadout plan production later. '
        'Enter one by hand — takes a minute.',
      ),
      findsOneWidget,
    );
    expect(find.text('New recipe'), findsWidgets); // empty action + FAB
  });

  testWidgets('live recipe tile shows output, yield caption, lines, rev N', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final kit = await seedItem(h, 'Taco kit');
      final tortillas = await seedItem(h, 'Tortillas');
      final cheese = await seedItem(h, 'Cheese');
      await seedRecipe(
        h,
        name: 'Taco kit build',
        outputItemId: kit,
        yieldWhole: 10,
        yieldLabel: '10 kits',
        lines: {tortillas: 20, cheese: 2},
      );
    });

    await h.pumpScreen(tester, const RecipeListScreen());

    expect(find.text('Taco kit build'), findsOneWidget);
    expect(
      find.text('Taco kit · Makes 10 (10 kits) · 2 ingredients'),
      findsOneWidget,
    );
    expect(find.text('rev 1'), findsOneWidget);
  });

  testWidgets('archived recipes hide behind the archived filter', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final salsa = await seedItem(h, 'Salsa');
      final tomato = await seedItem(h, 'Tomato');
      final kit = await seedItem(h, 'Taco kit');
      await seedRecipe(
        h,
        name: 'Live build',
        outputItemId: kit,
        lines: {tomato: 1},
      );
      final archivedId = await seedRecipe(
        h,
        name: 'Old salsa',
        outputItemId: salsa,
        lines: {tomato: 3},
      );
      unwrap(
        await h
            .read(recipeServiceProvider)
            .setArchived(recipeId: archivedId, archived: true),
      );
    });

    await h.pumpScreen(tester, const RecipeListScreen());

    // Live only by default.
    expect(find.text('Live build'), findsOneWidget);
    expect(find.text('Old salsa'), findsNothing);
    expect(find.text('Show archived (1)'), findsOneWidget);

    await tester.tap(find.text('Show archived (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Old salsa'), findsOneWidget);
    expect(find.textContaining('Archived · Salsa'), findsOneWidget);

    await tester.tap(find.text('Show archived (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Old salsa'), findsNothing);
  });
}
