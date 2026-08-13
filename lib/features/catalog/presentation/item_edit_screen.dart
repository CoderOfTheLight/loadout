/// `/items/new` and `/items/:itemId/edit` — ItemEditScreen.
///
/// The owner's model of an item, in her words: NAME + HOW MANY YOU HAVE +
/// optionally HOW MANY PEOPLE ONE SERVES. So this form asks exactly that:
///
///   * **Item name** — required, live unique-among-live check. Something
///     sold by weight goes in the name ("Mince (500 g packs)") and is
///     counted as whole packs; the app never does weight arithmetic.
///   * **How many do you have?** — a plain whole number, create only. It
///     rides inside `CreateItem` as the opening `adjust` movement, so the
///     item and its count land in one transaction. On an existing item the
///     count is derived from the ledger and can only change by recording a
///     movement, so edit mode shows it read-only with a button to do that.
///   * **How many people does one serve?** — optional. Blank is an honest
///     answer and simply means a first-ever event gets no estimate.
///
/// No unit picker, no pack size: units left the product surface in schema
/// v2. A legacy row's stored unit and pack size are resubmitted verbatim so
/// a rename can never trip the §4 unit lock or silently restate what its
/// numbers mean.
///
/// Commands: `CatalogService.createItem` / `updateItem` — plain updates, no
/// revision log.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/count_form_field.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/form_action_bar.dart';
import '../../../core/errors.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/units.dart';
import '../domain/item.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';

/// Cap on "how many people does one serve?", mirroring the command
/// validator's `maxServesPerUnitMicros` (10 000 people per thing).
const int maxServesPerUnit = 10000;

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
  final _count = TextEditingController();
  final _serves = TextEditingController();
  final _notes = TextEditingController();
  String _category = '';
  bool _hydrated = false;
  bool _dirty = false;
  bool _submitting = false;

  /// Schema-v1 leftovers. Never shown, never asked, always resubmitted
  /// verbatim: changing a legacy item's unit after its first movement is an
  /// IMMUTABLE_RECORD, and rewriting its pack size would restate what its
  /// stored numbers mean.
  ItemUnit _unit = ItemUnit.each;
  Quantity _packSize = Quantity.one;

  /// Lowercased name most recently rejected by the command validator
  /// (uniqueness); mirrored onto the name field inline.
  String? _rejectedDuplicateName;

  bool get _isEdit => widget.itemId != null;

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    _serves.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  Future<void> _save() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    final category = _category.trim();
    final draft = ItemDraft(
      name: _name.text.trim(),
      servesPerUnit: CountFormField.tryParseQuantity(_serves.text),
      unit: _unit,
      packSize: _packSize,
      category: category.isEmpty ? null : category,
      notes: _notes.text.trim(),
    );
    setState(() => _submitting = true);
    final service = ref.read(catalogServiceProvider);
    final Result<Object?> result = _isEdit
        ? await service.updateItem(itemId: widget.itemId!, draft: draft)
        : await service.createItem(
            draft,
            openingCount:
                CountFormField.tryParseQuantity(_count.text) ?? Quantity.zero,
          );
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
          _showSnack(
            'Some of this item is already locked by its history. Archive it '
            'and add a new one instead.',
          );
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
      // This form is the only writer of serves-per-unit and only ever
      // writes whole people, so the truncation here is exact.
      _serves.text = switch (item.servesPerUnit) {
        final serves? => CountFormField.format(serves.micros ~/ Quantity.scale),
        null => '',
      };
      _notes.text = item.notes;
      _category = item.category ?? '';
      _unit = item.unit;
      _packSize = item.packSize;
    }
    final nameIndex = ref.watch(liveItemNameIndexProvider);
    final suggestions =
        ref.watch(categorySuggestionsProvider).valueOrNull ?? const <String>[];
    final theme = Theme.of(context);

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
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Item name',
                        hintText: 'Beef burgers',
                        helperText:
                            'Sold by weight? Put it in the name — '
                            '"Mince (500 g packs)" — and count the packs.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _markDirty(),
                      validator: (text) => _validateName(text, nameIndex),
                    ),
                    const SizedBox(height: 24),
                    if (_isEdit)
                      _CurrentCount(
                        itemId: widget.itemId!,
                        onHandMicros: detail!.onHandMicros,
                        unit: detail.item.unit,
                        archived: detail.item.isArchived,
                      )
                    else
                      CountFormField(
                        controller: _count,
                        labelText: 'How many do you have?',
                        hintText: '0',
                        helperText: 'Leave blank if you have none yet.',
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => _markDirty(),
                      ),
                    const SizedBox(height: 24),
                    CountFormField(
                      controller: _serves,
                      labelText: 'How many people does one serve?',
                      hintText: '4',
                      minValue: 1,
                      maxValue: maxServesPerUnit,
                      helperText:
                          'Optional. Leave blank if it varies — a forecast '
                          'can still learn from what you actually use.',
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 32),
                    Text('Optional details', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
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
                                  labelText: 'Group',
                                  helperText:
                                      'Groups the item list — "Drinks", '
                                      '"Dry goods".',
                                  helperMaxLines: 2,
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
                      textCapitalization: TextCapitalization.sentences,
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
            onPressed: _submitting ? null : _save,
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            child: _submitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(_isEdit ? 'Save changes' : 'Add item'),
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

/// Edit mode's read-only count. On-hand is derived from the append-only
/// ledger, so it is never editable here — the way to change it is to record
/// what happened.
class _CurrentCount extends StatelessWidget {
  const _CurrentCount({
    required this.itemId,
    required this.onHandMicros,
    required this.unit,
    required this.archived,
  });

  final String itemId;
  final int onHandMicros;
  final ItemUnit unit;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final negative = onHandMicros < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'How many you have now',
            helperText:
                'Counted from everything you have recorded. To change it, '
                'record what happened.',
            helperMaxLines: 3,
            border: OutlineInputBorder(),
            enabled: false,
          ),
          child: Text(
            formatCount(onHandMicros, unit),
            style: theme.textTheme.titleMedium?.copyWith(
              color: negative ? theme.colorScheme.error : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: archived
                ? null
                : () =>
                      context.push('/movements/new?kind=count&itemId=$itemId'),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Record a count'),
          ),
        ),
      ],
    );
  }
}
