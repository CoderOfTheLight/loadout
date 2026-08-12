/// §9 `/recipes/new` + `/recipes/:recipeId/revise` — RecipeEditScreen.
///
/// This manual form IS the Gate 5 OCR fallback: OCR will prefill this same
/// form as an unapproved proposal, so it is built complete now. Create mode
/// (`recipeId == null`) writes a recipe + revision 1; revise mode prefills
/// from the latest revision and APPENDS immutable revision N+1 — editing a
/// stored revision is impossible by design, the form always appends
/// (`RecipeService.createRecipe` / `reviseRecipe`; the validator runs
/// `assertFlat` / `detectCycles` and enforces one live recipe per output
/// item).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../core/errors.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/result.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/item.dart';
import '../application/recipe_service.dart';
import '../domain/recipe_drafts.dart';

/// Canonical (const, so family-cached) picker filter. Archived items are
/// included so a prefilled line whose ingredient was archived since stays
/// visible (inline-flagged) instead of crashing the picker.
const _pickerFilter = ItemFilter(includeArchived: true);

class RecipeEditScreen extends ConsumerStatefulWidget {
  const RecipeEditScreen({super.key, this.recipeId});

  /// Null = create (recipe + revision 1); otherwise revise = append
  /// immutable revision N+1 prefilled from the latest revision.
  final String? recipeId;

  @override
  ConsumerState<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends ConsumerState<RecipeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _yieldController = TextEditingController();
  final _yieldLabelController = TextEditingController();
  final _noteController = TextEditingController();
  final List<_IngredientRow> _rows = [];

  String? _outputItemId;
  bool _prefilled = false;
  bool _submitting = false;
  bool _showLinesError = false;
  DomainError? _submitError;
  int _nextRevision = 1;
  int _nextRowUid = 0;

  /// Form contents when editing began; the back guard compares against it.
  /// This is the app's longest form and it has no autosave, so popping it
  /// unguarded discards everything typed.
  String? _pristine;
  bool _saved = false;

  bool get _isRevise => widget.recipeId != null;

  bool get _dirty => !_saved && _pristine != null && _signature() != _pristine;

  String _signature() => [
    _nameController.text,
    _outputItemId ?? '',
    _yieldController.text,
    _yieldLabelController.text,
    _noteController.text,
    for (final row in _rows)
      '${row.itemId ?? ''}:${row.quantityController.text}',
  ].join('\u0000');

