/// §9 `/recipes/:recipeId` — RecipeDetailScreen.
///
/// Renders the current revision read-only (yield, lines, note) with a
/// revision picker ("Revision 3 · 2026-08-02") that renders any prior
/// revision verbatim, a revision history list (immutable, each entry with
/// its form/OCR source badge), and app-bar Revise / Archive actions.
///
/// v5 (recipe decoupling): a recipe normally lives OUTSIDE the item list.
/// A live, unbound recipe offers the labeled "Add to my items" action —
/// the sheet (`recipe_add_to_items_sheet.dart`) picks a folder for the
/// recipe and optionally turns unlinked ingredient lines into items too
/// (one `AddRecipeToItems` command). A recipe that is already in the items
/// list shows WHERE it lives instead of the action. Ingredient lines read
/// table-like — amount first, then the display-only unit, then the name
/// ("0.5 cup · Flour") — free lines under their own text, linked lines as
/// their live item.
///
/// v7 (money): the CURRENT revision carries what one batch costs, right
/// under the yield so it reads "this batch costs X". Σ (per-batch quantity ×
/// the linked item's price) over linked, priced lines, at TODAY's prices —
/// a live figure, not a snapshot: repricing an ingredient moves it. Lines
/// with no price (unlinked, or linked to an unpriced item) contribute
/// nothing and are counted out loud, and a recipe with nothing priced shows
/// no money at all rather than a $0. Only the current revision is costed:
/// an old revision's amounts at today's prices would be a hybrid of two
/// moments, so viewing one simply shows no figure.
///
/// "Scale to event" (proposal §3) opens a read-only sheet
/// (`recipe_scale_sheet.dart`) that shows the CURRENT revision as whole
/// batches against an upcoming event's stored packing list. A view — the
/// saved recipe never changes; hidden until the recipe has an output item.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_display.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../../core/money.dart';
import '../../../core/money_codec.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/folder.dart';
import '../../catalog/domain/item.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../application/recipe_service.dart';
import '../domain/recipe.dart';
import '../domain/recipe_cost.dart';
import 'recipe_add_to_items_sheet.dart';
import 'recipe_scale_sheet.dart';

/// Canonical (const, so family-cached) filter: archived items included —
/// old revisions may reference since-archived ingredients.
const _allItemsFilter = ItemFilter(includeArchived: true);

