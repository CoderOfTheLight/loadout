/// "Add to my items" bottom sheet (v5 recipe decoupling): puts a recipe on
/// the item list, on the owner's say-so only.
///
/// The sheet picks the folder the recipe's output item goes into (the
/// shared folder picker — a pick-list, never free text), then offers the
/// CURRENT revision's unlinked ingredient lines as an opt-in checklist
/// ("also add these as items"), each defaulting to the recipe's folder
/// until given its own. Confirm submits ONE `AddRecipeToItems` command —
/// one transaction: the output item, the chosen ingredient items (created
/// AND linked back to their lines), and the recipe binding land together
/// or not at all. Validator refusals surface as plain text in the sheet.
///
/// Resolves to `true` when the recipe was added, null when dismissed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/result.dart';
import '../../catalog/domain/folder.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../catalog/presentation/folder_picker_sheet.dart';
import '../domain/recipe.dart';

/// Opens the sheet over the recipe's CURRENT revision lines.
Future<bool?> showAddToItemsSheet(
  BuildContext context, {
  required String recipeId,
  required String recipeName,
  required List<RecipeLine> currentLines,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => AddToItemsSheet(
    recipeId: recipeId,
    recipeName: recipeName,
    currentLines: currentLines,
  ),
);

class AddToItemsSheet extends ConsumerStatefulWidget {
  const AddToItemsSheet({
    super.key,
    required this.recipeId,
    required this.recipeName,
    required this.currentLines,
  });

  final String recipeId;
  final String recipeName;

  /// The CURRENT revision's lines in stored order — the list position IS
  /// the stored line index the command addresses.
  final List<RecipeLine> currentLines;

  @override
  ConsumerState<AddToItemsSheet> createState() => _AddToItemsSheetState();
}

class _AddToItemsSheetState extends ConsumerState<AddToItemsSheet> {
  /// Folder for the recipe's own item; null = Unfiled.
  String? _recipeFolderId;

  /// Line indexes ticked in the "also add these" checklist.
  final Set<int> _chosen = {};

  /// Explicit per-line folder picks; a line without one follows
  /// [_recipeFolderId]. Wrapped in [FolderPick] so "picked Unfiled" is
  /// distinguishable from "never picked".
  final Map<int, FolderPick> _lineFolders = {};

  bool _busy = false;
  String? _error;

  /// (stored line index, line) for every unlinked line — linked lines are
  /// already items, so there is nothing to create for them.
  List<(int, RecipeLine)> get _freeLines => [
    for (var i = 0; i < widget.currentLines.length; i++)
      if (!widget.currentLines[i].isLinked) (i, widget.currentLines[i]),
  ];

  String? _folderIdForLine(int index) => _lineFolders.containsKey(index)
      ? _lineFolders[index]!.folderId
      : _recipeFolderId;

  Future<void> _pickRecipeFolder() async {
    final pick = await showFolderPickerSheet(
      context,
      selectedFolderId: _recipeFolderId,
    );
    if (pick != null && mounted) {
      setState(() => _recipeFolderId = pick.folderId);
    }
  }

  Future<void> _pickLineFolder(int index) async {
    final pick = await showFolderPickerSheet(
      context,
      selectedFolderId: _folderIdForLine(index),
    );
    if (pick != null && mounted) {
      setState(() => _lineFolders[index] = pick);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(recipeServiceProvider)
        .addToItems(
          recipeId: widget.recipeId,
          folderId: _recipeFolderId,
          ingredients: [
            for (final index in _chosen.toList()..sort())
              (lineIndex: index, folderId: _folderIdForLine(index)),
          ],
        );
    if (!mounted) return;
    switch (result) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final error):
        // Plain words, in the sheet, next to the button that failed.
        setState(() {
          _busy = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foldersById = <String, Folder>{
      for (final folder
          in ref.watch(folderListProvider).valueOrNull ?? const <Folder>[])
        folder.id.value: folder,
    };
    final freeLines = _freeLines;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.l,
            Space.l,
            Space.l,
            Space.m,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add to my items', style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.xs),
              Text(
                '“${widget.recipeName}” becomes an item you can count, '
                'forecast, and put on packing lists.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.s),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        key: const Key('add-folder-picker'),
                        contentPadding: EdgeInsets.zero,
                        leading: _FolderGlyph(
                          folder: switch (_recipeFolderId) {
                            final id? => foldersById[id],
                            null => null,
                          },
                        ),
                        title: Text(_folderName(_recipeFolderId, foldersById)),
                        subtitle: const Text('Folder for this recipe'),
                        trailing: const Icon(Icons.arrow_drop_down),
                        onTap: _busy ? null : _pickRecipeFolder,
                      ),
                      if (freeLines.isNotEmpty) ...[
                        const SizedBox(height: Space.s),
                        Text(
                          'Also add these as items',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'Ticked ingredients become items of their own '
                          '(and stay linked to this recipe). Unticked ones '
                          'stay as recipe text.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        for (final (index, line) in freeLines) ...[
                          CheckboxListTile(
                            key: ValueKey('add-line-$index'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _chosen.contains(index),
                            onChanged: _busy
                                ? null
                                : (checked) => setState(() {
                                    if (checked ?? false) {
                                      _chosen.add(index);
                                    } else {
                                      _chosen.remove(index);
                                    }
                                  }),
                            title: Text(line.name),
                            subtitle: Text(_amountCaption(line)),
                          ),
                          if (_chosen.contains(index))
                            Padding(
                              padding: const EdgeInsets.only(left: Space.xxl),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: ValueKey('line-folder-$index'),
                                  onPressed: _busy
                                      ? null
                                      : () => _pickLineFolder(index),
                                  icon: const Icon(
                                    Icons.folder_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Into ${_folderName(_folderIdForLine(index), foldersById)}',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.s),
                Text(
                  _error!,
                  key: const Key('add-to-items-error'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: Space.s),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('confirm-add-to-items'),
                    onPressed: _busy ? null : _confirm,
                    child: Text(
                      _chosen.isEmpty
                          ? 'Add to items'
                          : 'Add to items (+${_chosen.length} '
                                '${_chosen.length == 1 ? 'ingredient' : 'ingredients'})',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _folderName(String? folderId, Map<String, Folder> foldersById) =>
      switch (folderId) {
        final id? => foldersById[id]?.name ?? 'Unknown folder',
        null => 'Unfiled',
      };

  /// "0.5 cup per batch" — the line's amount with its display-only label.
  String _amountCaption(RecipeLine line) {
    final amount = QuantityCodec.format(line.quantityPerBatch);
    final unit = line.unitLabel;
    return '$amount${unit == null ? '' : ' $unit'} per batch';
  }
}

/// The folder identity chip for a picked folder, or the neutral inbox glyph
/// for Unfiled — the same visual language as the folder picker itself.
class _FolderGlyph extends StatelessWidget {
  const _FolderGlyph({required this.folder});

  final Folder? folder;

  @override
  Widget build(BuildContext context) {
    final folder = this.folder;
    if (folder != null) return FolderChip.forFolder(folder);
    return const Icon(Icons.inbox_outlined);
  }
}
