/// "Paste ingredients" bottom sheet (proposal §3, recipe screen): paste
/// multi-line text, review what each line matched, and ONLY on confirm are
/// new items created (through the real `CatalogService`, into one folder
/// picked once for the whole batch) and the resolved rows handed back to
/// the form. Cancel/Back/dismiss write nothing at all.
///
/// GATE 5 SEAM: the review stage renders `List<PasteCandidateLine>` — the
/// producer-agnostic shape `ingredient_paste.dart` defines — so the OCR
/// flow becomes a second producer feeding this same reviewer. No OCR is
/// built here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/result.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/folder.dart';
import '../../catalog/domain/item.dart';
import 'ingredient_paste.dart';
import 'recipe_catalog_filters.dart';

/// Opens the sheet; resolves to the confirmed rows for the form to append,
/// or null when dismissed without confirming (nothing was written then).
Future<List<PastedIngredient>?> showIngredientPasteSheet(
  BuildContext context,
) => showModalBottomSheet<List<PastedIngredient>>(
  context: context,
  isScrollControlled: true,
  builder: (_) => const IngredientPasteSheet(),
);

class IngredientPasteSheet extends ConsumerStatefulWidget {
  const IngredientPasteSheet({super.key});

  @override
  ConsumerState<IngredientPasteSheet> createState() =>
      _IngredientPasteSheetState();
}

class _IngredientPasteSheetState extends ConsumerState<IngredientPasteSheet> {
  final _textController = TextEditingController();

  /// Null while typing; parsed candidates once "Review" is pressed.
  List<PasteCandidateLine>? _candidates;

  /// Per-candidate "create this one" ticks (unmatched lines only).
  final Map<int, bool> _create = {};

  /// Sentinel for "Unfiled" in the folder picker (null is not a usable
  /// dropdown value).
  static const String _unfiled = '';
  String _createFolderId = _unfiled;
  bool _submitting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int get _addCount {
    final candidates = _candidates ?? const <PasteCandidateLine>[];
    var count = 0;
    for (var i = 0; i < candidates.length; i++) {
      count += switch (candidates[i].status) {
        PasteLineStatus.matched || PasteLineStatus.ambiguous => 1,
        PasteLineStatus.unmatched => (_create[i] ?? false) ? 1 : 0,
        PasteLineStatus.excluded => 0,
      };
    }
    return count;
  }

  void _review(List<Item> catalog, Set<String> salesTableFolderIds) {
    final candidates = parseIngredientPaste(
      _textController.text,
      catalog: catalog,
      salesTableFolderIds: salesTableFolderIds,
    );
    setState(() {
      _candidates = candidates;
      _create.clear();
      for (var i = 0; i < candidates.length; i++) {
        if (candidates[i].status == PasteLineStatus.unmatched) {
          _create[i] = true;
        }
      }
    });
  }

