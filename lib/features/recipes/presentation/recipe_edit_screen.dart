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
///
/// v5 (recipe decoupling): a recipe no longer needs the item catalog AT
/// ALL. Each ingredient row is free text — a name, an amount (decimals and
/// fractions), and an optional display-only unit label entered with the
/// shared suggestion chips (`unit_label_suggestions.dart`, the same const
/// the item form uses). When a typed name exactly matches a live item
/// (case-insensitive), an optional per-row "link" affordance offers to
/// link the line to that item — never required, never forced. There is no
/// output-item picker on creation: a recipe is created standalone (name,
/// yield, lines); its output joins the item list later, only if the owner
/// asks ("Add to my items" on the detail screen).
///
/// Two proposal rules live here too: "Paste ingredients" opens the review
/// sheet (`ingredient_paste_sheet.dart`) whose confirmed rows are appended
/// as ordinary ingredient rows — nothing saves until this form is saved —
/// and sales-table-folder items (`recipe_catalog_filters.dart`) are never
/// offered as link targets: no recipe makes or consumes a CD.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_label_suggestions.dart';
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
import 'ingredient_paste_sheet.dart';
import 'recipe_catalog_filters.dart';

/// Canonical (const, so family-cached) filter. Archived items are included
/// so a prefilled line whose linked ingredient was archived since stays
/// resolvable (inline-flagged) instead of rendering as an unknown.
const _allItemsFilter = ItemFilter(includeArchived: true);

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

  /// The recipe's existing output binding (revise mode only; create mode is
  /// always standalone — the binding comes later via "Add to my items").
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
    _yieldController.text,
    _yieldLabelController.text,
    _noteController.text,
    for (final row in _rows)
      '${row.itemId ?? ''}:${row.nameController.text}:'
          '${row.unitController.text}:${row.quantityController.text}',
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

  _IngredientRow _newRow({
    String? itemId,
    String? name,
    String? unitLabel,
    Quantity? quantity,
  }) {
    final row = _IngredientRow(
      uid: _nextRowUid++,
      itemId: itemId,
      nameController: TextEditingController(text: name ?? ''),
      unitController: TextEditingController(text: unitLabel ?? ''),
      quantityController: TextEditingController(
        text: quantity == null ? '' : QuantityCodec.format(quantity),
      ),
    );
    // The unit suggestion chips show only for the focused row.
    row.unitFocus.addListener(_refresh);
    return row;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _prefillFrom(RecipeDetail detail) {
    _prefilled = true;
    _outputItemId = detail.recipe.outputItemId?.value;
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
          itemId: line.ingredientItemId?.value,
          name: line.name,
          unitLabel: line.unitLabel,
          quantity: line.quantityPerBatch,
        ),
      );
    }
    _pristine = _signature();
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(_isRevise ? 'Revise recipe' : 'New recipe');
    final items = ref.watch(itemListProvider(_allItemsFilter));
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
    // The catalog is only CONTEXT here (link matching, archived flags,
    // error-path names) — an EMPTY catalog is a perfectly good one: the
    // form never needs an item to exist. Gated alongside the sales-folder
    // set so a late emission can never flash a sales item into a link
    // affordance.
    final salesFolderIds = ref.watch(salesTableFolderIdsProvider);
    if (items.valueOrNull == null || salesFolderIds == null) {
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
    // Exact-name link targets: live items outside sales-table folders (no
    // recipe makes or consumes a CD). Live names are unique, so the map is
    // collision-free.
    final linkTargetsByName = <String, Item>{
      for (final summary in items.value!)
        if (!summary.item.isArchived &&
            !salesFolderIds.contains(summary.item.folderId?.value))
          summary.item.name.trim().toLowerCase(): summary.item,
    };
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
                  // v5: only a recipe that is already in the items list has
                  // an output item, and only revise mode can see one.
                  if (_isRevise && _outputItemId != null) ...[
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
                    ),
                    const SizedBox(height: 16),
                  ],
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
                          allowFractions: true,
                          labelText: 'How many one batch makes',
                          requiredMessage: 'Enter how many one batch makes',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const Key('recipe-yield-label'),
                          controller: _yieldLabelController,
                          decoration: const InputDecoration(
                            labelText: 'What a batch is called (optional)',
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
                  const SizedBox(height: 4),
                  Text(
                    'Type what goes in — amounts take decimals and '
                    'fractions ("1 1/2"). Linking to your items is optional.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                      linkTargetsByName: linkTargetsByName,
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('add-ingredient'),
                        onPressed: () => setState(() {
                          _rows.add(_newRow());
                          _showLinesError = false;
                        }),
                        icon: const Icon(Icons.add),
                        label: const Text('Add ingredient'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('paste-ingredients'),
                        onPressed: _pasteIngredients,
                        icon: const Icon(Icons.content_paste_outlined),
                        label: const Text('Paste ingredients'),
                      ),
                    ],
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

  /// The confirmed rows from the paste sheet, appended as ordinary
  /// ingredient rows. A single pristine empty starter row is replaced, not
  /// kept as noise. The sheet creates NOTHING — matched rows arrive linked,
  /// the rest arrive as free rows; every row keeps its own pasted text and
  /// parsed unit, and nothing saves until the Save button.
  Future<void> _pasteIngredients() async {
    final added = await showIngredientPasteSheet(context);
    if (added == null || added.isEmpty || !mounted) return;
    setState(() {
      if (_rows.length == 1 && _rows.first.isBlank) {
        _removeRow(_rows.first);
      }
      for (final entry in added) {
        _rows.add(
          _newRow(
            itemId: entry.itemId,
            name: entry.name,
            unitLabel: entry.unitLabel,
            quantity: entry.quantityPerBatch,
          ),
        );
      }
      _showLinesError = false;
    });
  }

  void _removeRow(_IngredientRow row) {
    _rows.remove(row);
    row.unitFocus.removeListener(_refresh);
    row.dispose();
  }

  /// The live item an unlinked row's typed name exactly matches (case-
  /// insensitive), if that item is not already linked on another row —
  /// the target of the per-row "link" affordance.
  Item? _linkCandidate(
    _IngredientRow row,
    Map<String, Item> linkTargetsByName,
  ) {
    if (row.itemId != null) return null;
    final typed = row.nameController.text.trim().toLowerCase();
    if (typed.isEmpty) return null;
    final item = linkTargetsByName[typed];
    if (item == null) return null;
    if (_rows.any((other) => other.itemId == item.id.value)) return null;
    return item;
  }

  Widget _buildIngredientRow(
    BuildContext context,
    int index, {
    required Map<String, Item> itemsById,
    required Map<String, Item> linkTargetsByName,
  }) {
    final theme = Theme.of(context);
    final row = _rows[index];
    final linkedItem = row.itemId == null ? null : itemsById[row.itemId];
    final candidate = _linkCandidate(row, linkTargetsByName);
    return Padding(
      key: ValueKey('ingredient-row-${row.uid}'),
      padding: const EdgeInsets.only(bottom: 16),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: ValueKey('ingredient-name-${row.uid}'),
                  controller: row.nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Ingredient',
                    border: OutlineInputBorder(),
                  ),
                  // Re-evaluate the link affordance as the name is typed.
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final trimmed = (value ?? '').trim();
                    if (row.itemId == null && trimmed.isEmpty) {
                      return 'Enter an ingredient name';
                    }
                    if (trimmed.length > 120) {
                      return 'Keep it under 120 characters';
                    }
                    if (row.itemId != null) {
                      // Flag duplicates on the later row only: the first
                      // occurrence stays valid, the repeat gets the error.
                      if (_rows
                          .take(_rows.indexOf(row))
                          .any((other) => other.itemId == row.itemId)) {
                        return 'Already in this recipe';
                      }
                      if (itemsById[row.itemId]?.isArchived ?? false) {
                        return 'This linked item is archived';
                      }
                    }
                    return null;
                  },
                ),
                if (row.itemId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.link,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Linked to “${linkedItem?.name ?? row.nameController.text.trim()}”',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          key: ValueKey('unlink-line-${row.uid}'),
                          onPressed: () => setState(() => row.itemId = null),
                          child: const Text('Unlink'),
                        ),
                      ],
                    ),
                  )
                else if (candidate != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: ValueKey('link-line-${row.uid}'),
                      onPressed: () =>
                          setState(() => row.itemId = candidate.id.value),
                      icon: const Icon(Icons.link, size: 18),
                      label: Text('Link to your item “${candidate.name}”'),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: QuantityFormField(
                        key: ValueKey('ingredient-qty-${row.uid}'),
                        controller: row.quantityController,
                        allowFractions: true,
                        labelText: 'Per batch',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('ingredient-unit-${row.uid}'),
                        controller: row.unitController,
                        focusNode: row.unitFocus,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(unitLabelMaxLength),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Unit (optional)',
                          hintText: 'cup, lbs…',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                // The shared suggestion chips, shown for the focused row
                // only. A convenience keyboard, not a managed list — the
                // field stays free text.
                if (row.unitFocus.hasFocus)
                  Padding(
                    key: ValueKey('unit-suggestions-${row.uid}'),
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: unitLabelSuggestions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, chipIndex) {
                          final label = unitLabelSuggestions[chipIndex];
                          return ActionChip(
                            label: Text(label),
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                setState(() => row.unitController.text = label),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('remove-ingredient-${row.uid}'),
            tooltip: 'Remove ingredient',
            padding: const EdgeInsets.only(top: 12),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => setState(() => _removeRow(row)),
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
    final yieldLabel = _yieldLabelController.text.trim();
    final draft = RecipeFormDraft(
      name: _nameController.text.trim(),
      outputItemId: _outputItemId,
      yieldQuantity: QuantityFormField.tryParse(_yieldController.text)!,
      yieldLabel: yieldLabel.isEmpty ? null : yieldLabel,
      note: _noteController.text.trim(),
      lines: [
        for (final row in _rows)
          RecipeFormLine(
            itemId: row.itemId,
            name: row.trimmedName.isEmpty ? null : row.trimmedName,
            unitLabel: row.trimmedUnit.isEmpty ? null : row.trimmedUnit,
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
    required this.nameController,
    required this.unitController,
    required this.quantityController,
  });

  final int uid;

  /// Optional catalog link (v5): set by the per-row link affordance or a
  /// matched paste line; null = free line standing on its own text.
  String? itemId;

  final TextEditingController nameController;
  final TextEditingController unitController;
  final TextEditingController quantityController;

  /// Drives the per-row unit suggestion chips.
  final FocusNode unitFocus = FocusNode();

  String get trimmedName => nameController.text.trim();

  String get trimmedUnit => unitController.text.trim();

  /// A pristine starter row (nothing typed, nothing linked).
  bool get isBlank =>
      itemId == null &&
      trimmedName.isEmpty &&
      trimmedUnit.isEmpty &&
      quantityController.text.trim().isEmpty;

  void dispose() {
    nameController.dispose();
    unitController.dispose();
    quantityController.dispose();
    unitFocus.dispose();
  }
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
    // An output-less (not-in-items) recipe contributes an empty id to the
    // path; drop it rather than render a dangling arrow.
    if (err is RecipeNestingError && err.path.isNotEmpty) {
      final path = err.path
          .where((id) => id.isNotEmpty)
          .map(_labelFor)
          .join(' → ');
      return 'Recipes stay flat in this version — ${err.message}: $path. '
          'Use the base items directly, or archive the other recipe first.';
    }
    if (err is RecipeCycleError && err.path.isNotEmpty) {
      final path = err.path
          .where((id) => id.isNotEmpty)
          .map(_labelFor)
          .join(' → ');
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
