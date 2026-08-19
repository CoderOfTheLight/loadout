/// `/items/new` and `/items/:itemId/edit` — ItemEditScreen.
///
/// CREATE asks FOUR questions and nothing else — the same four the scan-in
/// "New item" sheet asks, which is the shape this form was rebuilt to match:
///
///   * **Item name** — required, live unique-among-live check.
///   * **How many do you have?** — rides inside `CreateItem` as the opening
///     `adjust` movement. Accepts decimals and simple/mixed fractions
///     ("1.5", "1/2", "1 1/2") exactly like every other amount field.
///   * **Price each** — optional money entry ([MoneyFormField], exact
///     integer cents, v7).
///   * **Folder** — a pick-list over the owner's folders ("New folder…" at
///     the bottom, created through the command path), never free text.
///     Free-text groups are how "Drinks", "drinks" and "Beverages" become
///     three folders.
///
/// Everything else lives on the SAVED item behind ONE plain row, **More
/// options**, so the front door stays one screen long:
///
///   * **Unit** — an optional DISPLAY label for the amount ("tsp", "cup",
///     "lbs"; 1–24 chars), free text. Shown after the amount everywhere; the
///     app never converts between labels and never does unit arithmetic.
///   * **The one question**, as ONE checkbox: "Bring the same amount however
///     many people come" (the forecast engine's `DemandBasis`). On create it
///     is never asked — the folder answers it and the stored override is
///     null whenever the answer matches the folder's, so a new item simply
///     inherits and a folder-level change carries its items with it.
///   * **Cold start** — headcount items take ONE number plus a two-option
///     phrasing pick ("4 people per one" / "3 per person"; the second stores
///     an exact `UnitRatio` so 200 people × 3/person is exactly 600). Items
///     that ignore headcount take "How many do you usually bring?". The
///     phrasing not on screen is resubmitted verbatim, so flipping the
///     answer twice loses nothing.
///   * **Notes**.
///
/// Edit mode also shows the ledger-derived count read-only with a button to
/// record a count, and the barcode row (v6).
///
/// Changing the answer on an item that already has history is allowed,
/// never silent: a plain-words confirm explains that past events will be
/// read differently.
///
/// No unit picker, no pack size, and no free-text group: a legacy row's
/// stored unit, pack size and category text are resubmitted verbatim so a
/// rename can never trip the §4 unit lock or wipe the tidy-up flow's raw
/// material.
///
/// Commands: `CatalogService.createItem` / `updateItem` — plain updates, no
/// revision log.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_label_suggestions.dart' show unitLabelMaxLength;
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/count_form_field.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/form_action_bar.dart';
import '../../../app/widgets/money_form_field.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../core/errors.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/unit_ratio.dart';
import '../../../core/units.dart';
import '../application/barcode_scan_service.dart';
import '../domain/demand_basis.dart';
import '../domain/folder.dart';
import '../domain/item.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'folder_picker_sheet.dart';

/// Cap on the cold-start number, mirroring the command validator
/// (`maxServesPerUnitMicros` and the ratio halves cap: 10 000 each).
const int maxServesPerUnit = 10000;

/// The opening count keeps [CountFormField]'s envelope (one million whole
/// things) even though it now accepts fractions.
const int _maxOpeningCountMicros = maxCountValue * Quantity.scale;

/// One value, two ways of saying it: "4 people per one" and "3 per person".
/// One number and this pick replace the pair of fields that used to clear
/// each other.
enum _PerPersonPhrasing {
  /// One of these serves N people → `servesPerUnit`.
  peoplePerOne('people per one'),

  /// N of these per person → `perPersonRatio` (N/1).
  perPerson('per person');

  const _PerPersonPhrasing(this.label);

