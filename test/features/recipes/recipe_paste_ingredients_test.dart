/// "Paste ingredients" end-to-end widget test (proposal §3): a six-line
/// paste resolves to 4 matches, 1 create, and 1 ambiguous line left for
/// manual fixing; NOTHING is written until the review is confirmed; the
/// created item lands in the folder picked once for the batch; and the
/// saved recipe carries all six lines with the parsed per-batch amounts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  testWidgets(
    'six pasted lines: 4 match, 1 create, 1 ambiguous left for manual fix',
    (tester) async {
      final h = (await tester.runAsync(
        () => AppHarness.start(state: AppHarnessState.workspace),
      ))!;
      addTearDown(h.dispose);
      late String chilli, carrots, onions, kidneyBeans, choppedTomatoes;
      late String tomatoPuree, produceFolderId;
      await tester.runAsync(() async {
        chilli = await seedItem(h, 'Chilli');
        carrots = await seedItem(h, 'Carrots');
        onions = await seedItem(h, 'Onions');
        kidneyBeans = await seedItem(h, 'Kidney beans');
        choppedTomatoes = await seedItem(h, 'Chopped tomatoes');
        tomatoPuree = await seedItem(h, 'Tomato puree');
        // Fresh workspaces seed the eight starter folders; the batch of
        // created items goes into one picked once on the review sheet.
        final folders = await h
            .read(catalogServiceProvider)
            .watchFolders()
            .first;
        produceFolderId = folders
            .firstWhere((folder) => folder.name == 'Fresh produce')
            .id
            .value;
      });

      await h.pumpApp(tester);
      await h.go(tester, '/recipes/new');

      await pickFromDropdown(
        tester,
        find.byKey(const Key('output-item-picker')),
        'Chilli',
      );
      await tester.enterText(
        find.byKey(const Key('recipe-name')),
        'Chilli batch',
      );
      await tester.enterText(find.byKey(const Key('recipe-yield')), '10');

      // Open the paste sheet and paste six lines (one of them, "tomato",
      // contains-matches two items; "rolls" matches nothing).
      await tapVisible(tester, find.byKey(const Key('paste-ingredients')));
      await tester.enterText(
        find.byKey(const Key('paste-input')),
        '2x carrots\n'
        '3 bags onions\n'
        'Kidney beans\n'
        'chopped tomatoes\n'
        'rolls\n'
        'tomato',
      );
      await tapVisible(tester, find.byKey(const Key('paste-review')));

      // The review says what each line became: matches with their parsed
      // per-batch amounts, the create offer, the ambiguity left unresolved.
      expect(find.text('→ Carrots · 2 per batch'), findsOneWidget);
      expect(find.text('→ Onions · 3 per batch'), findsOneWidget);
      expect(find.text('→ Kidney beans · amount left for you'), findsOneWidget);
      expect(
        find.text('→ Chopped tomatoes · amount left for you'),
        findsOneWidget,
      );
      expect(find.text('Create «rolls»'), findsOneWidget);
      expect(
        find.textContaining('added blank; pick on the form'),
        findsOneWidget,
      );
      expect(find.text('Add 6 ingredients'), findsOneWidget);

      // NOTHING saves until the review is confirmed: no "rolls" item yet.
      final namesBefore = (await tester.runAsync(
        () =>
            h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
      ))!;
      expect([
        for (final summary in namesBefore) summary.item.name,
      ], isNot(contains('rolls')));

      // Pick the batch folder once, then confirm.
      await pickFromDropdown(
        tester,
        find.byKey(const Key('paste-folder-picker')),
        'Fresh produce',
      );
      await tapVisible(tester, find.byKey(const Key('paste-confirm')));
      await h.flushTimers(tester);

      // The confirmed create went through CatalogService into that folder.
      final rolls = (await tester.runAsync(() async {
        final summaries = await h
            .read(catalogServiceProvider)
            .watchItems(const ItemFilter())
            .first;
        return summaries
            .firstWhere((summary) => summary.item.name == 'rolls')
            .item;
      }))!;
      expect(rolls.folderId?.value, produceFolderId);

      // Six rows landed on the form (uids 1..6; the pristine starter row
      // was replaced). Fix the ambiguous line by hand and fill the blanks.
      await pickFromDropdown(
        tester,
        find.byKey(const ValueKey('ingredient-item-6')),
        'Tomato puree',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ingredient-qty-3')),
        '5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ingredient-qty-4')),
        '4',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ingredient-qty-5')),
        '30',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ingredient-qty-6')),
        '1',
      );
      await tapVisible(tester, find.byKey(const Key('save-recipe')));

      // The saved revision carries all six lines, paste order kept, parsed
      // amounts intact.
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
      expect(detail.recipe.outputItemId.value, chilli);
      final lines = detail.revisions.first.lines;
      expect(lines, hasLength(6));
      expect(
        [for (final line in lines) line.ingredientItemId.value],
        [
          carrots,
          onions,
          kidneyBeans,
          choppedTomatoes,
          rolls.id.value,
          tomatoPuree,
        ],
      );
      expect(
        [for (final line in lines) line.quantityPerBatch],
        [
          Quantity.whole(2), // "2x carrots"
          Quantity.whole(3), // "3 bags onions"
          Quantity.whole(5), // typed by hand
          Quantity.whole(4), // typed by hand
          Quantity.whole(30), // typed by hand
          Quantity.whole(1), // typed by hand
        ],
      );
    },
  );

  testWidgets('cancelling the paste sheet writes nothing', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      await seedItem(h, 'Chilli');
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    await tapVisible(tester, find.byKey(const Key('paste-ingredients')));
    await tester.enterText(
      find.byKey(const Key('paste-input')),
      'rolls\nsourdough',
    );
    await tapVisible(tester, find.byKey(const Key('paste-review')));
    expect(find.text('Create «rolls»'), findsOneWidget);
    expect(find.text('Create «sourdough»'), findsOneWidget);

    // Back out instead of confirming.
    await tapVisible(tester, find.text('Back'));
    await tapVisible(tester, find.text('Cancel'));
    await h.flushTimers(tester);

    final summaries = (await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    ))!;
    expect([for (final summary in summaries) summary.item.name], ['Chilli']);
  });
}
