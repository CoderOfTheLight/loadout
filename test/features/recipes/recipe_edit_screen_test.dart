/// §9 + §11.3 RecipeEditScreen (create mode) widget tests, v5 decoupled
/// form: a recipe is created standalone from free-text ingredient rows —
/// name + amount (decimals AND fractions) + optional unit label — with NO
/// catalog dependency at all (the old empty-catalog dead end is
/// deliberately gone), an optional link affordance when a typed name
/// matches a live item, and the nesting guard still surfaced with its
/// resolved path when a LINK would nest recipes.
///
/// ONE ROW IS ONE LINE: exactly three controls (name, amount, unit) and a
/// row overflow holding link / unlink / remove. Deliberately superseded
/// pins: the output-item picker is gone from creation (a recipe binds to an
/// item only via "Add to my items" later); the per-row drag handle is now a
/// long press; the unit suggestion chips, the "Linked to X" caption and the
/// inline "Unlink" button are gone; and the "revisions are permanent"
/// banner moved off the form into the save confirmation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/recipes/domain/recipe.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  testWidgets('creates a recipe with ZERO catalog items: free lines, fraction '
      'amounts, unit chips — no dead end, no items created', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    // NO seeding on purpose: the catalog is empty and stays empty.

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    // The pre-v5 empty-catalog dead end is GONE — the form is usable.
    expect(find.text('Add an item first'), findsNothing);
    expect(find.byKey(const Key('output-item-picker')), findsNothing);
    expect(find.byKey(const ValueKey('ingredient-name-0')), findsOneWidget);

    // THREE controls on the row, and nothing else: name, amount, unit. No
    // drag handle (long-press reorders), no inline unlink, no chip strip.
    final row = find.byKey(const ValueKey('ingredient-row-0'));
    expect(
      find.descendant(of: row, matching: find.byType(TextField)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.drag_indicator)),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.byType(ActionChip)),
      findsNothing,
    );
    expect(find.text('Unlink'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('recipe-name')),
      'Sourdough loaves',
    );
    await tester.enterText(find.byKey(const Key('recipe-yield')), '6');
    // Owner feedback: the field is plain 'Yield', and the old "what a
    // batch is called" field is gone entirely.
    expect(find.text('Yield'), findsOneWidget);
    expect(find.text('How many one batch makes'), findsNothing);
    expect(find.text('What a batch is called (optional)'), findsNothing);
    expect(find.byKey(const Key('recipe-yield-label')), findsNothing);

    // Row 0: fraction amount, unit from the shared suggestion chips.
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-name-0')),
      'Flour',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-qty-0')),
      '1 1/2',
    );
    // A plain unit box with a hint — the chip strip that used to appear
    // under the focused row is gone.
    await tapVisible(tester, find.byKey(const ValueKey('ingredient-unit-0')));
    expect(find.byKey(const ValueKey('unit-suggestions-0')), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-unit-0')),
      'cup',
    );

    // Row 1: typed unit label.
    await tapVisible(tester, find.byKey(const Key('add-ingredient')));
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-name-1')),
      'Salt',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-qty-1')),
      '0.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-unit-1')),
      'tsp',
    );

    await tapVisible(tester, find.byKey(const Key('save-recipe')));
    // Leaving the route auto-disposes providers; drift closes its query
    // streams on a zero-duration timer that pumpAndSettle never runs.
    await h.flushTimers(tester);
    await tester.pumpAndSettle();

    // Popped back to the list showing the new live recipe.
    expect(find.text('Sourdough loaves'), findsOneWidget);
    expect(find.text('rev 1'), findsOneWidget);

    final detail = (await tester.runAsync(() async {
      final summaries = await h
          .read(recipeServiceProvider)
          .watchRecipes()
          .first;
      expect(summaries, hasLength(1));
      return h
          .read(recipeServiceProvider)
          .watchRecipe(summaries.first.id)
          .first;
    }))!;
    // Standalone: no output item until "Add to my items".
    expect(detail.recipe.outputItemId, isNull);
    expect(detail.recipe.isInItems, isFalse);
    final revision = detail.revisions.single;
    expect(revision.revision, 1);
    expect(revision.yieldQuantity, Quantity.whole(6));
    expect(revision.yieldLabel, isNull); // the form no longer captures one
    expect(revision.sourceKind, RecipeSourceKind.form);
    expect(revision.lines, hasLength(2));
    final (flour, salt) = (revision.lines[0], revision.lines[1]);
    expect(flour.name, 'Flour');
    expect(flour.unitLabel, 'cup');
    expect(flour.quantityPerBatch.micros, 1500000); // "1 1/2", exact
    expect(flour.ingredientItemId, isNull);
    expect(salt.name, 'Salt');
    expect(salt.unitLabel, 'tsp');
    expect(salt.quantityPerBatch.micros, 500000);
    expect(salt.ingredientItemId, isNull);

    // The catalog was never touched: still zero items.
    final items = (await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    ))!;
    expect(items, isEmpty);
  });

  testWidgets(
    'link affordance: appears on a live-item name match, links, unlinks, '
    'and never offers an item already linked on another row',
    (tester) async {
      final h = (await tester.runAsync(
        () => AppHarness.start(state: AppHarnessState.workspace),
      ))!;
      addTearDown(h.dispose);
      late String tortillas;
      await tester.runAsync(() async {
        tortillas = await seedItem(h, 'Tortillas');
      });

      await h.pumpApp(tester);
      await h.go(tester, '/recipes/new');

      await tester.enterText(
        find.byKey(const Key('recipe-name')),
        'Taco build',
      );
      await tester.enterText(find.byKey(const Key('recipe-yield')), '10');

      // No affordance while the name matches nothing.
      await tester.enterText(
        find.byKey(const ValueKey('ingredient-name-0')),
        'Torti',
      );
      await tester.pumpAndSettle();
      expect(await ingredientMenuOffers(tester, 0, 'link-line-0'), isFalse);

      // Case-insensitive exact match → the overflow names its target. The
      // row itself stays three fields wide; the verb lives one tap down.
      await tester.enterText(
        find.byKey(const ValueKey('ingredient-name-0')),
        'tortillas',
      );
      await tester.pumpAndSettle();
      await openIngredientMenu(tester, 0);
      expect(find.text('Link to your item “Tortillas”'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('link-line-0')));
      await tester.pumpAndSettle();

      // Linked: a mark on the row, never a caption sentence, and the unlink
      // verb in the overflow rather than a button competing for width.
      expect(find.text('Linked to “Tortillas”'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ingredient-row-0')),
          matching: find.byIcon(Icons.link),
        ),
        findsOneWidget,
      );
      await tapIngredientMenuItem(tester, 0, 'unlink-line-0');
      expect(await ingredientMenuOffers(tester, 0, 'unlink-line-0'), isFalse);
      await tapIngredientMenuItem(tester, 0, 'link-line-0');

      // A second row typing the same name gets NO affordance — the item is
      // already linked on the first row (no duplicate links by design).
      await tapVisible(tester, find.byKey(const Key('add-ingredient')));
      await tester.enterText(
        find.byKey(const ValueKey('ingredient-name-1')),
        'Tortillas',
      );
      await tester.pumpAndSettle();
      expect(await ingredientMenuOffers(tester, 1, 'link-line-1'), isFalse);
      await tapIngredientMenuItem(tester, 1, 'remove-ingredient-1');

      await tester.enterText(
        find.byKey(const ValueKey('ingredient-qty-0')),
        '20',
      );
      await tapVisible(tester, find.byKey(const Key('save-recipe')));
      await h.flushTimers(tester);
      await tester.pumpAndSettle();
      expect(find.text('Taco build'), findsOneWidget);

      final detail = (await tester.runAsync(() async {
        final summaries = await h
            .read(recipeServiceProvider)
            .watchRecipes()
            .first;
        return h
            .read(recipeServiceProvider)
            .watchRecipe(summaries.single.id)
            .first;
      }))!;
      final line = detail.revisions.single.lines.single;
      expect(line.ingredientItemId?.value, tortillas);
      // The line keeps its OWN typed text — unlinking later loses nothing.
      expect(line.name, 'tortillas');
      expect(line.quantityPerBatch, Quantity.whole(20));
    },
  );

  testWidgets('linking a line to a live recipe\'s output is rejected with the '
      'RecipeNestingError path shown', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final salsa = await seedItem(h, 'Salsa');
      final tomato = await seedItem(h, 'Tomato');
      await seedRecipe(
        h,
        name: 'Salsa base',
        outputItemId: salsa,
        lines: {tomato: 3},
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    await tester.enterText(find.byKey(const Key('recipe-name')), 'Kit build');
    await tester.enterText(find.byKey(const Key('recipe-yield')), '1');
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-name-0')),
      'Salsa',
    );
    await tester.pumpAndSettle();
    await tapIngredientMenuItem(tester, 0, 'link-line-0');
    await tester.enterText(find.byKey(const ValueKey('ingredient-qty-0')), '2');
    await tapVisible(tester, find.byKey(const Key('save-recipe')));

    // The RecipeNestingError message and its resolved path are shown — the
    // path joined with a WORD, because the arrow glyph it used to use is a
    // tofu box in the app's font.
    expect(
      find.textContaining('ingredient is the output of a live recipe'),
      findsOneWidget,
    );
    expect(
      find.textContaining("Salsa then recipe 'Salsa base'"),
      findsOneWidget,
    );
    final summaries = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipes().first,
    ))!;
    expect(summaries, hasLength(1)); // only the seeded recipe
  });

  testWidgets('an empty ingredient name is rejected inline', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    await tester.enterText(find.byKey(const Key('recipe-name')), 'Bare');
    await tester.enterText(find.byKey(const Key('recipe-yield')), '2');
    await tester.enterText(find.byKey(const ValueKey('ingredient-qty-0')), '1');
    await tapVisible(tester, find.byKey(const Key('save-recipe')));

    expect(find.text('Enter an ingredient name'), findsOneWidget);
    final summaries = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipes().first,
    ))!;
    expect(summaries, isEmpty);
  });

  testWidgets('the form renders at 200 % text scale on a 320 dp viewport: the '
      'row folds instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final tortillas = await seedItem(h, 'Tortillas');
      recipeId = await seedRecipe(
        h,
        name: 'Taco kit build',
        outputItemId: await seedItem(h, 'Taco kit'),
        lines: {tortillas: 20},
      );
    });

    // An overflow at 200 % scale would throw and fail the test here.
    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');
    expect(find.byKey(const ValueKey('ingredient-row-0')), findsOneWidget);
    // Still exactly three controls — the row stacks, it does not shed a
    // field or squeeze one to nothing.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ingredient-row-0')),
        matching: find.byType(TextField),
      ),
      findsNWidgets(3),
    );

    // Revise mode too: prefilled rows, the pinned save bar, and the save
    // confirmation all at 200 %.
    await h.go(tester, '/recipes/$recipeId/revise');
    expect(find.byKey(const ValueKey('ingredient-row-0')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('save-recipe')));
    expect(find.text('Save revision 2?'), findsOneWidget);
    await tapVisible(tester, find.text('Keep editing'));
    await h.flushTimers(tester);
  });
}