class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  /// Revision number being viewed; null = current (latest).
  int? _viewedRevision;
  bool _archiveBusy = false;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(recipeDetailProvider(widget.recipeId));
    final items = ref.watch(itemListProvider(_allItemsFilter));
    final itemsById = <String, Item>{
      for (final summary in items.valueOrNull ?? const <ItemSummary>[])
        summary.item.id.value: summary.item,
    };
    final foldersById = <String, Folder>{
      for (final folder
          in ref.watch(folderListProvider).valueOrNull ?? const <Folder>[])
        folder.id.value: folder,
    };
    return detailAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Recipe')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Recipe')),
        body: const Center(child: Text("Couldn't load this recipe.")),
      ),
      data: (detail) => _buildLoaded(context, detail, itemsById, foldersById),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    RecipeDetail detail,
    Map<String, Item> itemsById,
    Map<String, Folder> foldersById,
  ) {
    final theme = Theme.of(context);
    final recipe = detail.recipe;
    final revisions = detail.revisions; // newest first
    final latest = revisions.isEmpty ? null : revisions.first;
    final viewed = revisions.isEmpty
        ? null
        : revisions.firstWhere(
            (r) => r.revision == _viewedRevision,
            orElse: () => revisions.first,
          );
    final outputItemId = recipe.outputItemId?.value;
    final outputItem = outputItemId == null ? null : itemsById[outputItemId];
    // Only the CURRENT revision is costed (see the library doc): today's
    // prices over an old revision's amounts would mix two moments.
    final cost = viewed == null || viewed.revision != latest?.revision
        ? null
        : recipeBatchCost([
            for (final line in viewed.lines)
              (
                quantityMicros: line.quantityPerBatch.micros,
                unitPrice: switch (line.ingredientItemId) {
                  final id? => itemsById[id.value]?.unitPrice,
                  null => null,
                },
              ),
          ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name),
        actions: [
          TextButton(
            onPressed: recipe.isArchived
                ? null
                : () => context.push('/recipes/${widget.recipeId}/revise'),
            child: const Text('Revise'),
          ),
          // A word, not a glyph: no icon-only actions (design-spec §2 —
          // only search's magnifier is universal).
          TextButton(
            key: const Key('archive-action'),
            onPressed: _archiveBusy
                ? null
                : () => _setArchived(!recipe.isArchived),
            child: Text(recipe.isArchived ? 'Unarchive' : 'Archive'),
          ),
        ],
      ),
      body: ListView(
        children: [
          ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recipe.isArchived) ...[
                  WarningBanner(
                    message:
                        'This recipe is archived. Unarchive it to revise it '
                        'or plan production with it.',
                    actionLabel: 'Unarchive',
                    onAction: _archiveBusy ? null : () => _setArchived(false),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('Output', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  // v5: a recipe without an output item is the normal
                  // decoupled state — it makes itself, not a catalog item.
                  outputItemId == null
                      ? recipe.name
                      : outputItem?.name ?? 'Unknown item',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                // v5: in the items list → say where it lives; not yet →
                // the labeled action that puts it there (live recipes only;
                // an archived recipe cannot be added).
                if (outputItemId != null)
                  _InItemsLocation(
                    outputItem: outputItem,
                    foldersById: foldersById,
                  )
                else if (!recipe.isArchived && latest != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('add-to-items'),
                      onPressed: () => _addToItems(recipe.name, latest),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Add to my items'),
                    ),
                  ),
                if (viewed != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _yieldCaption(viewed, outputItem),
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (cost != null && !cost.isEmpty) ...[
                    const SizedBox(height: 4),
                    _BatchCost(
                      cost: cost,
                      // A per-unit figure only where dividing the yield is
                      // honest: a whole count of things, and never a legacy
                      // MEASURED output item, whose yield is a weight or a
                      // volume rather than a number of portions.
                      perUnit:
                          outputItem == null || outputItem.unit == ItemUnit.each
                          ? cost.perYieldUnit(viewed.yieldQuantity)
                          : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Always scales the CURRENT revision (`revisions.first`),
                  // whatever revision is being viewed — you cook today's
                  // method. Read-only, so archived recipes may scale too.
                  // v5: needs the output item on a packing list, so it is
                  // only offered once the recipe has been added to items.
                  if (outputItemId != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const Key('scale-to-event'),
                        onPressed: () => showRecipeScaleSheet(
                          context,
                          outputItemId: outputItemId,
                          outputItemName: outputItem?.name ?? 'Unknown item',
                          revision: revisions.first,
                          itemsById: itemsById,
                        ),
                        icon: const Icon(Icons.event_outlined),
                        label: const Text('Scale to event'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          // initialValue-only API: remount when the viewed
                          // revision changes from the history list below.
                          key: ValueKey('revision-picker-${viewed.revision}'),
                          initialValue: viewed.revision,
                          // Revision labels carry a date; without this they
                          // overflow the field on narrow screens.
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Viewing',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final revision in revisions)
                              DropdownMenuItem(
                                value: revision.revision,
                                child: Text(
                                  _revisionLabel(revision),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (revision) =>
                              setState(() => _viewedRevision = revision),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SourceBadge(sourceKind: viewed.sourceKind),
                    ],
                  ),
                  if (latest != null && viewed.revision != latest.revision) ...[
                    const SizedBox(height: 12),
                    WarningBanner(
                      message:
                          'Viewing revision ${viewed.revision}. The current '
                          'revision is ${latest.revision}. Revisions are '
                          'permanent and never change.',
                      actionLabel: 'View current',
                      onAction: () => setState(() => _viewedRevision = null),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Ingredients per batch',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  for (final line in viewed.lines)
                    _IngredientTile(line: line, itemsById: itemsById),
                  if (viewed.note.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Note', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(viewed.note, style: theme.textTheme.bodyLarge),
                  ],
                ],
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Text('Revision history', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Revisions are permanent records — revising always adds a '
                  'new one on top.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                for (final revision in revisions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    selected:
                        viewed != null && revision.revision == viewed.revision,
                    title: Text('Revision ${revision.revision}'),
                    // The badge wraps under the date rather than sitting in
                    // `trailing`, where its label overflows narrow screens.
                    subtitle: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(_formatDate(revision.createdAt)),
                        _SourceBadge(sourceKind: revision.sourceKind),
                      ],
                    ),
                    onTap: () =>
                        setState(() => _viewedRevision = revision.revision),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addToItems(
    String recipeName,
    RecipeRevisionView current,
  ) async {
    final added = await showAddToItemsSheet(
      context,
      recipeId: widget.recipeId,
      recipeName: recipeName,
      currentLines: current.lines,
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Added to your items')));
    }
  }

  Future<void> _setArchived(bool archived) async {
    setState(() => _archiveBusy = true);
    final result = await ref
        .read(recipeServiceProvider)
        .setArchived(recipeId: widget.recipeId, archived: archived);
    if (!mounted) return;
    setState(() => _archiveBusy = false);
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case Ok():
        messenger.showSnackBar(
          SnackBar(
            content: Text(archived ? 'Recipe archived' : 'Recipe unarchived'),
          ),
        );
      case Err(:final error):
        // Validator messages are content-free by design (§10).
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String _yieldCaption(RecipeRevisionView revision, Item? outputItem) {
    final amount = QuantityCodec.format(revision.yieldQuantity);
    final unit = outputItem == null ? '' : unitSuffix(outputItem.unit);
    final label = revision.yieldLabel;
    final suffix = label == null || label.isEmpty ? '' : ' — “$label”';
    return 'Makes $amount$unit per batch$suffix';
  }

  String _revisionLabel(RecipeRevisionView revision) =>
      'Revision ${revision.revision} · ${_formatDate(revision.createdAt)}';
}

/// "In your items · Prep" — where an added recipe's output item lives. The
/// folder identity chip travels with the name (spec §3: an item outside its
/// own section always carries its folder chip); Unfiled keeps the neutral
/// inbox glyph.
class _InItemsLocation extends StatelessWidget {
  const _InItemsLocation({required this.outputItem, required this.foldersById});

  final Item? outputItem;
  final Map<String, Folder> foldersById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folder = switch (outputItem?.folderId?.value) {
      final id? => foldersById[id],
      null => null,
    };
    return Row(
      key: const Key('in-items-location'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (folder != null)
          FolderChip.forFolder(folder, size: FolderChipSize.small)
        else
          Icon(
            Icons.inbox_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'In your items · ${folder?.name ?? 'Unfiled'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// What one batch costs, directly under the yield: "$12.40 a batch ·
/// $1.24 each". The money is the figure ([Numerals.glance] — the recipe
/// itself is the screen's subject, so the cost is a block of its own, not a
/// hero); the connecting words stay at body size so the line reads as a
/// sentence rather than a headline.
///
/// One plain note for everything the total left out. "Not linked to an item"
/// and "linked but never priced" are different plumbing but the same money
/// — nothing — and splitting them costs a sentence the owner did not ask
/// for on a screen she already finds busy.
class _BatchCost extends StatelessWidget {
  const _BatchCost({required this.cost, required this.perUnit});

  final RecipeBatchCost cost;

  /// What one of whatever the batch makes costs; null when dividing the
  /// yield would not be honest arithmetic.
  final Money? perUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final figure = Numerals.glance(theme.textTheme);
    final words = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      key: const Key('recipe-batch-cost'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: MoneyCodec.format(cost.total), style: figure),
              TextSpan(text: ' a batch', style: words),
              if (perUnit != null) ...[
                TextSpan(text: ' · ', style: words),
                TextSpan(text: MoneyCodec.format(perUnit!), style: figure),
                TextSpan(text: ' each', style: words),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text("At today's item prices.", style: muted),
        if (cost.isPartial) ...[
          const SizedBox(height: 4),
          Text(
            cost.unpricedLineCount == 1
                ? '1 ingredient has no price — not counted.'
                : '${cost.unpricedLineCount} ingredients have no price '
                      '— not counted.',
            style: muted,
          ),
        ],
      ],
    );
  }
}

/// One ingredient line, table-like (v5 feedback: amount first, then unit,
/// then name — "0.5 cup · Flour"). Free lines render under their OWN name
/// and display-only unit label; linked lines render as their live item,
/// with the legacy measured-unit suffix as the label fallback. Tabular
/// numerals keep the amounts aligned down the list.
class _IngredientTile extends StatelessWidget {
  const _IngredientTile({required this.line, required this.itemsById});

  final RecipeLine line;
  final Map<String, Item> itemsById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = switch (line.ingredientItemId) {
      final id? => itemsById[id.value],
      null => null,
    };
    final name = !line.isLinked
        ? line.name
        : item == null
        ? 'Unknown item'
        : item.isArchived
        ? '${item.name} (archived)'
        : item.name;
    final unit = line.unitLabel != null
        ? ' ${line.unitLabel}'
        : item == null
        ? ''
        : unitSuffix(item.unit);
    final amount = QuantityCodec.format(line.quantityPerBatch);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$amount$unit · $name',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontFeatures: Numerals.tabular,
          ),
        ),
      ),
    );
  }
}

/// Source badge (§9: each revision carries its form/OCR source). Icon +
/// text — meaning never color-only.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.sourceKind});

  final RecipeSourceKind sourceKind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label) = switch (sourceKind) {
      RecipeSourceKind.form => (Icons.edit_outlined, 'Entered by hand'),
      RecipeSourceKind.ocr => (Icons.document_scanner_outlined, 'Scanned'),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
      label: Text(label),
      labelStyle: theme.textTheme.labelMedium,
      visualDensity: VisualDensity.compact,
    );
  }
}

String _formatDate(Instant instant) {
  final date = DateTime.fromMicrosecondsSinceEpoch(
    instant.epochMicrosUtc,
    isUtc: true,
  );
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
