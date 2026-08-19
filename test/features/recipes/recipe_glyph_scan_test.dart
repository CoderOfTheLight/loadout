/// BUILD 0 — no tofu on the recipe screens.
///
/// The app's bundled font has no glyph for `→` (U+2192) or `✓` (U+2713):
/// both render as an empty box, so "Needs about 0.3 batches ▯ make 1" is
/// what a real owner saw. This test walks every rendered [Text] on the
/// screens this feature owns and fails on any character outside ASCII
/// except the small set the design uses on purpose ([_deliberate]).
///
/// It scans [Text] only — never [RichText] — because [Icon] paints a
/// private-use codepoint through a RichText, and a Material icon is not a
/// glyph anybody reads as text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/unit_ratio.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

/// The only non-ASCII characters allowed to reach a user's eyes: the
/// separator dot, the dashes (including the true minus), the typographic
/// quotes, the ellipsis, and the multiplication sign. Every one of them is
/// in the bundled font; every one of them is a deliberate typographic
/// choice rather than a symbol carrying meaning.
const Set<int> _deliberate = {
  0x00B7, // ·  middle dot
  0x00D7, // ×  multiplication sign
  0x2013, // –  en dash
  0x2014, // —  em dash
  0x2018, // '  left single quote
  0x2019, // '  right single quote
  0x201C, // "  left double quote
  0x201D, // "  right double quote
  0x2026, // …  ellipsis
  0x2212, // −  true minus
};

/// Fails with every offending codepoint and the string it came from.
void expectNoTofuGlyphs(WidgetTester tester, String where) {
  final offenders = <String>{};
  for (final widget in tester.allWidgets) {
    if (widget is! Text) continue;
    final strings = <String>[?widget.data, ?widget.textSpan?.toPlainText()];
    for (final text in strings) {
      for (final rune in text.runes) {
        if (rune < 0x80 || _deliberate.contains(rune)) continue;
        final hex = rune.toRadixString(16).toUpperCase().padLeft(4, '0');
        offenders.add('U+$hex "${String.fromCharCode(rune)}" in "$text"');
      }
    }
  }
  expect(
    offenders,
    isEmpty,
    reason:
        'These render as empty boxes in the bundled font. Say it in words '
        'instead. Found on $where: $offenders',
  );
}

void main() {
  testWidgets('no tofu glyph on the recipe list, form, paste review or '
      'save confirmation', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final onions = await seedItem(h, 'Onions');
      final salsa = await seedItem(h, 'Salsa');
      recipeId = await seedRecipe(
        h,
        name: 'Salsa base',
        outputItemId: salsa,
        lines: {onions: 3},
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/recipes');
    expectNoTofuGlyphs(tester, 'the recipe list');

    await h.go(tester, '/recipes/new');
    expectNoTofuGlyphs(tester, '/recipes/new');

    // The paste review, both of its states: a kept line and a line the
    // parser matched to an existing item.
    await tapVisible(tester, find.byKey(const Key('paste-ingredients')));
    await tester.enterText(
      find.byKey(const Key('paste-input')),
      '3 bags onions\nrolls',
    );
    await tapVisible(tester, find.byKey(const Key('paste-review')));
    expectNoTofuGlyphs(tester, 'the paste review');
    await tapVisible(tester, find.byKey(const Key('paste-confirm')));
    await h.flushTimers(tester);

    // An ingredient row's overflow, where the link verbs live.
    await openIngredientMenu(tester, 1);
    expectNoTofuGlyphs(tester, "an ingredient row's overflow");
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();

    // The nesting guard's error path — it used to be joined with an arrow.
    await tester.enterText(find.byKey(const Key('recipe-name')), 'Kit build');
    await tester.enterText(find.byKey(const Key('recipe-yield')), '1');
    // Row 1 is the matched "3 bags onions"; row 2 is the free "rolls".
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-name-2')),
      'Salsa',
    );
    await tester.pumpAndSettle();
    await tapIngredientMenuItem(tester, 2, 'link-line-2');
    await tester.enterText(find.byKey(const ValueKey('ingredient-qty-2')), '1');
    await tapVisible(tester, find.byKey(const Key('save-recipe')));
    expect(
      find.textContaining('ingredient is the output of a live recipe'),
      findsOneWidget,
    );
    expectNoTofuGlyphs(tester, 'the nesting-guard banner');

    // The revise form and its save confirmation.
    await h.go(tester, '/recipes/$recipeId/revise');
    expectNoTofuGlyphs(tester, 'the revise form');
    await tapVisible(tester, find.byKey(const Key('save-recipe')));
    expectNoTofuGlyphs(tester, 'the save confirmation');
    await tapVisible(tester, find.text('Keep editing'));
    await h.flushTimers(tester);
  });

  testWidgets('no tofu glyph on the recipe detail screen, its menu, its '
      'earlier-versions sheet or the scale sheet', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String recipeId;
    await tester.runAsync(() async {
      final chilli = unwrap(
        await h
            .read(catalogServiceProvider)
            .createItem(
              ItemDraft(
                name: 'Chilli',
                perPersonRatio: UnitRatio(1, 10),
                unitPrice: null,
              ),
            ),
      );
      final beans = await seedItem(h, 'Beans');
      recipeId = unwrap(
        await h
            .read(recipeServiceProvider)
            .createRecipe(
              RecipeFormDraft(
                name: 'Chilli batch',
                outputItemId: chilli,
                yieldQuantity: Quantity.whole(10),
                yieldLabel: '10 portions',
                note: 'Simmer for an hour.',
                lines: [
                  RecipeFormLine(
                    itemId: beans,
                    quantityPerBatch: Quantity.whole(3),
                  ),
                  const RecipeFormLine(
                    name: 'Secret spice',
                    unitLabel: 'tsp',
                    quantityPerBatch: Quantity.one,
                  ),
                ],
              ),
            ),
      );
      unwrap(
        await h
            .read(recipeServiceProvider)
            .reviseRecipe(
              recipeId: recipeId,
              draft: RecipeFormDraft(
                name: 'Chilli batch',
                outputItemId: chilli,
                yieldQuantity: Quantity.whole(10),
                yieldLabel: '10 portions',
                lines: [
                  RecipeFormLine(
                    itemId: beans,
                    quantityPerBatch: Quantity.whole(4),
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
    expectNoTofuGlyphs(tester, 'the recipe detail screen');

    await tapVisible(tester, find.byKey(const Key('recipe-menu')));
    expectNoTofuGlyphs(tester, "the detail screen's More menu");
    await tester.tap(find.byKey(const Key('earlier-versions')));
    await tester.pumpAndSettle();
    expectNoTofuGlyphs(tester, 'the earlier-versions sheet');
    await tapVisible(tester, find.byKey(const ValueKey('version-1')));
    expectNoTofuGlyphs(tester, 'an earlier version being read');
    await tapVisible(tester, find.text('Back to current'));

    await tapVisible(tester, find.byKey(const Key('scale-to-event')));
    expect(find.byKey(const Key('scale-verdict')), findsOneWidget);
    expectNoTofuGlyphs(tester, 'the scale sheet');
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });
}
