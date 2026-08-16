/// §9 + §11.3 RecipeEditScreen (revise mode) widget tests: the form
/// prefills from the latest revision and APPENDS immutable revision N+1 —
/// revision N stays byte-identical.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  testWidgets('revise prefills from latest and appends revision 2', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final recipeId = (await tester.runAsync(() async {
      final kit = await seedItem(h, 'Taco kit');
      final tortillas = await seedItem(h, 'Tortillas');
      return seedRecipe(
        h,
        name: 'Taco kit build',
        outputItemId: kit,
        yieldWhole: 10,
        yieldLabel: '10 kits',
        note: 'v1 method',
        lines: {tortillas: 20},
      );
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId/revise');

    // Prefilled from revision 1; the name stays editable (a rename rides
    // the revise); append is explicit. The old read-only output-item box
    // and the yield-label field are gone.
    expect(find.text('Revise recipe'), findsOneWidget);
    expect(find.text('Taco kit build'), findsOneWidget);
    expect(find.text('Output item'), findsNothing);
    expect(find.text('Taco kit'), findsNothing);
    expect(find.text('10'), findsOneWidget); // yield
    expect(find.byKey(const Key('recipe-yield-label')), findsNothing);
    expect(find.text('10 kits'), findsNothing);
    expect(find.text('v1 method'), findsOneWidget);
    expect(find.text('Save as revision 2'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('recipe-name')))
          .enabled,
      isTrue,
    );

    // Change the yield and the line quantity, then append.
    await tester.enterText(find.byKey(const Key('recipe-yield')), '12');
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-qty-0')),
      '24',
    );
    await tapVisible(tester, find.byKey(const Key('save-recipe')));
    await h.flushTimers(tester);
    await tester.pumpAndSettle();

    // Saving returns to the recipe, now viewing revision 2.
    expect(find.textContaining('Revision 2'), findsWidgets);

    final detail = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(detail.revisions, hasLength(2));
    final (rev2, rev1) = (detail.revisions[0], detail.revisions[1]);
    expect(rev2.revision, 2);
    expect(rev2.yieldQuantity, Quantity.whole(12));
    expect(rev2.yieldLabel, isNull); // the form no longer captures one
    expect(rev2.lines.single.quantityPerBatch, Quantity.whole(24));
    // Revision 1 is immutable — still exactly as created.
    expect(rev1.revision, 1);
    expect(rev1.yieldQuantity, Quantity.whole(10));
    expect(rev1.yieldLabel, '10 kits');
    expect(rev1.note, 'v1 method');
    expect(rev1.lines.single.quantityPerBatch, Quantity.whole(20));
  });

  testWidgets('a rename-only revise renames the recipe AND its output item '
      '(one name)', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String kit;
    final recipeId = (await tester.runAsync(() async {
      kit = await seedItem(h, 'Taco kit');
      final tortillas = await seedItem(h, 'Tortillas');
      return seedRecipe(
        h,
        name: 'Taco kit build',
        outputItemId: kit,
        lines: {tortillas: 20},
      );
    }))!;

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/$recipeId/revise');

    await tester.enterText(
      find.byKey(const Key('recipe-name')),
      'Burrito kit build',
    );
    // Drop focus first: a focused top-of-form field scrolls itself back into
    // view on the settle inside tapVisible, pushing Save below the fold.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('save-recipe')));
    await h.flushTimers(tester);
    await tester.pumpAndSettle();

    final detail = (await tester.runAsync(
      () => h.read(recipeServiceProvider).watchRecipe(recipeId).first,
    ))!;
    expect(detail.recipe.name, 'Burrito kit build');
    expect(
      detail.revisions,
      hasLength(2),
      reason: 'the rename rode an appended revision',
    );
    final item = (await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItem(kit).first,
    ))!;
    expect(
      item.item.name,
      'Burrito kit build',
      reason: 'the recipe and its output item share one name',
    );
  });
}
