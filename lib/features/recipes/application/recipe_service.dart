import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../data/db/app_database.dart' as db;
import '../../approval/domain/approval_service.dart';
import '../../approval/domain/commands.dart';
import '../../approval/domain/proposal.dart';
import '../domain/recipe.dart';
import '../domain/recipe_drafts.dart';
import '../../../data/db/table_watch.dart';

final class RecipeSummary {
  const RecipeSummary({
    required this.id,
    required this.name,
    this.outputItemId,
    this.outputItemName = '',
    required this.latestRevision,
    this.yieldMicros,
    this.yieldLabel,
    required this.ingredientCount,
    this.archivedAt,
  });

  final String id;
  final String name;

  /// v5: null until the recipe is added to the item list.
  final String? outputItemId;

  /// '' when the recipe has no output item yet.
  final String outputItemName;
  final int latestRevision;
  final int? yieldMicros;
  final String? yieldLabel;
  final int ingredientCount;
  final Instant? archivedAt;

  bool get isInItems => outputItemId != null;
}

/// Full recipe with every revision (the detail screen's revision dropdown
/// renders any prior revision verbatim).
final class RecipeDetail {
  const RecipeDetail({required this.recipe, required this.revisions});

  final Recipe recipe;

  /// Newest first; current = first.
  final List<RecipeRevisionView> revisions;
}

/// Screen-facing recipe surface (design §6.5). Revisions are append-only;
/// the validator runs assertFlat/detectCycles on every write.
abstract interface class RecipeService {
  /// Returns the created recipeId (revision 1 included).
  Future<Result<String>> createRecipe(RecipeFormDraft draft);

  /// Appends an immutable revision; returns the new revision number.
  Future<Result<int>> reviseRecipe({
    required String recipeId,
    required RecipeFormDraft draft,
  });
  Future<Result<void>> setArchived({
    required String recipeId,
    required bool archived,
  });

  /// v5: puts the recipe on the item list — ONE command, ONE transaction:
  /// creates the output item (named after the recipe) in [folderId] (null =
  /// Unfiled), optionally creates + links items for the chosen free lines
  /// (each into its own folder, null = Unfiled), and binds the recipe.
  /// Returns the created output item's id. A recipe that is already in the
  /// items list is rejected with a plain error.
  Future<Result<String>> addToItems({
    required String recipeId,
    String? folderId,
    List<({int lineIndex, String? folderId})> ingredients = const [],
  });

  /// v5: links a free line of the CURRENT revision to a live catalog item.
  Future<Result<void>> linkLine({
    required String recipeId,
    required int lineIndex,
    required String itemId,
  });

  /// v5: removes a line's catalog link; the line keeps its own name.
  Future<Result<void>> unlinkLine({
    required String recipeId,
    required int lineIndex,
  });

  Stream<List<RecipeSummary>> watchRecipes();
  Stream<RecipeDetail> watchRecipe(String recipeId);
}

final class DriftRecipeService implements RecipeService {
  DriftRecipeService(
    db.AppDatabase database,
    ApprovalService approval, {
    IdGenerator idGenerator = const UlidIdGenerator(),
    this._clock = const SystemClock(),
  }) : _db = database,
       _approval = approval,
       _ids = idGenerator;

  final db.AppDatabase _db;
  final ApprovalService _approval;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<String>> createRecipe(RecipeFormDraft draft) async {
    final result = await _submit(
      CreateRecipe(
        outputItemId: draft.outputItemId == null
            ? null
            : ItemId(draft.outputItemId!),
        name: draft.name,
        firstRevision: _toRevisionDraft(draft),
      ),
    );
    return result.fold(
      (receipt) => Ok(receipt.createdRecordIds.first),
      Err.new,
    );
  }

  @override
  Future<Result<String>> addToItems({
    required String recipeId,
    String? folderId,
    List<({int lineIndex, String? folderId})> ingredients = const [],
  }) async {
    final result = await _submit(
      AddRecipeToItems(
        recipeId: RecipeId(recipeId),
        folderId: folderId == null ? null : FolderId(folderId),
        ingredients: [
          for (final ingredient in ingredients)
            AddRecipeIngredient(
              lineIndex: ingredient.lineIndex,
              folderId: ingredient.folderId == null
                  ? null
                  : FolderId(ingredient.folderId!),
            ),
        ],
      ),
    );
    return result.fold(
      (receipt) => Ok(receipt.createdRecordIds.first),
      Err.new,
    );
  }

