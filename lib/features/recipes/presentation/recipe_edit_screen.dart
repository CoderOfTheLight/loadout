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
/// fractions), and an optional display-only unit label. When a typed name
/// exactly matches a live item (case-insensitive), an optional "link"
/// affordance offers to link the line to that item — never required, never
/// forced. There is no output-item picker on creation: a recipe is created
/// standalone (name, yield, lines); its output joins the item list later,
/// only if the owner asks ("Add to my items" on the detail screen).
///
/// ONE ROW IS ONE LINE (owner feedback: five ingredients used to span three
/// screens). The row carries exactly three controls — name, amount, unit —
/// and nothing else. Everything that is not typing lives behind the row's
/// overflow: link, unlink, remove. Reordering is a long press on the row
/// itself (`ReorderableListView`'s own delayed drag delegate), so no drag
/// handle competes for width. A linked row says so with a small link mark
/// inside the name field; the verb for it is in the overflow. On a viewport
/// too narrow for three fields abreast — a 320 dp phone, or any phone at
/// large text scale — the row folds to name-above-amount+unit rather than
/// squeezing or overflowing.
///
/// Two proposal rules live here too: "Paste ingredients" opens the review
/// sheet (`ingredient_paste_sheet.dart`) whose confirmed rows are appended
/// as ordinary ingredient rows — nothing saves until this form is saved —
/// and sales-table-folder items (`recipe_catalog_filters.dart`) are never
/// offered as link targets: no recipe makes or consumes a CD.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_label_suggestions.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/form_action_bar.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../core/errors.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/result.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/item.dart';
import '../application/recipe_ocr_service.dart';
import '../application/recipe_service.dart';
import '../domain/recipe.dart';
import '../domain/recipe_drafts.dart';
import 'ingredient_paste_sheet.dart';
import 'ocr_text_normalizer.dart';
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

  /// OCR capability probes (read once in initState; false until answered).
  /// The scan affordance shows when either is true.
  bool _cameraScanAvailable = false;
  bool _photoPickAvailable = false;

  /// True once any OCR capture landed rows on the form: the saved revision
  /// then records `source_kind = 'ocr'` (Gate 5 provenance).
  bool _usedScanner = false;

  bool get _isRevise => widget.recipeId != null;

  bool get _dirty => !_saved && _pristine != null && _signature() != _pristine;

  String _signature() => [
    _nameController.text,
    _yieldController.text,
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
    unawaited(_probeOcrAvailability());
  }

  /// Reads both OCR probes once. Availability is a capability, not an
  /// error: the scan button simply stays hidden until a probe says yes.
  Future<void> _probeOcrAvailability() async {
    final ocr = ref.read(recipeOcrServiceProvider);
    final camera = await ocr.isCameraScanAvailable();
    final photo = await ocr.isPhotoPickAvailable();
    if (!mounted) return;
    setState(() {
      _cameraScanAvailable = camera;
      _photoPickAvailable = photo;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yieldController.dispose();
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
  }) => _IngredientRow(
    uid: _nextRowUid++,
    itemId: itemId,
    nameController: TextEditingController(text: name ?? ''),
    unitController: TextEditingController(text: unitLabel ?? ''),
    quantityController: TextEditingController(
      text: quantity == null ? '' : QuantityCodec.format(quantity),
    ),
  );

  void _prefillFrom(RecipeDetail detail) {
    _prefilled = true;
    _outputItemId = detail.recipe.outputItemId?.value;
    _nameController.text = detail.recipe.name;
    if (detail.revisions.isEmpty) return;
    final latest = detail.revisions.first; // newest first
    _nextRevision = latest.revision + 1;
    _yieldController.text = QuantityCodec.format(latest.yieldQuantity);
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
                  // The "revisions are permanent" warning is NOT on the
                  // form: it is a fact about SAVING, so it lives in the
                  // save confirmation ([_confirmRevision]) where it is read
                  // at the only moment it can still change a decision.
                  if (_submitError != null) ...[
                    _SubmitErrorBanner(
                      error: _submitError!,
                      itemsById: itemsById,
                      recipeNamesById: recipeNamesById,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    key: const Key('recipe-name'),
                    controller: _nameController,
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
                  QuantityFormField(
                    key: const Key('recipe-yield'),
                    controller: _yieldController,
                    allowFractions: true,
                    labelText: 'Yield',
                    requiredMessage: 'Enter the yield',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Ingredients per batch',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Amounts take decimals and fractions, like "1 1/2".',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    // Long-press to reorder: Flutter's own delayed drag
                    // delegate on mobile. The row keeps its full width for
                    // the three fields that matter.
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
                      if (_cameraScanAvailable || _photoPickAvailable)
                        OutlinedButton.icon(
                          key: const Key('scan-recipe'),
                          onPressed: _scanRecipe,
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: const Text('Scan a recipe'),
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
                ],
              ),
            ),
          ),
        ),
        // The app's form grammar: the primary action pinned where every
        // other form in Loadout puts it, always reachable without scrolling
        // to the bottom of a long ingredient list.
        bottomNavigationBar: FormActionBar(
          child: FilledButton(
            key: const Key('save-recipe'),
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            onPressed: _submitting ? null : _submit,
            child: Text(
              _isRevise ? 'Save as revision $_nextRevision' : 'Save recipe',
              textAlign: TextAlign.center,
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

  Future<void> _pasteIngredients() => _reviewIngredients();

  /// The one "open the review sheet with this text" path both producers
  /// share: paste opens the sheet blank ([initialText] null), OCR hands its
  /// surviving lines in and the sheet opens straight on the review stage.
  /// Confirmed rows are appended as ordinary ingredient rows; a single
  /// pristine empty starter row is replaced, not kept as noise. The sheet
  /// creates NOTHING — matched rows arrive linked, the rest arrive as free
  /// rows; every row keeps its own text and parsed unit, and nothing saves
  /// until the Save button. Returns true when any row landed.
  Future<bool> _reviewIngredients({String? initialText}) async {
    final added = await showIngredientPasteSheet(
      context,
      initialText: initialText,
    );
    if (added == null || added.isEmpty || !mounted) return false;
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
    return true;
  }

  /// 'Scan a recipe': picks the capture path (a labeled chooser when both
  /// camera and photo are available, straight to the only one otherwise),
  /// runs it, and feeds the recognized lines into the same review sheet
  /// [_pasteIngredients] uses.
  Future<void> _scanRecipe() async {
    final ocr = ref.read(recipeOcrServiceProvider);
    final Future<RecipeOcrCapture?> Function() capture;
    if (_cameraScanAvailable && _photoPickAvailable) {
      final source = await showModalBottomSheet<_ScanSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('scan-take-photo'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(context).pop(_ScanSource.camera),
              ),
              ListTile(
                key: const Key('scan-choose-photo'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose a photo'),
                onTap: () => Navigator.of(context).pop(_ScanSource.photo),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;
      capture = source == _ScanSource.camera
          ? ocr.scanWithCamera
          : ocr.pickPhoto;
    } else {
      capture = _cameraScanAvailable ? ocr.scanWithCamera : ocr.pickPhoto;
    }
    await _captureAndReview(capture);
  }

  /// Runs one capture behind a blocking in-app progress state (the native
  /// side presents its own full-screen UI), then normalizes, pre-filters,
  /// and reviews the recognized lines. Content privacy: recognized text
  /// goes to the review sheet and NOWHERE else — never a log, never an
  /// error message.
  Future<void> _captureAndReview(
    Future<RecipeOcrCapture?> Function() capture,
  ) async {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );
    RecipeOcrCapture? result;
    var failed = false;
    try {
      result = await capture();
    } on RecipeOcrException {
      failed = true; // code deliberately unread: content-free either way
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // the progress dialog
    if (failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't read that photo. Try again.")),
      );
      return;
    }
    if (result == null) return; // owner cancelled: do nothing
    final lines = filterOcrIngredientLines([
      for (final line in result.lines) normalizeOcrLine(line),
    ]);
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No text found in that photo.')),
      );
      return;
    }
    final landed = await _reviewIngredients(initialText: lines.join('\n'));
    if (landed) {
      _usedScanner = true;
    }
  }

  void _removeRow(_IngredientRow row) {
    _rows.remove(row);
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

  /// One ingredient: THREE controls on one line — name, amount, unit — plus
  /// the overflow that holds every verb (link, unlink, remove). Nothing
  /// else. The row folds to two lines only when three fields abreast would
  /// not fit (narrow phone, or large text scale).
  Widget _buildIngredientRow(
    BuildContext context,
    int index, {
    required Map<String, Item> itemsById,
    required Map<String, Item> linkTargetsByName,
  }) {
    final theme = Theme.of(context);
    final row = _rows[index];
    final linked = row.itemId != null;
    final candidate = _linkCandidate(row, linkTargetsByName);

    final name = TextFormField(
      key: ValueKey('ingredient-name-${row.uid}'),
      controller: row.nameController,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Ingredient',
        border: const OutlineInputBorder(),
        // The link is an INDICATOR, not a control — the verb for it is in
        // the row's overflow. Tooltip carries its meaning to a screen
        // reader, so the mark is never colour-only.
        prefixIcon: linked
            ? Tooltip(
                message: 'Linked to one of your items',
                child: Icon(
                  Icons.link,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              )
            : null,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 24,
        ),
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
          // Flag duplicates on the later row only: the first occurrence
          // stays valid, the repeat gets the error.
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
    );

    final amount = QuantityFormField(
      key: ValueKey('ingredient-qty-${row.uid}'),
      controller: row.quantityController,
      allowFractions: true,
      labelText: 'Amount',
    );

    final unit = TextFormField(
      key: ValueKey('ingredient-unit-${row.uid}'),
      controller: row.unitController,
      inputFormatters: [LengthLimitingTextInputFormatter(unitLabelMaxLength)],
      decoration: const InputDecoration(
        labelText: 'Unit',
        hintText: 'cup, bag',
        border: OutlineInputBorder(),
      ),
    );

    final overflow = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: PopupMenuButton<_RowAction>(
        key: ValueKey('ingredient-menu-${row.uid}'),
        tooltip: 'Ingredient ${index + 1} options',
        padding: const EdgeInsets.all(12),
        onSelected: (action) => _applyRowAction(row, action, candidate),
        itemBuilder: (_) => [
          if (linked)
            PopupMenuItem(
              key: ValueKey('unlink-line-${row.uid}'),
              value: _RowAction.unlink,
              child: const Text('Unlink from item'),
            ),
          if (candidate != null)
            PopupMenuItem(
              key: ValueKey('link-line-${row.uid}'),
              value: _RowAction.link,
              child: Text('Link to your item “${candidate.name}”'),
            ),
          PopupMenuItem(
            key: ValueKey('remove-ingredient-${row.uid}'),
            value: _RowAction.remove,
            child: const Text('Remove ingredient'),
          ),
        ],
      ),
    );

    return Padding(
      key: ValueKey('ingredient-row-${row.uid}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Three labelled fields need roughly 280 dp of type; scale that
          // by the reader's own text size rather than guessing a breakpoint
          // in device pixels.
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          if (constraints.maxWidth >= 280 * scale) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: name),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: amount),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: unit),
                overflow,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              name,
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: amount),
                  const SizedBox(width: 8),
                  Expanded(child: unit),
                  overflow,
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _applyRowAction(_IngredientRow row, _RowAction action, Item? candidate) {
    setState(() {
      switch (action) {
        case _RowAction.link:
          if (candidate != null) row.itemId = candidate.id.value;
        case _RowAction.unlink:
          row.itemId = null;
        case _RowAction.remove:
          _removeRow(row);
      }
    });
  }

  /// The revise warning, at the only moment it can still change a decision.
  /// It used to sit at the top of the form, above everything the owner came
  /// here to type, where it was read once and never again.
  Future<bool> _confirmRevision() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Save revision $_nextRevision?'),
        content: Text(
          'Revisions are permanent. This adds revision $_nextRevision on '
          'top; earlier revisions never change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const Key('confirm-revision'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Save revision $_nextRevision'),
          ),
        ],
      ),
    );
    return go == true && mounted;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitError = null;
      _showLinesError = _rows.isEmpty;
    });
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _rows.isEmpty) return;
    if (_isRevise && !await _confirmRevision()) return;
    final draft = RecipeFormDraft(
      name: _nameController.text.trim(),
      outputItemId: _outputItemId,
      yieldQuantity: QuantityFormField.tryParse(_yieldController.text)!,
      yieldLabel: null,
      note: _noteController.text.trim(),
      // Provenance (both create and revise): any landed OCR capture marks
      // the revision as scanned.
      sourceKind: _usedScanner ? RecipeSourceKind.ocr : RecipeSourceKind.form,
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

/// Which capture path the 'Scan a recipe' chooser picked.
enum _ScanSource { camera, photo }

/// The verbs behind an ingredient row's overflow. Everything that is not
/// typing lives here, so the row itself stays three fields wide.
enum _RowAction { link, unlink, remove }

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
    // path; drop it rather than render a dangling link.
    if (err is RecipeNestingError && err.path.isNotEmpty) {
      return 'Recipes stay flat in this version — ${err.message}: '
          '${_path(err.path)}. Use the base items directly, or archive the '
          'other recipe first.';
    }
    if (err is RecipeCycleError && err.path.isNotEmpty) {
      return '${err.message}: ${_path(err.path)}';
    }
    return err.message;
  }

  /// The rejected chain in words. An arrow glyph used to join these and it
  /// rendered as an empty box in the app's font — a path nobody could read.
  String _path(List<String> ids) =>
      ids.where((id) => id.isNotEmpty).map(_labelFor).join(' then ');

  String _labelFor(String id) {
    final item = itemsById[id];
    if (item != null) return item.name;
    final recipeName = recipeNamesById[id];
    if (recipeName != null) return "recipe '$recipeName'";
    return id;
  }
}
