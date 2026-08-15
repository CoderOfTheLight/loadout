/// §9 `/recipes/:recipeId` — RecipeDetailScreen.
///
/// Renders the current revision read-only (yield, lines, note) with a
/// revision picker ("Revision 3 · 2026-08-02") that renders any prior
/// revision verbatim, a revision history list (immutable, each entry with
/// its form/OCR source badge), and app-bar Revise / Archive actions.
/// Commands: `RecipeService.setArchived` only — revisions are permanent by
/// design, so there is no edit here, only "Revise" (append).
///
/// "Scale to event" (proposal §3) opens a read-only sheet
/// (`recipe_scale_sheet.dart`) that shows the CURRENT revision as whole
/// batches against an upcoming event's stored packing list. A view — the
/// saved recipe never changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/unit_display.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/item.dart';
import '../application/recipe_service.dart';
import '../domain/recipe.dart';
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
    return detailAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Recipe')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Recipe')),
        body: const Center(child: Text("Couldn't load this recipe.")),
      ),
      data: (detail) => _buildLoaded(context, detail, itemsById),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    RecipeDetail detail,
    Map<String, Item> itemsById,
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
    final outputItem = itemsById[recipe.outputItemId.value];
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
                  outputItem?.name ?? 'Unknown item',
                  style: theme.textTheme.titleLarge,
                ),
                if (viewed != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _yieldCaption(viewed, outputItem),
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  // Always scales the CURRENT revision (`revisions.first`),
                  // whatever revision is being viewed — you cook today's
                  // method. Read-only, so archived recipes may scale too.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('scale-to-event'),
                      onPressed: () => showRecipeScaleSheet(
                        context,
                        outputItemId: recipe.outputItemId.value,
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

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({required this.line, required this.itemsById});

  final RecipeLine line;
  final Map<String, Item> itemsById;

  @override
  Widget build(BuildContext context) {
    final item = itemsById[line.ingredientItemId.value];
    final name = item == null
        ? 'Unknown item'
        : item.isArchived
        ? '${item.name} (archived)'
        : item.name;
    final unit = item == null ? '' : unitSuffix(item.unit);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      trailing: Text(
        '${QuantityCodec.format(line.quantityPerBatch)}$unit',
        style: Theme.of(context).textTheme.bodyLarge,
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