  @override
  void initState() {
    super.initState();
    if (!_isRevise) {
      // Start pleasant: one empty ingredient row ready to fill.
      _rows.add(_newRow());
      _pristine = _signature();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yieldController.dispose();
    _yieldLabelController.dispose();
    _noteController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  _IngredientRow _newRow({String? itemId, Quantity? quantity}) =>
      _IngredientRow(
        uid: _nextRowUid++,
        itemId: itemId,
        quantityController: TextEditingController(
          text: quantity == null ? '' : QuantityCodec.format(quantity),
        ),
      );

  void _prefillFrom(RecipeDetail detail) {
    _prefilled = true;
    _outputItemId = detail.recipe.outputItemId.value;
    _nameController.text = detail.recipe.name;
    if (detail.revisions.isEmpty) return;
    final latest = detail.revisions.first; // newest first
    _nextRevision = latest.revision + 1;
    _yieldController.text = QuantityCodec.format(latest.yieldQuantity);
    _yieldLabelController.text = latest.yieldLabel ?? '';
    _noteController.text = latest.note;
    for (final line in latest.lines) {
      _rows.add(
        _newRow(
          itemId: line.ingredientItemId.value,
          quantity: line.quantityPerBatch,
        ),
      );
    }
    _pristine = _signature();
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(_isRevise ? 'Revise recipe' : 'New recipe');
    final items = ref.watch(itemListProvider(_pickerFilter));
    final recipeNamesById = <String, String>{
      for (final summary
          in ref.watch(recipeListProvider).valueOrNull ??
              const <RecipeSummary>[])
        summary.id: summary.name,
    };
    if (_isRevise && !_prefilled) {
      final detail = ref.watch(recipeDetailProvider(widget.recipeId!));
      if (detail.hasError) {
        return Scaffold(
          appBar: AppBar(title: title),
          body: const Center(child: Text("Couldn't load this recipe.")),
        );
      }
      final value = detail.valueOrNull;
      if (value == null) {
        return Scaffold(
          appBar: AppBar(title: title),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      _prefillFrom(value);
    }
    if (items.valueOrNull == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: items.hasError
            ? const Center(child: Text("Couldn't load the item catalog."))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final itemsById = <String, Item>{
      for (final summary in items.value!) summary.item.id.value: summary.item,
    };
    final liveItems = [
      for (final summary in items.value!)
        if (!summary.item.isArchived) summary.item,
    ];
    final outputItem = _outputItemId == null ? null : itemsById[_outputItemId];
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: title),
        body: SingleChildScrollView(
          child: ContentColumn(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isRevise) ...[
                    _InfoNote(
                      message:
                          'Revisions are permanent. Saving adds revision '
                          '$_nextRevision on top; earlier revisions never '
                          'change.',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_submitError != null) ...[
                    _SubmitErrorBanner(
                      error: _submitError!,
                      itemsById: itemsById,
                      recipeNamesById: recipeNamesById,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_isRevise)
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Output item',
                        helperText:
                            'Fixed for this recipe — revisions change the '
                            'method, not the output.',
                        border: OutlineInputBorder(),
                        enabled: false,
                      ),
                      child: Text(outputItem?.name ?? 'Unknown item'),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('output-item-picker'),
                      initialValue: _outputItemId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Output item',
                        helperText: 'What one batch of this recipe makes',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final item in liveItems)
                          DropdownMenuItem(
                            value: item.id.value,
                            child: Text(
                              '${item.name} · ${item.unit.dbValue}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _outputItemId = value),
                      validator: (value) =>
                          value == null ? 'Choose the output item' : null,
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('recipe-name'),
                    controller: _nameController,
                    enabled: !_isRevise,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Recipe name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final trimmed = (value ?? '').trim();
                      if (trimmed.isEmpty || trimmed.length > 120) {
                        return 'Enter a name (up to 120 characters)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: QuantityFormField(
                          key: const Key('recipe-yield'),
                          controller: _yieldController,
                          labelText: 'Yield per batch',
                          unitLabel: outputItem?.unit.dbValue,
                          requiredMessage: 'Enter the yield',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const Key('recipe-yield-label'),
                          controller: _yieldLabelController,
                          decoration: const InputDecoration(
                            labelText: 'Yield label (optional)',
                            hintText: 'e.g. 12 tacos',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Ingredients per batch',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _rows.length,
                    // onReorderItem already adjusts newIndex for the removal.
                    onReorderItem: (oldIndex, newIndex) => setState(() {
                      _rows.insert(newIndex, _rows.removeAt(oldIndex));
                    }),
                    itemBuilder: (context, index) => _buildIngredientRow(
                      context,
                      index,
                      itemsById: itemsById,
                      liveItems: liveItems,
                    ),
                  ),
                  if (_showLinesError && _rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Add at least one ingredient.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('add-ingredient'),
                      onPressed: () => setState(() {
                        _rows.add(_newRow());
                        _showLinesError = false;
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add ingredient'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('recipe-note'),
                    controller: _noteController,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Method, prep reminders, allergens…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('save-recipe'),
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: Text(
                      _isRevise
                          ? 'Save as revision $_nextRevision'
                          : 'Save recipe',
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this recipe?'),
        content: const Text('Nothing has been saved yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _saved = true; // stop the guard re-asking on the way out
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  Widget _buildIngredientRow(
    BuildContext context,
    int index, {
    required Map<String, Item> itemsById,
    required List<Item> liveItems,
  }) {
    final row = _rows[index];
    // Options: live items except the output item — plus the row's current
    // value when it is not among them (archived item or output collision),
    // so the picker stays renderable and the validator can flag it inline.
    final options = [
      for (final item in liveItems)
        if (item.id.value != _outputItemId) item,
    ];
    final current = row.itemId;
    if (current != null && !options.any((item) => item.id.value == current)) {
      final item = itemsById[current];
      if (item != null) options.add(item);
    }
    final selected = current == null ? null : itemsById[current];
    return Padding(
      key: ValueKey('ingredient-row-${row.uid}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Reorder ingredient ${index + 1}',
            child: ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(top: 16, right: 4),
                child: Icon(Icons.drag_indicator),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<String>(
              key: ValueKey('ingredient-item-${row.uid}'),
              initialValue: current,
              isExpanded: true,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Ingredient',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final item in options)
                  DropdownMenuItem(
                    value: item.id.value,
                    child: Text(
                      item.isArchived ? '${item.name} (archived)' : item.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => row.itemId = value),
              validator: (value) {
                if (value == null) return 'Choose an ingredient';
                if (value == _outputItemId) {
                  return 'This is the output item';
                }
                // Flag duplicates on the later row only: the first
                // occurrence stays valid, the repeat gets the error.
                if (_rows
                    .take(_rows.indexOf(row))
                    .any((other) => other.itemId == value)) {
                  return 'Already in this recipe';
                }
                if (itemsById[value]?.isArchived ?? false) {
                  return 'This item is archived';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: QuantityFormField(
              key: ValueKey('ingredient-qty-${row.uid}'),
              controller: row.quantityController,
              labelText: 'Per batch',
              unitLabel: selected?.unit.dbValue,
            ),
          ),
          IconButton(
            key: ValueKey('remove-ingredient-${row.uid}'),
            tooltip: 'Remove ingredient',
            padding: const EdgeInsets.only(top: 12),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => setState(() => _rows.removeAt(index).dispose()),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitError = null;
      _showLinesError = _rows.isEmpty;
    });
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _rows.isEmpty) return;
    final outputItemId = _outputItemId;
    if (outputItemId == null) return; // picker validator already flagged it
    final yieldLabel = _yieldLabelController.text.trim();
    final draft = RecipeFormDraft(
      name: _nameController.text.trim(),
      outputItemId: outputItemId,
      yieldQuantity: QuantityFormField.tryParse(_yieldController.text)!,
      yieldLabel: yieldLabel.isEmpty ? null : yieldLabel,
      note: _noteController.text.trim(),
      lines: [
        for (final row in _rows)
          RecipeFormLine(
            itemId: row.itemId!,
            quantityPerBatch: QuantityFormField.tryParse(
              row.quantityController.text,
            )!,
          ),
      ],
    );
    setState(() => _submitting = true);
    final service = ref.read(recipeServiceProvider);
    final Result<Object?> result = _isRevise
        ? await service.reviseRecipe(recipeId: widget.recipeId!, draft: draft)
        : await service.createRecipe(draft);
    if (!mounted) return;
    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isRevise ? 'Revision $_nextRevision saved' : 'Recipe saved',
            ),
          ),
        );
        _saved = true;
        _close();
      case Err(:final error):
        setState(() {
          _submitting = false;
          _submitError = error;
        });
    }
  }

  void _close() {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.of(context).maybePop();
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go('/recipes');
    }
  }
}

final class _IngredientRow {
  _IngredientRow({
    required this.uid,
    this.itemId,
    required this.quantityController,
  });

  final int uid;
  String? itemId;
  final TextEditingController quantityController;

  void dispose() => quantityController.dispose();
}

/// Submit-failure banner. Domain validator messages are content-free by
/// design (§10), so they can be shown verbatim; a [RecipeNestingError]
/// additionally narrates its path with resolved names so the rejected
/// reference is clear.
class _SubmitErrorBanner extends StatelessWidget {
  const _SubmitErrorBanner({
    required this.error,
    required this.itemsById,
    required this.recipeNamesById,
  });

  final DomainError error;
  final Map<String, Item> itemsById;
  final Map<String, String> recipeNamesById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _message {
    final err = error;
    if (err is RecipeNestingError && err.path.isNotEmpty) {
      final path = err.path.map(_labelFor).join(' → ');
      return 'Recipes stay flat in this version — ${err.message}: $path. '
          'Use the base items directly, or archive the other recipe first.';
    }
    if (err is RecipeCycleError && err.path.isNotEmpty) {
      final path = err.path.map(_labelFor).join(' → ');
      return '${err.message}: $path';
    }
    return err.message;
  }

  String _labelFor(String id) {
    final item = itemsById[id];
    if (item != null) return item.name;
    final recipeName = recipeNamesById[id];
    if (recipeName != null) return "recipe '$recipeName'";
    return id;
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.history_edu_outlined,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