  @override
  Future<Result<void>> linkLine({
    required String recipeId,
    required int lineIndex,
    required String itemId,
  }) async {
    final result = await _submit(
      LinkRecipeLineToItem(
        recipeId: RecipeId(recipeId),
        lineIndex: lineIndex,
        itemId: ItemId(itemId),
      ),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<void>> unlinkLine({
    required String recipeId,
    required int lineIndex,
  }) async {
    final result = await _submit(
      UnlinkRecipeLine(recipeId: RecipeId(recipeId), lineIndex: lineIndex),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Future<Result<int>> reviseRecipe({
    required String recipeId,
    required RecipeFormDraft draft,
  }) async {
    final result = await _submit(
      AddRecipeRevision(
        recipeId: RecipeId(recipeId),
        revision: _toRevisionDraft(draft),
        // One name for the recipe and its output item — a rename rides the
        // revise (the applier no-ops when it matches the current name).
        name: draft.name,
      ),
    );
    return result.fold((receipt) async {
      final revisionId = receipt.createdRecordIds.first;
      final row = await (_db.select(
        _db.recipeRevisions,
      )..where((r) => r.id.equals(revisionId))).getSingle();
      return Ok(row.revision);
    }, (error) async => Err<int>(error));
  }

  @override
  Future<Result<void>> setArchived({
    required String recipeId,
    required bool archived,
  }) async {
    final result = await _submit(
      SetRecipeArchived(recipeId: RecipeId(recipeId), archived: archived),
    );
    return result.fold((_) => const Ok(null), Err.new);
  }

  @override
  Stream<List<RecipeSummary>> watchRecipes() => _db
      .watchTables('recipes.list', {
        _db.recipes,
        _db.recipeRevisions,
        _db.recipeLinesV2,
        _db.items,
      })
      .asyncMap((_) => _loadSummaries());

  @override
  Stream<RecipeDetail> watchRecipe(String recipeId) => _db
      .watchTables('recipes.detail', {
        _db.recipes,
        _db.recipeRevisions,
        _db.recipeLinesV2,
        _db.items,
      })
      .asyncMap((_) => _loadDetail(recipeId));

  Future<List<RecipeSummary>> _loadSummaries() async {
    final recipes = await _db.recipeDao.all();
    final summaries = <RecipeSummary>[];
    for (final recipe in recipes) {
      final latest = await _db.recipeDao.latestRevisionFor(recipe.id);
      final lines = latest == null
          ? const <db.RecipeLineV2>[]
          : await _db.recipeDao.linesForRevision(latest.id);
      final outputItem = recipe.outputItemId == null
          ? null
          : await _db.itemDao.byId(recipe.outputItemId!);
      summaries.add(
        RecipeSummary(
          id: recipe.id,
          name: recipe.name,
          outputItemId: recipe.outputItemId,
          outputItemName: outputItem?.name ?? '',
          latestRevision: latest?.revision ?? 0,
          yieldMicros: latest?.yieldMicros,
          yieldLabel: latest?.yieldLabel,
          ingredientCount: lines.length,
          archivedAt: recipe.archivedAtMicros == null
              ? null
              : Instant(recipe.archivedAtMicros!),
        ),
      );
    }
    return summaries;
  }

  Future<RecipeDetail> _loadDetail(String recipeId) async {
    final recipe = await _db.recipeDao.byId(recipeId);
    if (recipe == null) {
      throw StateError('recipe does not exist');
    }
    final revisions = await _db.recipeDao.revisionsFor(recipeId);
    return RecipeDetail(
      recipe: Recipe(
        id: RecipeId(recipe.id),
        outputItemId: recipe.outputItemId == null
            ? null
            : ItemId(recipe.outputItemId!),
        name: recipe.name,
        archivedAt: recipe.archivedAtMicros == null
            ? null
            : Instant(recipe.archivedAtMicros!),
        createdAt: Instant(recipe.createdAtMicros),
      ),
      revisions: [
        for (final revision in revisions)
          RecipeRevisionView(
            id: RecipeRevisionId(revision.id),
            recipeId: RecipeId(revision.recipeId),
            revision: revision.revision,
            yieldQuantity: Quantity.fromMicros(revision.yieldMicros),
            yieldLabel: revision.yieldLabel,
            sourceKind: RecipeSourceKind.fromDb(revision.sourceKind),
            note: revision.note,
            createdAt: Instant(revision.createdAtMicros),
            lines: [
              for (final line in await _db.recipeDao.linesForRevision(
                revision.id,
              ))
                RecipeLine(
                  name: line.ingredientName,
                  unitLabel: line.unitLabel,
                  ingredientItemId: line.ingredientItemId == null
                      ? null
                      : ItemId(line.ingredientItemId!),
                  quantityPerBatch: Quantity.fromMicros(
                    line.quantityPerBatchMicros,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  RecipeRevisionDraft _toRevisionDraft(RecipeFormDraft draft) =>
      RecipeRevisionDraft(
        yieldQuantity: draft.yieldQuantity,
        yieldLabel: draft.yieldLabel,
        note: draft.note,
        sourceKind: draft.sourceKind,
        lines: [
          for (final line in draft.lines)
            RecipeLineDraft(
              name: line.name,
              unitLabel: line.unitLabel,
              ingredientItemId: line.itemId == null
                  ? null
                  : ItemId(line.itemId!),
              quantityPerBatch: line.quantityPerBatch,
            ),
        ],
      );

  Future<Result<CommandReceipt>> _submit(WorkspaceCommand command) =>
      _approval.submit(
        Proposal(
          commandId: CommandId(_ids.newId()),
          origin: ProposalOrigin.form,
          command: command,
          createdAt: _clock.now(),
        ),
      );
}
