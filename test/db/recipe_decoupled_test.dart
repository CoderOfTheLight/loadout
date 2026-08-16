/// v5 recipe decoupling, through the REAL write path (§11.1 style): recipes
/// exist without any catalog item; lines are free text with optional links
/// and display-only unit labels; AddRecipeToItems puts the recipe (and any
/// chosen free lines) on the item list in ONE transaction with an
/// idempotency guard; Link/Unlink mutate exactly the link and nothing else;
/// and `items.unit_label` rides CreateItem/UpdateItem with its clear mirror.
library;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/catalog/application/catalog_service.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import 'fixtures.dart';
import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;

  setUp(() => h = WritePathHarness());

  tearDown(() => h.close());

  RecipeRevisionDraft revision(List<RecipeLineDraft> lines) =>
      RecipeRevisionDraft(yieldQuantity: Quantity.whole(10), lines: lines);

  RecipeLineDraft free(String name, {String? unitLabel, int whole = 1}) =>
      RecipeLineDraft(
        name: name,
        unitLabel: unitLabel,
        quantityPerBatch: Quantity.whole(whole),
      );

  RecipeLineDraft linked(String itemId, {String? name, String? unitLabel}) =>
      RecipeLineDraft(
        name: name,
        unitLabel: unitLabel,
        ingredientItemId: ItemId(itemId),
        quantityPerBatch: Quantity.whole(2),
      );

  group('CreateRecipe without any catalog item', () {
    test('a recipe of free lines exists with NULL output; linked lines '
        'snapshot the item name; free lines keep their own', () async {
      final beans = await h.createItem(name: 'Beans');
      final receipt = await h.ok(
        CreateRecipe(
          name: 'Chilli batch',
          firstRevision: revision([
            linked(beans),
            free('Cumin', unitLabel: 'tsp'),
            free('Secret spice', whole: 3),
          ]),
        ),
      );
      final recipeId = receipt.createdRecordIds.first;
      final recipe = await (h.db.select(
        h.db.recipes,
      )..where((r) => r.id.equals(recipeId))).getSingle();
      expect(recipe.outputItemId, isNull, reason: 'not added to items yet');
      expect(recipe.name, 'Chilli batch');

      final lines = await (h.db.select(
        h.db.recipeLinesV2,
      )..orderBy([(l) => OrderingTerm.asc(l.lineIndex)])).get();
      expect(lines, hasLength(3));
      expect(lines[0].ingredientItemId, beans);
      expect(
        lines[0].ingredientName,
        'Beans',
        reason: 'linked line with no name of its own snapshots the item name',
      );
      expect(lines[1].ingredientItemId, isNull);
      expect(lines[1].ingredientName, 'Cumin');
      expect(lines[1].unitLabel, 'tsp');
      expect(lines[2].ingredientName, 'Secret spice');
      expect(lines[2].quantityPerBatchMicros, 3000000);
      // The legacy append-only table is frozen: nothing writes it any more.
      expect(await h.count('recipe_lines'), 0);
    });

    test('binding an existing output item at create still works', () async {
      final chilli = await h.createItem(name: 'Chilli');
      final receipt = await h.ok(
        CreateRecipe(
          outputItemId: ItemId(chilli),
          name: 'Chilli batch',
          firstRevision: revision([free('Cumin')]),
        ),
      );
      final recipe = await (h.db.select(
        h.db.recipes,
      )..where((r) => r.id.equals(receipt.createdRecordIds.first))).getSingle();
      expect(recipe.outputItemId, chilli);
    });

    test('a free line needs a name; a linked line needs a live item; unit '
        'labels are bounded', () async {
      final beans = await h.createItem(name: 'Beans');
      expect(
        await h.err(
          CreateRecipe(
            name: 'R',
            firstRevision: revision([
              RecipeLineDraft(quantityPerBatch: Quantity.whole(1)),
            ]),
          ),
        ),
        isA<ValidationError>(),
        reason: 'neither name nor link',
      );
      expect(
        await h.err(
          CreateRecipe(
            name: 'R',
            firstRevision: revision([linked(tid('NOITEM'))]),
          ),
        ),
        isA<NotFoundError>(),
      );
      expect(
        await h.err(
          CreateRecipe(
            name: 'R',
            firstRevision: revision([free('Cumin', unitLabel: 'x' * 25)]),
          ),
        ),
        isA<ValidationError>(),
        reason: 'unit label over 24 chars',
      );
      expect(
        await h.err(
          CreateRecipe(
            name: 'R',
            firstRevision: revision([free('Cumin', unitLabel: '  ')]),
          ),
        ),
        isA<ValidationError>(),
        reason: 'blank unit label',
      );
      // Distinctness still holds for LINKED lines only; free lines with
      // equal names are left alone (quiet lines, no identity to collide).
      expect(
        await h.err(
          CreateRecipe(
            name: 'R',
            firstRevision: revision([linked(beans), linked(beans)]),
          ),
        ),
        isA<ValidationError>(),
      );
      final ok = await h.ok(
        CreateRecipe(
          name: 'R',
          firstRevision: revision([free('Pinch'), free('Pinch')]),
        ),
      );
      expect(ok.createdRecordIds, hasLength(2));
    });
  });

  group('AddRecipeToItems', () {
    test(
      'one transaction: output item into its folder, chosen free lines '
      'into theirs (with unit labels), links written, recipe bound',
      () async {
        final beans = await h.createItem(name: 'Beans');
        final folderReceipt = await h.ok(
          const CreateFolder(
            name: 'Cooked',
            demandBasis: DemandBasis.perPerson,
          ),
        );
        final cookedId = folderReceipt.createdRecordIds.first;
        final recipeReceipt = await h.ok(
          CreateRecipe(
            name: 'Chilli batch',
            firstRevision: revision([
              linked(beans),
              free('Cumin', unitLabel: 'tsp'),
              free('Secret spice'),
            ]),
          ),
        );
        final recipeId = recipeReceipt.createdRecordIds.first;

        final receipt = await h.ok(
          AddRecipeToItems(
            recipeId: RecipeId(recipeId),
            folderId: FolderId(cookedId),
            ingredients: const [AddRecipeIngredient(lineIndex: 1)],
          ),
        );
        // Receipt: output item first, then the created ingredient items.
        expect(receipt.createdRecordIds, hasLength(2));
        final outputId = receipt.createdRecordIds[0];
        final cuminId = receipt.createdRecordIds[1];

        final output = await h.itemRow(outputId);
        expect(output.name, 'Chilli batch');
        expect(output.folderId, cookedId);
        final cumin = await h.itemRow(cuminId);
        expect(cumin.name, 'Cumin');
        expect(cumin.unitLabel, 'tsp', reason: 'label travels to the item');
        expect(cumin.folderId, isNull, reason: 'chosen folder was Unfiled');

        final recipe = await (h.db.select(
          h.db.recipes,
        )..where((r) => r.id.equals(recipeId))).getSingle();
        expect(recipe.outputItemId, outputId);

        final lines = await (h.db.select(
          h.db.recipeLinesV2,
        )..orderBy([(l) => OrderingTerm.asc(l.lineIndex)])).get();
        expect(lines[0].ingredientItemId, beans, reason: 'untouched');
        expect(
          lines[1].ingredientItemId,
          cuminId,
          reason: 'created AND linked',
        );
        expect(lines[2].ingredientItemId, isNull, reason: 'not chosen: free');
      },
    );

    test('idempotency guard: a recipe already in the items list is rejected '
        'with a plain error, and nothing is written', () async {
      final recipeReceipt = await h.ok(
        CreateRecipe(name: 'Soup', firstRevision: revision([free('Stock')])),
      );
      final recipeId = recipeReceipt.createdRecordIds.first;
      await h.ok(AddRecipeToItems(recipeId: RecipeId(recipeId)));
      final before = await h.effectCounts();
      final error = await h.err(AddRecipeToItems(recipeId: RecipeId(recipeId)));
      expect(error, isA<ValidationError>());
      expect(error.message, contains('already in your items'));
      expect(await h.effectCounts(), before, reason: 'nothing written');
    });

    test('guards: unknown recipe, dead folder, linked line chosen, missing '
        'line, name collisions — all rejected, nothing written', () async {
      final beans = await h.createItem(name: 'Beans');
      await h.createItem(name: 'Cumin'); // collision target
      final recipeReceipt = await h.ok(
        CreateRecipe(
          name: 'Chilli batch',
          firstRevision: revision([linked(beans), free('Cumin')]),
        ),
      );
      final recipeId = recipeReceipt.createdRecordIds.first;
      final before = await h.effectCounts();

      expect(
        await h.err(AddRecipeToItems(recipeId: RecipeId(tid('NORECIPE')))),
        isA<NotFoundError>(),
      );
      expect(
        await h.err(
          AddRecipeToItems(
            recipeId: RecipeId(recipeId),
            folderId: FolderId(tid('NOFOLDER')),
          ),
        ),
        isA<NotFoundError>(),
      );
      expect(
        await h.err(
          AddRecipeToItems(
            recipeId: RecipeId(recipeId),
            ingredients: const [AddRecipeIngredient(lineIndex: 0)],
          ),
        ),
        isA<ValidationError>(),
        reason: 'line 0 is already linked',
      );
      expect(
        await h.err(
          AddRecipeToItems(
            recipeId: RecipeId(recipeId),
            ingredients: const [AddRecipeIngredient(lineIndex: 9)],
          ),
        ),
        isA<NotFoundError>(),
        reason: 'no such line',
      );
      expect(
        await h.err(
          AddRecipeToItems(
            recipeId: RecipeId(recipeId),
            ingredients: const [AddRecipeIngredient(lineIndex: 1)],
          ),
        ),
        isA<ValidationError>(),
        reason: 'a live item named Cumin already exists — link, not create',
      );
      // The recipe name itself collides with a live item.
      await h.createItem(name: 'Chilli batch');
      expect(
        await h.err(AddRecipeToItems(recipeId: RecipeId(recipeId))),
        isA<ValidationError>(),
      );
      final after = await h.effectCounts();
      expect(after['recipes'], before['recipes']);
      expect(after['recipe_revisions'], before['recipe_revisions']);
      expect(
        after['items'],
        before['items']! + 1, // only the deliberate collision seed
      );
    });
  });

  group('LinkRecipeLineToItem / UnlinkRecipeLine', () {
    test('link writes exactly the link; unlink clears it; the line keeps '
        'its own name throughout', () async {
      final cumin = await h.createItem(name: 'Cumin');
      final recipeReceipt = await h.ok(
        CreateRecipe(
          name: 'Chilli batch',
          firstRevision: revision([free('cumin (ground)', unitLabel: 'tsp')]),
        ),
      );
      final recipeId = recipeReceipt.createdRecordIds.first;

      await h.ok(
        LinkRecipeLineToItem(
          recipeId: RecipeId(recipeId),
          lineIndex: 0,
          itemId: ItemId(cumin),
        ),
      );
      var line = await (h.db.select(h.db.recipeLinesV2)).getSingle();
      expect(line.ingredientItemId, cumin);
      expect(line.ingredientName, 'cumin (ground)', reason: 'name untouched');
      expect(line.unitLabel, 'tsp');

      await h.ok(UnlinkRecipeLine(recipeId: RecipeId(recipeId), lineIndex: 0));
      line = await (h.db.select(h.db.recipeLinesV2)).getSingle();
      expect(line.ingredientItemId, isNull);
      expect(line.ingredientName, 'cumin (ground)');

      // Unlinking an already-free line is a plain error.
      expect(
        await h.err(
          UnlinkRecipeLine(recipeId: RecipeId(recipeId), lineIndex: 0),
        ),
        isA<ValidationError>(),
      );
    });

    test('linking enforces liveness, per-revision uniqueness, and the '
        'flatness guard', () async {
      final beans = await h.createItem(name: 'Beans');
      final recipeReceipt = await h.ok(
        CreateRecipe(
          name: 'Chilli batch',
          firstRevision: revision([linked(beans), free('Cumin'), free('X')]),
        ),
      );
      final recipeId = recipeReceipt.createdRecordIds.first;
      // Put the recipe on the items list so it HAS an output item.
      final added = await h.ok(AddRecipeToItems(recipeId: RecipeId(recipeId)));
      final outputId = added.createdRecordIds.first;

      expect(
        await h.err(
          LinkRecipeLineToItem(
            recipeId: RecipeId(recipeId),
            lineIndex: 1,
            itemId: ItemId(tid('NOITEM')),
          ),
        ),
        isA<NotFoundError>(),
      );
      expect(
        await h.err(
          LinkRecipeLineToItem(
            recipeId: RecipeId(recipeId),
            lineIndex: 1,
            itemId: ItemId(beans),
          ),
        ),
        isA<ValidationError>(),
        reason: 'Beans is already an ingredient of this recipe',
      );
      expect(
        await h.err(
          LinkRecipeLineToItem(
            recipeId: RecipeId(recipeId),
            lineIndex: 1,
            itemId: ItemId(outputId),
          ),
        ),
        isA<RecipeNestingError>(),
        reason: 'its own output cannot be an ingredient',
      );

      // Nesting across recipes: another live recipe's output is untouchable.
      final otherReceipt = await h.ok(
        CreateRecipe(name: 'Soup', firstRevision: revision([free('Stock')])),
      );
      final soupId = otherReceipt.createdRecordIds.first;
      final soupAdded = await h.ok(
        AddRecipeToItems(recipeId: RecipeId(soupId)),
      );
      expect(
        await h.err(
          LinkRecipeLineToItem(
            recipeId: RecipeId(recipeId),
            lineIndex: 1,
            itemId: ItemId(soupAdded.createdRecordIds.first),
          ),
        ),
        isA<RecipeNestingError>(),
      );
    });
  });

  group('CatalogService.watchFoldersWithItems (v5 recipe outputs)', () {
    test('an output item carries its live recipe\'s id; plain items and '
        'archived-recipe outputs carry none', () async {
      final catalog = DriftCatalogService(
        h.db,
        h.applier,
        idGenerator: h.ids,
        clock: h.clock,
      );
      await h.createItem(name: 'Napkins');
      final recipeReceipt = await h.ok(
        CreateRecipe(
          name: 'Chilli batch',
          firstRevision: revision([free('Cumin')]),
        ),
      );
      final recipeId = recipeReceipt.createdRecordIds.first;
      await h.ok(AddRecipeToItems(recipeId: RecipeId(recipeId)));

      var sections = await catalog.watchFoldersWithItems().first;
      var unfiled = sections.singleWhere((s) => s.isUnfiled).items;
      final chilli = unfiled.singleWhere((s) => s.item.name == 'Chilli batch');
      expect(chilli.isRecipeOutput, isTrue);
      expect(chilli.recipeId, recipeId, reason: 'says WHICH recipe');
      final napkins = unfiled.singleWhere((s) => s.item.name == 'Napkins');
      expect(napkins.isRecipeOutput, isFalse);
      expect(napkins.recipeId, isNull);

      // Archiving the recipe quietly turns the group back into a plain row.
      await h.ok(
        SetRecipeArchived(recipeId: RecipeId(recipeId), archived: true),
      );
      sections = await catalog.watchFoldersWithItems().first;
      unfiled = sections.singleWhere((s) => s.isUnfiled).items;
      expect(
        unfiled.singleWhere((s) => s.item.name == 'Chilli batch').recipeId,
        isNull,
      );
    });
  });

  group('items.unit_label through the command path', () {
    test('CreateItem stores it, UpdateItem changes it, the clear mirror '
        'erases it, bounds are validator-enforced', () async {
      expect(
        await h.err(CreateItem(name: 'Flour', unitLabel: 'x' * 25)),
        isA<ValidationError>(),
      );
      expect(
        await h.err(const CreateItem(name: 'Flour', unitLabel: '   ')),
        isA<ValidationError>(),
      );

      final receipt = await h.ok(
        const CreateItem(name: 'Flour', unitLabel: 'cups'),
      );
      final id = receipt.createdRecordIds.first;
      expect((await h.itemRow(id)).unitLabel, 'cups');

      await h.ok(UpdateItem(itemId: ItemId(id), unitLabel: 'lbs'));
      expect((await h.itemRow(id)).unitLabel, 'lbs');

      // Untouched by an unrelated update (absent ≠ clear).
      await h.ok(UpdateItem(itemId: ItemId(id), name: 'Bread flour'));
      expect((await h.itemRow(id)).unitLabel, 'lbs');

      await h.ok(UpdateItem(itemId: ItemId(id), clearUnitLabel: true));
      expect((await h.itemRow(id)).unitLabel, isNull);

      expect(
        await h.err(UpdateItem(itemId: ItemId(id), unitLabel: 'x' * 25)),
        isA<ValidationError>(),
      );
    });
  });
}
