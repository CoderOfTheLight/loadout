/// `/items/scan-in` — the fast restock loop ("Scan items in…" from the
/// Items screen's overflow, shown only when the scanner probe says yes).
///
/// The screen is a HUB: it opens the scanner immediately on arrival and
/// again after every recorded scan, and between scans it shows the running
/// session summary plus a big 'Scan next' — so a mis-dismissed scanner
/// never strands the owner. Per detected barcode:
///
///  * KNOWN (a live item carries exactly this payload): a bottom sheet with
///    the item's name, its folder, its current on-hand, and "How many
///    arrived?" — submitting records a RECEIVE movement (note 'Scanned in')
///    through the one inventory write path.
///  * UNKNOWN: a "New item" sheet — name, "How many do you have?", an
///    optional "Price each" (v7, exact cents), folder — creating the item
///    WITH the barcode linked, the count as its opening count, and the
///    price in ONE command (`CatalogService.createItem(barcode:)`).
///
/// Cancelling the scanner lands on the hub, silently. A 'camera_denied'
/// failure shows an inline settings pointer on the hub; other failures a
/// content-free snackbar. Content privacy: payloads are looked up and
/// stored, never logged, never shown — snackbars carry names only.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../app/widgets/money_form_field.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../app/widgets/section_header.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../inventory/application/inventory_service.dart';
import '../../inventory/domain/movement.dart';
import '../application/barcode_scan_service.dart';
import '../domain/folder.dart';
import '../domain/item.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'folder_picker_sheet.dart';

/// What a sheet resolved to: the recorded addition and whether the owner
/// asked for the next scan ('… & scan next') or to finish ('Done'). A
/// dismissed sheet resolves to null — nothing recorded, back to the hub.
final class _ScanOutcome {
  const _ScanOutcome({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.created,
    required this.scanNext,
  });

  final String itemId;
  final String itemName;
  final Quantity quantity;

  /// True when the sheet created a new item (vs. restocked a known one).
  final bool created;
  final bool scanNext;
}

class ScanItemsInScreen extends ConsumerStatefulWidget {
  const ScanItemsInScreen({super.key});

  @override
  ConsumerState<ScanItemsInScreen> createState() => _ScanItemsInScreenState();
}

class _ScanItemsInScreenState extends ConsumerState<ScanItemsInScreen> {
  /// This session's additions, itemId → running total. Insertion-ordered so
  /// the summary reads in scan order.
  final Map<String, ({String name, int micros})> _session = {};

