/// "Paste ingredients" end-to-end widget test (proposal §3, reworked for the
/// v5 recipe decoupling): a seven-line paste resolves to 4 matches (LINKED
/// lines), 2 unmatched kept as FREE lines, and 1 ambiguous kept as a FREE
/// line; measure words ride along as display-only unit labels ("3 bags
/// onions" → 3 "bags"; "500g flour" → 500 "g" — never converted); NOTHING
/// is ever written to the item catalog — paste fills recipe lines only, and
/// matching is optional linking. The pre-v5 behaviour (confirm
/// force-created catalog items into a batch folder) is deliberately gone:
/// items are created later, only via "Add to my items".
///
/// Deliberately superseded pin: linked lines used to store the ITEM's name
/// (the form discarded the pasted text on link); now every line keeps its
/// OWN pasted text, linked or not, so unlinking later loses nothing.
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
    'seven pasted lines: 4 link, units parsed as display labels, free '
    'lines kept — and the catalog is never written',
    (tester) async {
      final h = (await tester.runAsync(
        () => AppHarness.start(state: AppHarnessState.workspace),
      ))!;
      addTearDown(h.dispose);
      late String carrots, onions, kidneyBeans, choppedTomatoes;
      await tester.runAsync(() async {
        carrots = await seedItem(h, 'Carrots');
        onions = await seedItem(h, 'Onions');
        kidneyBeans = await seedItem(h, 'Kidney beans');
        choppedTomatoes = await seedItem(h, 'Chopped tomatoes');
        await seedItem(h, 'Tomato puree');
      });

      await h.pumpApp(tester);
      await h.go(tester, '/recipes/new');

      await tester.enterText(
        find.byKey(const Key('recipe-name')),
        'Chilli batch',
      );
      await tester.enterText(find.byKey(const Key('recipe-yield')), '10');

      // Open the paste sheet and paste seven lines (one of them, "tomato",
      // contains-matches two items; "rolls" and "flour" match nothing).
      await tapVisible(tester, find.byKey(const Key('paste-ingredients')));
      await tester.enterText(
        find.byKey(const Key('paste-input')),
        '2x carrots\n'
        '3 bags onions\n'
        'Kidney beans\n'
        'chopped tomatoes\n'
        'rolls\n'
        'tomato\n'
        '500g flour',
      );
      await tapVisible(tester, find.byKey(const Key('paste-review')));

      // The review says what each line became: matches with their parsed
      // per-batch amounts AND unit labels, the free-line offers, the
      // ambiguity kept free.
      expect(find.text('→ Carrots · 2 per batch'), findsOneWidget);
      expect(find.text('→ Onions · 3 bags per batch'), findsOneWidget);
      expect(find.text('→ Kidney beans · amount left for you'), findsOneWidget);
      expect(
        find.text('→ Chopped tomatoes · amount left for you'),
        findsOneWidget,
      );
      expect(find.text('Add «rolls»'), findsOneWidget);
      expect(find.text('Add «flour»'), findsOneWidget);
      expect(find.textContaining('500 g per batch'), findsOneWidget);
      expect(
        find.textContaining('added as its own line; link it later'),
        findsOneWidget,
      );
      expect(find.text('Add 7 ingredients'), findsOneWidget);

      // There is no folder picker any more — nothing is created, so there
      // is nothing to file.
      expect(find.byKey(const Key('paste-folder-picker')), findsNothing);

      await tapVisible(tester, find.byKey(const Key('paste-confirm')));
      await h.flushTimers(tester);

      // Confirm created NOTHING: the catalog is exactly the five seeds.
      final afterConfirm = (await tester.runAsync(
        () =>
            h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
      ))!;
      expect(afterConfirm, hasLength(5));
      expect([
        for (final summary in afterConfirm) summary.item.name,
      ], isNot(contains('rolls')));

      // Seven rows landed on the form (uids 1..7; the pristine starter row
      // was replaced): every row keeps its own pasted text, matched rows
      // arrive linked, units land in the unit fields.
      expect(find.text('Linked to “Carrots”'), findsOneWidget);
      expect(find.text('Linked to “Onions”'), findsOneWidget);
      expect(find.text('rolls'), findsOneWidget);
      expect(find.text('tomato'), findsOneWidget);
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

      // The saved revision carries all seven lines, paste order kept,
      // parsed amounts and unit labels intact, links only where the
      // catalog matched — and every line's OWN pasted text.
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
      final lines = detail.revisions.first.lines;
      expect(lines, hasLength(7));
      expect(
        [for (final line in lines) line.ingredientItemId?.value],
        [carrots, onions, kidneyBeans, choppedTomatoes, null, null, null],
      );
      expect(
        [for (final line in lines) line.name],
        [
          'carrots', // linked, but the pasted text stays the line's own name
          'onions',
          'Kidney beans',
          'chopped tomatoes',
          'rolls',
          'tomato',
          'flour',
        ],
      );
      expect(
        [for (final line in lines) line.unitLabel],
        [null, 'bags', null, null, null, null, 'g'],
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
          Quantity.whole(500), // "500g flour"
        ],
      );

      // And still: the catalog was never touched by the save either.
      final afterSave = (await tester.runAsync(
        () =>
            h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
      ))!;
      expect(afterSave, hasLength(5));
    },
  );

  testWidgets('cancelling the paste sheet hands back nothing', (tester) async {
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
    expect(find.text('Add «rolls»'), findsOneWidget);
    expect(find.text('Add «sourdough»'), findsOneWidget);

    // Back out instead of confirming.
    await tapVisible(tester, find.text('Back'));
    await tapVisible(tester, find.text('Cancel'));
    await h.flushTimers(tester);

    final summaries = (await tester.runAsync(
      () => h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
    ))!;
    expect([for (final summary in summaries) summary.item.name], ['Chilli']);
    // No rows were appended to the form either: the starter row is alone.
    expect(find.byKey(const ValueKey('ingredient-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ingredient-row-1')), findsNothing);
  });
}
