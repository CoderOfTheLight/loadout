/// `/items/new` and `/items/:itemId/edit` (design §9 ItemEditScreen).
///
/// Name (required, live unique-among-live check), unit (`DropdownMenu`,
/// closed list each/g/kg/ml/L — read-only in edit mode once the item has
/// any movement, helper explains archive+recreate), pack size
/// (`QuantityFormField`, required > 0), category (free text + autocomplete
/// over `categorySuggestions`), notes. Commands:
/// `CatalogService.createItem` / `updateItem` — plain updates, no revision
/// log. Once locked, the stored unit is always resubmitted verbatim; a
/// racing IMMUTABLE_RECORD from the applier surfaces the same
/// archive+recreate explanation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../core/errors.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/result.dart';
import '../../../core/units.dart';
import '../application/catalog_service.dart';
import '../domain/item.dart';
import 'catalog_providers.dart';
import '../../../app/widgets/form_action_bar.dart';

/// The §9 unit-lock explanation, shown as dropdown helper text when locked
/// and as the IMMUTABLE_RECORD snackbar (content-free by design).
const String unitLockedExplanation =
    'Unit is locked after the first movement. To change it, archive this '
    'item and create a new one.';

class ItemEditScreen extends ConsumerStatefulWidget {
  const ItemEditScreen({super.key, this.itemId});

  /// Null = create a new item; otherwise edit this one.
  final String? itemId;

  @override
  ConsumerState<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends ConsumerState<ItemEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _packSize = TextEditingController();
  final _notes = TextEditingController();
  String _category = '';
  ItemUnit _unit = ItemUnit.each;
  bool _hydrated = false;
  bool _dirty = false;
  bool _submitting = false;

  /// Lowercased name most recently rejected by the command validator
  /// (uniqueness); mirrored onto the name field inline.
  String? _rejectedDuplicateName;

  bool get _isEdit => widget.itemId != null;

  @override
  void dispose() {
    _name.dispose();
    _packSize.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  Future<void> _save(ItemDetail? detail) async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    final packSize = QuantityFormField.tryParse(_packSize.text);
    if (packSize == null) {
      return; // The field validator already rejected this.
    }
    final locked = detail?.hasMovements ?? false;
    final category = _category.trim();
    final draft = ItemDraft(
      name: _name.text.trim(),
      // §4 unit lock: once any movement exists the stored unit is always
      // resubmitted verbatim.
      unit: locked ? detail!.item.unit : _unit,
      packSize: packSize,
      category: category.isEmpty ? null : category,
      notes: _notes.text.trim(),
    );
    setState(() => _submitting = true);
    final service = ref.read(catalogServiceProvider);
    final Result<Object?> result = _isEdit
        ? await service.updateItem(itemId: widget.itemId!, draft: draft)
        : await service.createItem(draft);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        _dirty = false;
        // Plain pop: maybePop would consult the PopScope, whose canPop
        // still reflects the pre-save dirty state until the next build.
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          setState(() => _submitting = false);
        }
      case Err(:final error):
        setState(() => _submitting = false);
        if (error.message.contains('name already exists')) {
          setState(() => _rejectedDuplicateName = draft.name.toLowerCase());
          _formKey.currentState!.validate();
        } else if (error is ImmutableRecordError) {
          _showSnack(unitLockedExplanation);
        } else if (error.message.contains('archived')) {
          _showSnack('This item is archived. Unarchive it first.');
        } else {
          // Content-free by design (§9): no names or quantities in errors.
          _showSnack("Couldn't save this entry. Try again.");
        }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
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
      _dirty = false;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = _isEdit
        ? ref.watch(itemDetailProvider(widget.itemId!))
        : null;
    final detail = detailAsync?.valueOrNull;
    if (_isEdit && detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit item')),
        body: detailAsync!.hasError
            ? const EmptyState(
                message: 'This item is not available.',
                icon: Icons.error_outline,
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (_isEdit && !_hydrated) {
      // First build with data: the form fields below have not been built
      // yet, so seeding the controllers here is safe and happens once.
      _hydrated = true;
      final item = detail!.item;
      _name.text = item.name;
      _packSize.text = QuantityCodec.format(item.packSize);
      _notes.text = item.notes;
      _category = item.category ?? '';
      _unit = item.unit;
    }
    final locked = _isEdit && detail!.hasMovements;
    final nameIndex = ref.watch(liveItemNameIndexProvider);
    final suggestions =
        ref.watch(categorySuggestionsProvider).valueOrNull ?? const <String>[];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isEdit ? 'Edit item' : 'New item')),
        body: SafeArea(
          child: SingleChildScrollView(
            child: ContentColumn(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _markDirty(),
                      validator: (text) => _validateName(text, nameIndex),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      label: locked
                          ? 'Unit is locked after the first movement'
                          : null,
                      child: DropdownMenu<ItemUnit>(
                        enabled: !locked,
                        initialSelection: _unit,
                        requestFocusOnTap: false,
                        expandedInsets: EdgeInsets.zero,
                        label: const Text('Unit'),
                        helperText: locked
                            ? unitLockedExplanation
                            : 'One unit per item — no conversions.',
                        dropdownMenuEntries: [
                          for (final unit in ItemUnit.values)
                            DropdownMenuEntry(value: unit, label: unit.label),
                        ],
                        onSelected: (unit) {
                          if (unit != null) {
                            setState(() {
                              _unit = unit;
                              _dirty = true;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    QuantityFormField(
                      controller: _packSize,
                      labelText: 'Pack size',
                      requiredMessage: 'Enter a pack size',
                      unitLabel: _unit.dbValue,
                      helperText:
                          'How many ${_unit.dbValue} per pack you buy or '
                          'load — used for rounding',
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 24),
                    Autocomplete<String>(
                      initialValue: TextEditingValue(text: _category),
                      optionsBuilder: (value) {
                        final query = value.text.trim().toLowerCase();
                        if (query.isEmpty) {
                          return suggestions;
                        }
                        return suggestions.where(
                          (category) => category.toLowerCase().contains(query),
                        );
                      },
                      onSelected: (value) {
                        _category = value;
                        _markDirty();
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) =>
                              TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Category',
                                  helperText:
                                      'Optional — groups the item list.',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  _category = value;
                                  _markDirty();
                                },
                              ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: FormActionBar(
          child: FilledButton(
            onPressed: _submitting ? null : () => _save(detail),
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            child: _submitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Save item'),
          ),
        ),
      ),
    );
  }

  String? _validateName(String? text, Map<String, String> nameIndex) {
    final name = (text ?? '').trim();
    if (name.isEmpty) {
      return 'Enter a name';
    }
    if (name.length > 120) {
      return 'Keep the name under 120 characters';
    }
    final lower = name.toLowerCase();
    final owner = nameIndex[lower];
    if ((owner != null && owner != widget.itemId) ||
        lower == _rejectedDuplicateName) {
      return 'A live item with this name already exists.';
    }
    return null;
  }
}