  /// THE writing moment: creates the ticked new items (one command each,
  /// through the single command path) and pops with the resolved rows in
  /// paste order. On a create failure the sheet stays open and says so —
  /// items already created stay created (they are ordinary catalog rows the
  /// owner can see), and nothing was added to the recipe form.
  Future<void> _confirm() async {
    final candidates = _candidates;
    if (candidates == null || _submitting) return;
    setState(() => _submitting = true);
    final catalog = ref.read(catalogServiceProvider);
    final folderId = _createFolderId == _unfiled ? null : _createFolderId;
    final results = <PastedIngredient>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      switch (candidate.status) {
        case PasteLineStatus.matched:
          results.add(
            PastedIngredient(
              itemId: candidate.match!.id.value,
              quantityPerBatch: candidate.quantityPerBatch,
            ),
          );
        case PasteLineStatus.ambiguous:
          // Left for manual fixing: an empty row on the form, amount kept.
          results.add(
            PastedIngredient(quantityPerBatch: candidate.quantityPerBatch),
          );
        case PasteLineStatus.unmatched:
          if (!(_create[i] ?? false)) break;
          final created = await catalog.createItem(
            ItemDraft(name: candidate.name, folderId: folderId),
          );
          switch (created) {
            case Ok(:final value):
              results.add(
                PastedIngredient(
                  itemId: value,
                  quantityPerBatch: candidate.quantityPerBatch,
                ),
              );
            case Err(:final error):
              if (!mounted) return;
              setState(() => _submitting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Could not create «${candidate.name}»: ${error.message}',
                  ),
                ),
              );
              return;
          }
        case PasteLineStatus.excluded:
          break; // Skipped, with the reason shown in the review list.
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(results);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(itemListProvider(const ItemFilter()));
    final salesTableFolderIds = ref.watch(salesTableFolderIdsProvider);
    final folders = ref.watch(recipeFolderListProvider).valueOrNull;
    final ready =
        items.valueOrNull != null &&
        salesTableFolderIds != null &&
        folders != null;
    return SafeArea(
      child: Padding(
        // The sheet holds a text field: keep it above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: !ready
                ? SizedBox(
                    height: 160,
                    child: items.hasError
                        ? const Center(
                            child: Text('Items could not be loaded.'),
                          )
                        : const Center(child: CircularProgressIndicator()),
                  )
                : _candidates == null
                ? _buildInput(theme, items.value!, salesTableFolderIds)
                : _buildReview(theme, folders),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(
    ThemeData theme,
    List<ItemSummary> summaries,
    Set<String> salesTableFolderIds,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Paste ingredients', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'One ingredient per line. A leading amount — "2x carrots", '
          '"3 bags onions" — becomes the per-batch count; anything unclear '
          'is left blank for you.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: TextField(
            key: const Key('paste-input'),
            controller: _textController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '2x carrots\n3 bags onions\nrolls',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const Spacer(),
            FilledButton(
              key: const Key('paste-review'),
              onPressed: () => _review([
                for (final summary in summaries) summary.item,
              ], salesTableFolderIds),
              child: const Text('Review'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReview(ThemeData theme, List<Folder> folders) {
    final candidates = _candidates!;
    final anyCreates = _create.isNotEmpty;
    final count = _addCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review before adding', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Nothing is saved until you add them.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: candidates.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nothing to review — the pasted text was empty.'),
                )
              // Non-lazy on purpose: a paste is a handful of lines, and the
              // whole review must be walkable (and testable) as one column.
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < candidates.length; i++)
                        _buildCandidateRow(theme, i, candidates[i]),
                    ],
                  ),
                ),
        ),
        if (anyCreates) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('paste-folder-picker'),
            initialValue: _createFolderId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'New items go in',
              helperText: 'One folder for everything created from this paste',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: _unfiled, child: Text('Unfiled')),
              // Sales-table folders are excluded here too: an item created
              // AS an ingredient must never land somewhere no recipe can
              // see it.
              for (final folder in folders)
                if (!isSalesTableFolderName(folder.name))
                  DropdownMenuItem(
                    value: folder.id.value,
                    child: Text(folder.name, overflow: TextOverflow.ellipsis),
                  ),
            ],
            onChanged: (value) =>
                setState(() => _createFolderId = value ?? _unfiled),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() => _candidates = null),
              child: const Text('Back'),
            ),
            const Spacer(),
            FilledButton(
              key: const Key('paste-confirm'),
              onPressed: count == 0 || _submitting ? null : _confirm,
              child: Text(
                'Add $count ${count == 1 ? 'ingredient' : 'ingredients'}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCandidateRow(
    ThemeData theme,
    int index,
    PasteCandidateLine candidate,
  ) {
    final amount = candidate.quantityPerBatch;
    final amountNote = amount == null
        ? 'amount left for you'
        : '${QuantityCodec.format(amount)} per batch';
    switch (candidate.status) {
      case PasteLineStatus.matched:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.check_circle_outline,
            color: theme.colorScheme.primary,
          ),
          title: Text(candidate.rawText),
          subtitle: Text('→ ${candidate.match!.name} · $amountNote'),
        );
      case PasteLineStatus.ambiguous:
        final names = [for (final item in candidate.nearMatches) item.name];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.help_outline, color: theme.colorScheme.tertiary),
          title: Text(candidate.rawText),
          subtitle: Text(
            'Could be ${names.join(' or ')} — added blank; '
            'pick on the form',
          ),
        );
      case PasteLineStatus.unmatched:
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _create[index] ?? false,
          onChanged: (checked) =>
              setState(() => _create[index] = checked ?? false),
          title: Text('Create «${candidate.name}»'),
          subtitle: Text(
            candidate.rawText == candidate.name
                ? 'New item · $amountNote'
                : '${candidate.rawText} · $amountNote',
          ),
        );
      case PasteLineStatus.excluded:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.block_outlined, color: theme.colorScheme.error),
          title: Text(candidate.rawText),
          subtitle: Text(
            '«${candidate.match!.name}» is on the sales table — '
            'recipes never use it. Skipped.',
          ),
        );
    }
  }
}
