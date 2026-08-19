/// Proposal §2/§3: "no recipe can claim a CD" — items in a sales-table
/// folder are never offered as link targets on the v5 free-text ingredient
/// rows, and the paste matcher reports them as excluded instead of matching
/// them or offering to create a duplicate.
///
/// Deliberately superseded pin: the output/ingredient PICKERS this file
/// used to walk are gone with the v5 decoupling (free-text rows, no output
/// picker on creation) — the sales-table rule now guards the link
/// affordance instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

void main() {
  Future<AppHarness> startWithSalesItem(WidgetTester tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final folders = await h.read(catalogServiceProvider).watchFolders().first;
      final salesId = folders
          .firstWhere((folder) => folder.name == 'Sales table')
          .id
          .value;
      unwrap(
        await h
            .read(catalogServiceProvider)
            .createItem(ItemDraft(name: 'Album CD', folderId: salesId)),
      );
      await seedItem(h, 'Soup');
      await seedItem(h, 'Rolls');
    });
    return h;
  }

  testWidgets('the link affordance is never offered for a sales-table item', (
    tester,
  ) async {
    final h = await startWithSalesItem(tester);

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/new');

    // A kitchen item's exact name offers the link…
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-name-0')),
      'Soup',
    );
    await tester.pumpAndSettle();
    expect(await ingredientMenuOffers(tester, 0, 'link-line-0'), isTrue);

    // …the sales-table item's exact name never does: the line stays free
    // text (typing it is fine — linking to a CD is not).
    await tester.enterText(
      find.byKey(const ValueKey('ingredient-name-0')),
      'Album CD',
    );
    await tester.pumpAndSettle();
    expect(await ingredientMenuOffers(tester, 0, 'link-line-0'), isFalse);
  });

  testWidgets(
    'paste matching reports a sales-table item as excluded, never created',
    (tester) async {
      final h = await startWithSalesItem(tester);

      await h.pumpApp(tester);
      await h.go(tester, '/recipes/new');

      await tapVisible(tester, find.byKey(const Key('paste-ingredients')));
      await tester.enterText(find.byKey(const Key('paste-input')), 'album cd');
      await tapVisible(tester, find.byKey(const Key('paste-review')));

      // Not matched, and NOT offered as anything that would duplicate the
      // sales-table item under a new id. The review's SECOND state: greyed,
      // with the reason in plain words.
      expect(
        find.text(
          'Skipped: this is something you sell, not something you cook with.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('paste-skipped-0')), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);

      // Nothing to add, so confirm is disabled.
      final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('paste-confirm')),
      );
      expect(confirm.onPressed, isNull);

      await tapVisible(tester, find.text('Back'));
      await tapVisible(tester, find.text('Cancel'));
      await h.flushTimers(tester);

      // The catalog is untouched.
      final summaries = (await tester.runAsync(
        () =>
            h.read(catalogServiceProvider).watchItems(const ItemFilter()).first,
      ))!;
      expect([
        for (final summary in summaries) summary.item.name,
      ], unorderedEquals(['Album CD', 'Soup', 'Rolls']));
    },
  );
}
