/// `/items/new` and `/items/:itemId/edit` — ItemEditScreen.
///
/// The owner's model of an item, in her words (folders proposal §3):
///
///   * **Item name** — required, live unique-among-live check.
///   * **How many do you have?** — create only; rides inside `CreateItem`
///     as the opening `adjust` movement. Accepts decimals and simple/mixed
///     fractions ("1.5", "1/2", "1 1/2") exactly like every other amount
///     field. Edit mode shows the ledger-derived count read-only with a
///     button to record a movement.
///   * **Unit** — an optional DISPLAY label for the amount ("tsp", "cup",
///     "lbs"; 1–24 chars), free text with suggestion chips. Shown after
///     the amount everywhere; the app never converts between labels and
///     never does unit arithmetic.
///   * **Folder** — a pick-list over the owner's folders ("New folder…" at
///     the bottom, created through the command path), never free text.
///     Free-text groups are how "Drinks", "drinks" and "Beverages" become
///     three folders.
///   * **The one question** — "Does how much you bring depend on how many
///     people come?" as two plain choices, pre-answered by the folder and
///     called out as the exception only when this item differs. The stored
///     override is null whenever the answer matches the folder's, so a
///     folder-level change carries its items with it.
///   * **Cold start** — per-person items take "How many people does one
///     serve?" OR the flipped "How many per person?" (one value, two
///     phrasings; the second stores an exact `UnitRatio` so 200 people ×
///     3/person is exactly 600). Per-event items take "How many do you
///     usually bring?". The phrasing not on screen is resubmitted verbatim,
///     so flipping the answer twice loses nothing.
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
import '../../../app/unit_label_suggestions.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/count_form_field.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/form_action_bar.dart';
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
import 'demand_basis_choice.dart';
import 'folder_picker_sheet.dart';

/// Cap on "how many people does one serve?" and "how many per person?",
/// mirroring the command validator (`maxServesPerUnitMicros` and the ratio
/// halves cap: 10 000 each).
const int maxServesPerUnit = 10000;

/// The opening count keeps [CountFormField]'s envelope (one million whole
/// things) even though it now accepts fractions.
const int _maxOpeningCountMicros = maxCountValue * Quantity.scale;

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
  final _unitLabel = TextEditingController();
  final _serves = TextEditingController();
  final _perPerson = TextEditingController();
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

  /// True once the owner touched either per-person phrasing field (or the
  /// per-event field). Until then, edit mode resubmits the stored values
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
    _unitLabel.dispose();
    _serves.dispose();
    _perPerson.dispose();
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

  /// The selection on screen: the owner's explicit tap wins, else the
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
    // folder would answer; matching items follow the folder.
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
        serves = CountFormField.tryParseQuantity(_serves.text);
        final perPerson = CountFormField.tryParseCount(_perPerson.text);
        ratio = serves == null && perPerson != null
            ? UnitRatio(perPerson, 1)
            : null;
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
      // This form is the only writer of serves-per-unit and only ever
      // writes whole people, so the truncation here is exact.
      _serves.text = switch (item.servesPerUnit) {
        final serves? => CountFormField.format(serves.micros ~/ Quantity.scale),
        null => '',
      };
      // Same for the flipped phrasing (a denominator > 1 cannot come from
      // this form; it stays blank here and rides along verbatim).
      _perPerson.text = switch (item.perPersonRatio) {
        final ratio? when ratio.denominator == 1 => '${ratio.numerator}',
        _ => '',
      };
      _usualBring.text = switch (item.perEventBaseline) {
        final usual? => CountFormField.format(usual.micros ~/ Quantity.scale),
        null => '',
      };
      _notes.text = item.notes;
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
    final displayedBasis = _displayedBasis(folders);
    final folderDefault = _folderDefault(folders);
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
                        helperText:
                            'Leave blank if you have none yet. Fractions '
                            'work: "1.5", "1/2", "1 1/2".',
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value.micros > _maxOpeningCountMicros
                            ? 'Keep it under 1,000,000'
                            : null,
                        onChanged: (_) => _markDirty(),
                      ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _unitLabel,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      textInputAction: TextInputAction.next,
                      maxLength: unitLabelMaxLength,
                      decoration: const InputDecoration(
                        labelText: 'Unit (optional)',
                        hintText: 'packages',
                        helperText:
                            'Just a label shown after the amount — '
                            '"12 packages". Loadout never converts units.',
                        helperMaxLines: 3,
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 8),
                    // The shared suggestion chips (never forked from the
                    // recipe form's). A scroll-row like the hue swatches —
                    // not a second ListView on the form.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final suggestion in unitLabelSuggestions)
                            Padding(
                              padding: const EdgeInsets.only(right: Space.s),
                              child: ActionChip(
                                label: Text(suggestion),
                                onPressed: () {
                                  _unitLabel.text = suggestion;
                                  _markDirty();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_isEdit && (_barcode != null || _scanAvailable)) ...[
                      const SizedBox(height: 24),
                      _buildBarcodeRow(theme),
                    ],
                    const SizedBox(height: 24),
                    InkWell(
                      borderRadius: BorderRadius.circular(Radii.small),
                      onTap: _pickFolder,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Folder',
                          helperText:
                              'Every list sections by folder, in your order.',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(folderName()),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Does how much you bring depend on how many people '
                      'come?',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    DemandBasisChoice(
                      value: displayedBasis,
                      onChanged: (basis) {
                        setState(() {
                          _basisTouched = true;
                          _explicitBasis = basis;
                        });
                        _markDirty();
                      },
                    ),
                    if (displayedBasis != folderDefault) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Usually '${demandBasisLabel(folderDefault)}' "
                        '${_folderId == null ? 'for unfiled items' : 'in this folder'} '
                        '— this item is the exception.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (displayedBasis == DemandBasis.perPerson) ...[
                      CountFormField(
                        controller: _serves,
                        labelText: 'How many people does one serve?',
                        hintText: '4',
                        minValue: 1,
                        maxValue: maxServesPerUnit,
                        helperText: 'One shared by several — "1 pot serves 8".',
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => _servesChanged(),
                      ),
                      const SizedBox(height: 24),
                      CountFormField(
                        controller: _perPerson,
                        labelText: 'How many per person?',
                        hintText: '3',
                        minValue: 1,
                        maxValue: maxServesPerUnit,
                        helperText:
                            'Several each — "3 napkins per person". Answer '
                            'whichever way you would say it; leave both '
                            'blank if it varies.',
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => _perPersonChanged(),
                      ),
                    ] else
                      CountFormField(
                        controller: _usualBring,
                        labelText: 'How many do you usually bring?',
                        hintText: '2',
                        minValue: 1,
                        helperText:
                            'Optional. Your first packing lists start '
                            'here; real events take over as you close '
                            'them out.',
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          _baselineEdited = true;
                          _markDirty();
                        },
                      ),
                    const SizedBox(height: 32),
                    Text('Optional details', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
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

  /// One value, two phrasings: typing into one side clears the other, so
  /// serves and per-person can never both be submitted.
  void _servesChanged() {
    _phrasingEdited = true;
    if (_serves.text.trim().isNotEmpty && _perPerson.text.isNotEmpty) {
      _perPerson.clear();
    }
    _markDirty();
  }

  void _perPersonChanged() {
    _phrasingEdited = true;
    if (_perPerson.text.trim().isNotEmpty && _serves.text.isNotEmpty) {
      _serves.clear();
    }
    _markDirty();
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
            helperText:
                'Counted from everything you have recorded. To change it, '
                'record what happened.',
            helperMaxLines: 3,
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