  final String label;
}

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
  final _price = TextEditingController();
  final _unitLabel = TextEditingController();
  final _perPersonAmount = TextEditingController();
  final _usualBring = TextEditingController();
  final _notes = TextEditingController();
  bool _hydrated = false;
  bool _dirty = false;
  bool _submitting = false;

  /// The item's folder; null = Unfiled.
  String? _folderId;

  /// The stored per-item override, hydrated on edit. Displayed selection is
  /// derived: explicit tap wins, else this override, else the folder.
  DemandBasis? _storedOverride;
  bool _basisTouched = false;
  DemandBasis? _explicitBasis;

  /// Which way the cold-start number is phrased on screen.
  _PerPersonPhrasing _phrasing = _PerPersonPhrasing.peoplePerOne;

  /// True once the owner touched the cold-start number or its phrasing (or
  /// the per-event field). Until then, edit mode resubmits the stored values
  /// verbatim — which keeps a ratio this form's whole-number field cannot
  /// express (denominator > 1) intact through an unrelated rename.
  bool _phrasingEdited = false;
  bool _baselineEdited = false;

  /// Schema-v1/v2 leftovers. Never shown, never asked, always resubmitted
  /// verbatim: changing a legacy item's unit after its first movement is an
  /// IMMUTABLE_RECORD, rewriting its pack size would restate what its
  /// stored numbers mean, and its free-text category is the tidy-up flow's
  /// raw material.
  ItemUnit _unit = ItemUnit.each;
  Quantity _packSize = Quantity.one;
  String _category = '';

  /// Lowercased name most recently rejected by the command validator
  /// (uniqueness); mirrored onto the name field inline.
  String? _rejectedDuplicateName;

  /// v6: the stored barcode payload, hydrated on edit and updated by the
  /// immediate link/remove actions below. Barcode changes deliberately do
  /// NOT ride the Save button: `updateItem` never touches the barcode (the
  /// draft doesn't carry one), so linking commits immediately through
  /// `setItemBarcode` — the same side-action grammar as "Record a count".
  String? _barcode;

  /// Barcode-scanner capability, probed once (false until answered). With
  /// no barcode and no scanner there is no row at all.
  bool _scanAvailable = false;

  bool get _isEdit => widget.itemId != null;

  @override
  void initState() {
    super.initState();
    unawaited(_probeScanner());
  }

  Future<void> _probeScanner() async {
    final available = await ref.read(barcodeScanServiceProvider).isAvailable();
    if (mounted && available) {
      setState(() => _scanAvailable = true);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    _price.dispose();
    _unitLabel.dispose();
    _perPersonAmount.dispose();
    _usualBring.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  // ------------------------------------------------------- basis plumbing

  DemandBasis? _folderBasis(List<Folder> folders, String? folderId) {
    if (folderId == null) {
      return null;
    }
    for (final folder in folders) {
      if (folder.id.value == folderId) {
        return folder.demandBasis;
      }
    }
    return null;
  }

  /// What the folder would answer for this item — the pre-selection, and
  /// the value against which "this item is the exception" is judged.
  DemandBasis _folderDefault(List<Folder> folders) =>
      effectiveDemandBasis(folderBasis: _folderBasis(folders, _folderId));

  /// The selection on screen: the owner's explicit tick wins, else the
  /// stored override, else the folder's answer.
  DemandBasis _displayedBasis(List<Folder> folders) => _basisTouched
      ? _explicitBasis!
      : effectiveDemandBasis(
          itemOverride: _storedOverride,
          folderBasis: _folderBasis(folders, _folderId),
        );

  Future<void> _pickFolder() async {
    final folders = ref.read(folderListProvider).valueOrNull ?? const [];
    final hasHistory =
        _isEdit &&
        (ref
                .read(itemDetailProvider(widget.itemId!))
                .valueOrNull
                ?.hasMovements ??
            false);
    final basisBeforeMove = _displayedBasis(folders);
    final pick = await showFolderPickerSheet(
      context,
      selectedFolderId: _folderId,
    );
    if (pick == null || !mounted || pick.folderId == _folderId) {
      return;
    }
    setState(() {
      // Moving folders is JUST a move. Before this pin, an item with
      // history silently inherited the new folder's answer to the one
      // question, and saving then raised the "Read past events
      // differently?" confirm — whose safe-sounding "Keep it as it was"
      // aborted the WHOLE save, dropping the move (the failure the owner
      // hit moving a folder's only item). Now an item WITH history keeps
      // the answer it already had: pinned as the explicit selection,
      // stored as the per-item exception when it differs from the new
      // folder's default, so forecasts read past events exactly as
      // before and the move always survives. Changing the answer remains
      // her explicit act — and still confirms.
      if (hasHistory && !_basisTouched) {
        _basisTouched = true;
        _explicitBasis = basisBeforeMove;
      }
      _folderId = pick.folderId;
    });
    _markDirty();
  }

  // ------------------------------------------------------------- saving

  Future<void> _save() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    final folders = ref.read(folderListProvider).valueOrNull ?? const [];
    final detail = _isEdit
        ? ref.read(itemDetailProvider(widget.itemId!)).valueOrNull
        : null;
    final item = detail?.item;
    final selectedBasis = _displayedBasis(folders);

    // Changing how an item with history forecasts is allowed, never silent.
    if (_isEdit && detail!.hasMovements) {
      final oldEffective = effectiveDemandBasis(
        itemOverride: item!.demandBasis,
        folderBasis: _folderBasis(folders, item.folderId?.value),
      );
      if (oldEffective != selectedBasis &&
          !await _confirmBasisChange(selectedBasis)) {
        return;
      }
      if (!mounted) {
        return;
      }
    }

    // The override is stored only when this item differs from what its
    // folder would answer; matching items follow the folder. On create
    // nothing is asked, so this is always null — the item inherits.
    final folderDefault = _folderDefault(folders);
    final override = selectedBasis == folderDefault ? null : selectedBasis;

    // One value, two phrasings — at most one of serves/ratio is ever set.
    // The phrasing that is not on screen rides along verbatim, so flipping
    // the answer twice loses nothing.
    Quantity? serves;
    UnitRatio? ratio;
    Quantity? baseline;
    if (selectedBasis == DemandBasis.perPerson) {
      if (_phrasingEdited || !_isEdit) {
        final amount = CountFormField.tryParseCount(_perPersonAmount.text);
        if (amount != null) {
          switch (_phrasing) {
            case _PerPersonPhrasing.peoplePerOne:
              serves = Quantity.whole(amount);
            case _PerPersonPhrasing.perPerson:
              ratio = UnitRatio(amount, 1);
          }
        }
      } else {
        serves = item!.servesPerUnit;
        ratio = item.perPersonRatio;
      }
      baseline = item?.perEventBaseline;
    } else {
      baseline = _baselineEdited || !_isEdit
          ? CountFormField.tryParseQuantity(_usualBring.text)
          : item!.perEventBaseline;
      serves = item?.servesPerUnit;
      ratio = item?.perPersonRatio;
    }

    final category = _category.trim();
    final label = _unitLabel.text.trim();
    final draft = ItemDraft(
      name: _name.text.trim(),
      unitLabel: label.isEmpty ? null : label,
      // Whole-state grammar: the field is prefilled from the item, so an
      // empty field is the owner's answer — no price (clears a stored one
      // on update). The validator already vouched for non-empty text.
      unitPrice: MoneyFormField.tryParse(_price.text),
      servesPerUnit: serves,
      perPersonRatio: ratio,
      folderId: _folderId,
      demandBasis: override,
      perEventBaseline: baseline,
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
                QuantityFormField.tryParse(_count.text) ?? Quantity.zero,
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

  Future<bool> _confirmBasisChange(DemandBasis to) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Read past events differently?'),
        content: Text(
          "This item has history. Switching to "
          "'${demandBasisLabel(to)}' changes how the events you've "
          'already recorded are read, so the next packing list can '
          'change. Nothing you recorded is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it as it was'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change it'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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

  // -------------------------------------------------------------- build

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
      // One number, one phrasing. This form is the only writer of
      // serves-per-unit and only ever writes whole people, so the
      // truncation here is exact; a stored ratio with a denominator > 1
      // cannot come from this form, so it stays blank and rides along
      // verbatim.
      if (item.servesPerUnit case final serves?) {
        _perPersonAmount.text = CountFormField.format(
          serves.micros ~/ Quantity.scale,
        );
        _phrasing = _PerPersonPhrasing.peoplePerOne;
      } else if (item.perPersonRatio case final ratio?
          when ratio.denominator == 1) {
        _perPersonAmount.text = '${ratio.numerator}';
        _phrasing = _PerPersonPhrasing.perPerson;
      }
      _usualBring.text = switch (item.perEventBaseline) {
        final usual? => CountFormField.format(usual.micros ~/ Quantity.scale),
        null => '',
      };
      _notes.text = item.notes;
      // CRITICAL: updateItem is whole-state — without this prefill, saving
      // any edit would silently wipe a stored price.
      _price.text = switch (item.unitPrice) {
        final price? => MoneyFormField.formatFieldText(price),
        null => '',
      };
      _unitLabel.text = item.unitLabel ?? '';
      _barcode = item.barcode;
      _folderId = item.folderId?.value;
      _storedOverride = item.demandBasis;
      _category = item.category ?? '';
      _unit = item.unit;
      _packSize = item.packSize;
    }
    final nameIndex = ref.watch(liveItemNameIndexProvider);
    final folders = ref.watch(folderListProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    String folderName() {
      for (final folder in folders) {
        if (folder.id.value == _folderId) {
          return folder.name;
        }
      }
      return 'Unfiled';
    }

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
                        unitLabel: detail.item.unitLabel,
                        archived: detail.item.isArchived,
                      )
                    else
                      QuantityFormField(
                        controller: _count,
                        labelText: 'How many do you have?',
                        isRequired: false,
                        allowZero: true,
                        allowFractions: true,
                        helperText: 'Leave blank if you have none yet.',
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value.micros > _maxOpeningCountMicros
                            ? 'Keep it under 1,000,000'
                            : null,
                        onChanged: (_) => _markDirty(),
                      ),
                    const SizedBox(height: 24),
                    MoneyFormField(
                      controller: _price,
                      labelText: 'Price each (optional)',
                      hintText: '12.50',
                      helperText: 'What one costs you.',
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 24),
                    InkWell(
                      borderRadius: BorderRadius.circular(Radii.small),
                      onTap: _pickFolder,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Folder',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(folderName()),
                      ),
                    ),
                    if (_isEdit) ...[
                      if (_barcode != null || _scanAvailable) ...[
                        const SizedBox(height: 24),
                        _buildBarcodeRow(theme),
                      ],
                      const SizedBox(height: 16),
                      _moreOptions(folders),
                    ],
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

  // -------------------------------------------------------- more options
  // Edit only: one plain row that opens the rest. Nothing here is needed to
  // put an item on the list, so nothing here is on the way in.

  Widget _moreOptions(List<Folder> folders) {
    final perEvent = _displayedBasis(folders) == DemandBasis.perEvent;
    return ExpansionTile(
      key: const Key('more-options'),
      title: const Text('More options'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _unitLabel,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textInputAction: TextInputAction.next,
          maxLength: unitLabelMaxLength,
          decoration: const InputDecoration(
            labelText: 'Unit (optional)',
            hintText: 'packages',
            counterText: '',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const Key('same-every-event'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Bring the same amount however many people come'),
          value: perEvent,
          onChanged: (checked) {
            setState(() {
              _basisTouched = true;
              _explicitBasis = (checked ?? false)
                  ? DemandBasis.perEvent
                  : DemandBasis.perPerson;
            });
            _markDirty();
          },
        ),
        const SizedBox(height: 16),
        if (perEvent)
          CountFormField(
            controller: _usualBring,
            labelText: 'How many do you usually bring?',
            hintText: '2',
            minValue: 1,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              _baselineEdited = true;
              _markDirty();
            },
          )
        else
          _perPersonRow(),
        const SizedBox(height: 16),
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
      ],
    );
  }

  /// The cold-start question as ONE row: a number and how to read it.
  /// "4 people per one" and "3 per person" are the same question said two
  /// ways, so they are one control — never two fields that clear each other.
  Widget _perPersonRow() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: CountFormField(
          controller: _perPersonAmount,
          labelText: 'How many',
          hintText: '4',
          minValue: 1,
          maxValue: maxServesPerUnit,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            _phrasingEdited = true;
            _markDirty();
          },
        ),
      ),
      const SizedBox(width: Space.m),
      Expanded(
        flex: 3,
        child: DropdownButtonFormField<_PerPersonPhrasing>(
          key: const Key('per-person-phrasing'),
          isExpanded: true,
          initialValue: _phrasing,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            for (final phrasing in _PerPersonPhrasing.values)
              DropdownMenuItem(value: phrasing, child: Text(phrasing.label)),
          ],
          onChanged: (phrasing) {
            if (phrasing == null) {
              return;
            }
            setState(() => _phrasing = phrasing);
            _phrasingEdited = true;
            _markDirty();
          },
        ),
      ),
    ],
  );

  // ------------------------------------------------------------- barcode
  // v6, edit mode only. Content privacy: the payload appears ONLY as the
  // small caption below "Barcode linked" — the owner's own data on her own
  // screen — never in a snackbar and never in a log.

  Widget _buildBarcodeRow(ThemeData theme) {
    final barcode = _barcode;
    if (barcode == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('scan-barcode'),
          onPressed: _scanBarcode,
          icon: const Icon(Icons.qr_code_scanner_outlined),
          label: const Text('Scan barcode'),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Barcode linked', style: theme.textTheme.bodyLarge),
              Text(
                barcode,
                key: const Key('barcode-caption'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: Numerals.tabular,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          key: const Key('remove-barcode'),
          onPressed: _removeBarcode,
          child: const Text('Remove'),
        ),
      ],
    );
  }

  /// Scans one barcode and links it immediately through `setItemBarcode`
  /// (the single write path; the validator rejects a payload another live
  /// item carries).
  Future<void> _scanBarcode() async {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );
    BarcodeScan? scan;
    String? failureCode;
    try {
      scan = await ref.read(barcodeScanServiceProvider).scanOne();
    } on BarcodeScanException catch (e) {
      failureCode = e.code; // a stable channel code, never a payload
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop(); // the progress dialog
    if (failureCode != null) {
      _showSnack(
        failureCode == 'camera_denied'
            ? 'Camera access is off. Turn it on in Settings to scan.'
            : "Couldn't open the camera. Try again.",
      );
      return;
    }
    if (scan == null) {
      return; // owner cancelled: nothing changes
    }
    final result = await ref
        .read(catalogServiceProvider)
        .setItemBarcode(itemId: widget.itemId!, barcode: scan.payload);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        setState(() => _barcode = scan!.payload);
        _showSnack('Barcode linked');
      case Err(:final error):
        _showSnack(
          error.message.contains('barcode')
              ? 'Another item already has this barcode'
              // Content-free by design (§9).
              : "Couldn't save this entry. Try again.",
        );
    }
  }

  /// Clears the stored barcode — immediate, behind its own plain-words
  /// confirm (a scan either assigns a payload or removes one; the Save
  /// button never touches it).
  Future<void> _removeBarcode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this barcode?'),
        content: const Text(
          'Scanning it will no longer bring up this item. You can scan a '
          'barcode again any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final result = await ref
        .read(catalogServiceProvider)
        .setItemBarcode(itemId: widget.itemId!, barcode: null);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        setState(() => _barcode = null);
        _showSnack('Barcode removed');
      case Err():
        // Content-free by design (§9).
        _showSnack("Couldn't save this entry. Try again.");
    }
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
    required this.unitLabel,
    required this.archived,
  });

  final String itemId;
  final int onHandMicros;
  final ItemUnit unit;
  final String? unitLabel;
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
            border: OutlineInputBorder(),
            enabled: false,
          ),
          child: Text(
            formatAmount(onHandMicros, unit, unitLabel),
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