  bool _cameraDenied = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    // Straight into the scanner: the hub is where scans RETURN to, not a
    // stop on the way in. Post-frame so sheets and dialogs have a context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_scanNext());
      }
    });
  }

  /// One full scan turn: capture behind a blocking progress state (the
  /// native side presents its own full-screen UI), look the payload up,
  /// run the matching sheet, record the outcome, then loop or finish.
  Future<void> _scanNext() async {
    if (_scanning) {
      return;
    }
    _scanning = true;
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
    _scanning = false;
    if (failureCode != null) {
      if (failureCode == 'camera_denied') {
        setState(() => _cameraDenied = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the camera. Try again.")),
        );
      }
      return;
    }
    if (scan == null) {
      return; // owner cancelled: the hub, silently
    }
    if (_cameraDenied) {
      setState(() => _cameraDenied = false); // the camera evidently works
    }
    final item = await ref
        .read(catalogServiceProvider)
        .itemByBarcode(scan.payload);
    if (!mounted) {
      return;
    }
    final outcome = await showModalBottomSheet<_ScanOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => item != null
          ? _KnownItemSheet(item: item)
          : _NewItemSheet(payload: scan!.payload),
    );
    if (!mounted || outcome == null) {
      return; // dismissed without recording: the hub
    }
    setState(() {
      final previous = _session[outcome.itemId];
      _session[outcome.itemId] = (
        name: outcome.itemName,
        micros: (previous?.micros ?? 0) + outcome.quantity.micros,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.created
              ? 'Created "${outcome.itemName}"'
              : 'Added ${formatMicros(outcome.quantity.micros)} × '
                    '"${outcome.itemName}"',
        ),
      ),
    );
    if (outcome.scanNext) {
      unawaited(_scanNext());
    } else {
      _close();
    }
  }

  void _close() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/items');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan items in')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_cameraDenied)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.l,
                      Space.l,
                      Space.l,
                      0,
                    ),
                    child: _CameraDeniedNote(
                      key: const Key('camera-denied-note'),
                    ),
                  ),
                Expanded(
                  child: _session.isEmpty
                      ? const EmptyState(
                          message:
                              'Nothing scanned in yet. Scan a barcode to '
                              'count stock in as it arrives.',
                          icon: Icons.qr_code_scanner_outlined,
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.l,
                          ),
                          children: [
                            const SectionHeader('Added this session'),
                            for (final entry in _session.entries)
                              ListTile(
                                key: ValueKey('session-row-${entry.key}'),
                                contentPadding: EdgeInsets.zero,
                                minTileHeight: 56,
                                title: Text(
                                  entry.value.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  formatMicros(entry.value.micros),
                                  style: Numerals.rowQuantity(theme.textTheme),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Material(
        color: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        elevation: 3,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.l,
              Space.m,
              Space.l,
              Space.m,
            ),
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      key: const Key('scan-next'),
                      style: FilledButton.styleFrom(
                        minimumSize: primaryButtonMinSize,
                      ),
                      onPressed: _scanNext,
                      child: const Text('Scan next'),
                    ),
                    const SizedBox(height: Space.s),
                    OutlinedButton(
                      key: const Key('scan-done'),
                      onPressed: _close,
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline 'camera_denied' pointer — plain words toward Settings, never
/// an error dialog (availability said yes; permission is the owner's call).
class _CameraDeniedNote extends StatelessWidget {
  const _CameraDeniedNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(Radii.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.l,
          vertical: Space.m,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.no_photography_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: Space.m),
            Expanded(
              child: Text(
                'Camera access is off. Turn it on in Settings to scan.',
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
}

/// Bottom-sheet scaffolding shared by both sheets: title row, body, the
/// primary '… & scan next' + 'Done' pair, lifted above the keyboard.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.header,
    required this.children,
    required this.primaryLabel,
    required this.primaryKey,
    required this.onPrimary,
    required this.onDone,
    required this.submitting,
  });

  final Widget header;
  final List<Widget> children;
  final String primaryLabel;
  final Key primaryKey;
  final VoidCallback onPrimary;
  final VoidCallback onDone;
  final bool submitting;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.xl,
          Space.xl,
          Space.l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: Space.l),
            ...children,
            const SizedBox(height: Space.xl),
            FilledButton(
              key: primaryKey,
              style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
              onPressed: submitting ? null : onPrimary,
              child: Text(primaryLabel),
            ),
            const SizedBox(height: Space.s),
            OutlinedButton(
              key: const Key('sheet-done'),
              onPressed: submitting ? null : onDone,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A recognized barcode: the item's identity, its current on-hand, and
/// "How many arrived?" → one RECEIVE movement, note 'Scanned in'.
class _KnownItemSheet extends ConsumerStatefulWidget {
  const _KnownItemSheet({required this.item});

  final Item item;

  @override
  ConsumerState<_KnownItemSheet> createState() => _KnownItemSheetState();
}

class _KnownItemSheetState extends ConsumerState<_KnownItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool scanNext}) async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    final quantity = QuantityFormField.tryParse(_quantity.text)!;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final result = await ref
        .read(inventoryServiceProvider)
        .record(
          MovementFormDraft(
            itemId: widget.item.id.value,
            kind: MovementKind.receive,
            quantity: quantity,
            note: 'Scanned in',
          ),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        Navigator.of(context).pop(
          _ScanOutcome(
            itemId: widget.item.id.value,
            itemName: widget.item.name,
            quantity: quantity,
            created: false,
            scanNext: scanNext,
          ),
        );
      case Err():
        // Content-free by design (§9): no names or quantities in errors.
        setState(() {
          _submitting = false;
          _submitError = "Couldn't save this entry. Try again.";
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = ref.watch(folderListProvider).valueOrNull ?? const [];
    Folder? folder;
    for (final candidate in folders) {
      if (candidate.id.value == widget.item.folderId?.value) {
        folder = candidate;
      }
    }
    final position = ref
        .watch(stockPositionProvider(widget.item.id.value))
        .valueOrNull;
    return _SheetFrame(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item.name, style: theme.textTheme.titleLarge),
          if (folder != null) ...[
            const SizedBox(height: Space.s),
            Row(
              children: [
                FolderChip.forFolder(folder, size: FolderChipSize.small),
                const SizedBox(width: Space.s),
                Text(
                  folder.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (position != null) ...[
            const SizedBox(height: Space.s),
            Text(
              'You have '
              '${formatAmount(position.onHandMicros, widget.item.unit, widget.item.unitLabel)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      primaryLabel: 'Add & scan next',
      primaryKey: const Key('scan-add-next'),
      onPrimary: () => _submit(scanNext: true),
      onDone: () => _submit(scanNext: false),
      submitting: _submitting,
      children: [
        Form(
          key: _formKey,
          child: QuantityFormField(
            key: const Key('scan-arrived-quantity'),
            controller: _quantity,
            autofocus: true,
            allowFractions: true,
            labelText: 'How many arrived?',
            requiredMessage: 'Enter how many arrived',
          ),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: Space.s),
          Text(
            _submitError!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// An unrecognized barcode: create the item WITH the payload linked and the
/// typed count as its opening count — one command, one transaction.
class _NewItemSheet extends ConsumerStatefulWidget {
  const _NewItemSheet({required this.payload});

  final String payload;

  @override
  ConsumerState<_NewItemSheet> createState() => _NewItemSheetState();
}

class _NewItemSheetState extends ConsumerState<_NewItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _count = TextEditingController();
  final _price = TextEditingController();

  /// Null = Unfiled, exactly as the item form starts.
  String? _folderId;
  bool _submitting = false;
  String? _submitError;

  /// Lowercased name most recently rejected by the command validator
  /// (unique among live), mirrored inline like the item form does.
  String? _rejectedDuplicateName;

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final pick = await showFolderPickerSheet(
      context,
      selectedFolderId: _folderId,
    );
    if (pick == null || !mounted) {
      return;
    }
    setState(() => _folderId = pick.folderId);
  }

  Future<void> _submit({required bool scanNext}) async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    final name = _name.text.trim();
    final count = QuantityFormField.tryParse(_count.text) ?? Quantity.zero;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final result = await ref
        .read(catalogServiceProvider)
        .createItem(
          ItemDraft(
            name: name,
            folderId: _folderId,
            // Optional (v7): empty = no price; the field validated already.
            unitPrice: MoneyFormField.tryParse(_price.text),
          ),
          openingCount: count,
          barcode: widget.payload,
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(
          _ScanOutcome(
            itemId: value,
            itemName: name,
            quantity: count,
            created: true,
            scanNext: scanNext,
          ),
        );
      case Err(:final error):
        setState(() {
          _submitting = false;
          if (error.message.contains('name already exists')) {
            _rejectedDuplicateName = name.toLowerCase();
          } else if (error.message.contains('barcode')) {
            _submitError = 'Another item already has this barcode';
          } else {
            // Content-free by design (§9).
            _submitError = "Couldn't save this entry. Try again.";
          }
        });
        _formKey.currentState!.validate();
    }
  }

  String? _validateName(String? text) {
    final name = (text ?? '').trim();
    if (name.isEmpty) {
      return 'Enter a name';
    }
    if (name.length > 120) {
      return 'Keep the name under 120 characters';
    }
    if (name.toLowerCase() == _rejectedDuplicateName) {
      return 'A live item with this name already exists.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = ref.watch(folderListProvider).valueOrNull ?? const [];
    var folderName = 'Unfiled';
    for (final folder in folders) {
      if (folder.id.value == _folderId) {
        folderName = folder.name;
      }
    }
    return _SheetFrame(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New item', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.s),
          Text(
            "This barcode isn't linked to any of your items yet. Name the "
            'item and the barcode links to it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      primaryLabel: 'Create & scan next',
      primaryKey: const Key('scan-create-next'),
      onPrimary: () => _submit(scanNext: true),
      onDone: () => _submit(scanNext: false),
      submitting: _submitting,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('scan-new-name'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Item name',
                  border: OutlineInputBorder(),
                ),
                validator: _validateName,
              ),
              const SizedBox(height: Space.l),
              QuantityFormField(
                key: const Key('scan-new-quantity'),
                controller: _count,
                allowFractions: true,
                allowZero: true,
                isRequired: false,
                labelText: 'How many do you have?',
                helperText: 'Leave blank if you have none yet.',
              ),
              const SizedBox(height: Space.l),
              MoneyFormField(
                key: const Key('scan-new-price'),
                controller: _price,
                labelText: 'Price each (optional)',
                hintText: '12.50',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.l),
              InkWell(
                key: const Key('scan-new-folder'),
                borderRadius: BorderRadius.circular(Radii.small),
                onTap: _pickFolder,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Folder',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(folderName),
                ),
              ),
            ],
          ),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: Space.s),
          Text(
            _submitError!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
