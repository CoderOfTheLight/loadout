/// Proposal §2/§3: "no recipe can claim a CD" — items in a sales-table
/// folder never appear in the recipe pickers (output OR ingredient), and
/// the paste matcher reports them as excluded instead of matching them or
/// offering to create a duplicate.
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

  testWidgets(
    'output and ingredient pickers exclude sales-table-folder items',
    (tester) async {
      final h = await startWithSalesItem(tester);

      await h.pumpApp(tester);
      await h.go(tester, '/recipes/new');

      // Open the output picker: the kitchen items are offered, the
      // sales-table item is not — anywhere on the screen.
      await tapVisible(tester, find.byKey(const Key('output-item-picker')));
      expect(find.text('Soup'), findsWidgets); // the menu did open
      expect(find.text('Rolls'), findsWidgets);
      expect(find.text('Album CD'), findsNothing);
      await tester.tap(find.text('Soup').last);
      await tester.pumpAndSettle();

      // Same for the ingredient picker.
      await tapVisible(tester, find.byKey(const ValueKey('ingredient-item-0')));
      expect(find.text('Album CD'), findsNothing);
      expect(find.text('Rolls'), findsWidgets);
      await tester.tap(find.text('Rolls').last);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'paste matching reports a sales-table item as excluded, never created',
    (tester) async {
      final h = await startWithSalesItem(tester);

      await h.pumpApp(tester);
      await h.go(tester, '/recipes/new');

      await tapVisible(tester, find.byKey(const Key('paste-ingredients')));
      await tester.enterText(find.byKey(const Key('paste-input')), 'album cd');
      await tapVisible(tester, find.byKey(const Key('paste-review')));

      // Not matched, and NOT offered as "Create «album cd»" — that would
      // just duplicate the sales-table item under a new id.
      expect(find.textContaining('is on the sales table'), findsOneWidget);
      expect(find.textContaining('Create «'), findsNothing);

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
