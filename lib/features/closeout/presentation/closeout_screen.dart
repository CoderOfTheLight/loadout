/// `/events/:eventId/closeout` (design §9 CloseoutScreen): the label
/// factory. One scrollable form — confirmed exposure (prefilled from the
/// planned estimate, captioned "estimate was N"), one [CloseoutLineCard]
/// per planned item, optional note, sticky progress + confirm bar with a
/// confirmation bottom sheet. Every change autosaves (debounced 500 ms)
/// into `closeout_drafts` via `CloseoutService.saveDraft`, reloads via
/// `loadDraft` (the draft survives process death; the applier deletes it on
/// confirm). Confirm submits `CloseoutService.confirm` (header + lines +
/// movements atomically, event → closed, §5); a closed event reopens this
/// same screen prefilled from the latest revision and `revise` appends
/// revision N+1. Receipt warnings — including NEGATIVE_ON_HAND — surface
/// as non-blocking snackbars; closeout is never blocked by ledger drift.
///
/// The line cards read in the same folder sections as every other list
/// (proposal §3), and per-event lines start as "didn't count it" — see
/// closeout_line_card.dart.
///
/// Scan to count ("a faster way to check what was used"): an app-bar text
/// action, probe-gated like the recipe screen's scanner — availability is
/// a capability, not an error. The loop: scanOne → resolve the item via
/// its barcode → the matching line in THIS worksheet → a compact "How many
/// came back?" sheet → scan again. Saves go through the SAME edit path
/// typing uses (controllers, then [_touched]) so state recompute, section
/// Done flips, and the debounced autosave all fire normally; when loaded
/// is blank but a planned load exists the save fills it, and a save
/// through this sheet — only this sheet — defaults an unset waste to 0,
/// so a scan-count alone can complete a line. Cancel stops silently;
/// failures speak content-free (never a channel code, never a payload).
///
/// Design-spec §4 treatment: a pinned progress header under the app bar
/// (determinate bar + "23 of 60 confirmed" in tabular `titleMedium` on
/// opaque `surfaceContainerLow`); section headers with the 24 dp folder
/// chip whose fraction morphs into a filled "Done" chip when the section
/// completes; a plain 64 dp "Finish closeout" button whose friction is the
/// enablement rule, never a gesture; and THE one per-session celebration on
/// commit success — a check disc scaling in, one medium haptic, one line of
/// copy. Once. Never per row.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_display.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../approval/domain/proposal.dart';
import '../../catalog/application/barcode_scan_service.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/demand_basis.dart';
import '../../catalog/domain/folder.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/folder_sections.dart';
import '../../forecasting/domain/snapshot.dart';
import '../application/closeout_service.dart';
import '../domain/closeout.dart';
import '../domain/closeout_form.dart';
import 'closeout_line_card.dart';
import '../../../app/widgets/form_action_bar.dart';

class CloseoutScreen extends ConsumerStatefulWidget {
  const CloseoutScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<CloseoutScreen> createState() => _CloseoutScreenState();
}

class _CloseoutScreenState extends ConsumerState<CloseoutScreen> {
  static const int _maxExposure = 1000000;
  static const Duration _autosaveDebounce = Duration(milliseconds: 500);

  final _exposure = TextEditingController();
  final _note = TextEditingController();
  List<CloseoutLineController> _lines = const [];

  /// Live folders — the closeout inherits the same sections every list
  /// reads in. Empty (migrated, tidy-up not run) = flat list. Filled by
  /// [_applyBasis] once the folder/item/snapshot providers have data.
  List<Folder> _folders = const [];

  /// True while no draft and no revision existed at load: only then do
  /// per-event lines default to "didn't count it".
  bool _freshCloseout = false;

  /// One-shot: basis + folder resolution has been applied to [_lines].
  bool _basisApplied = false;

  bool _loading = true;
  bool _loadFailed = false;

  /// Non-null when the event cannot be closed out (planned/cancelled).
  String? _blockedMessage;

  /// True when the event is already closed: confirming appends a revision.
  bool _revising = false;
  int _nextRevision = 1;
  int? _plannedExposure;
  bool _confirmed = false;
  bool _submitting = false;
  Timer? _autosave;

  /// Scanner probe result (read once in initState; false until answered).
  /// The 'Scan to count' action stays hidden until this says yes.
  bool _scanAvailable = false;

  /// Re-entry guard for the scan loop.
  bool _scanning = false;

  /// Resolved while mounted: `dispose()` runs after the element is defunct,
  /// so reading `ref` there throws and the pending draft would be lost.
  CloseoutService? _closeoutService;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_probeScanAvailability());
  }

  /// Reads the scanner probe once (the recipe screen's pattern):
  /// availability is a capability, not an error — the action simply stays
  /// hidden until the probe says yes.
  Future<void> _probeScanAvailability() async {
    final available = await ref.read(barcodeScanServiceProvider).isAvailable();
    if (!mounted) return;
    setState(() => _scanAvailable = available);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _closeoutService = ref.read(closeoutServiceProvider);
  }

  @override
  void dispose() {
    final pendingSave = (_autosave?.isActive ?? false) && !_confirmed;
    _autosave?.cancel();
    final service = _closeoutService;
    if (pendingSave && service != null) {
      // Flush the debounced draft so backing out never loses entries.
      final draft = _buildDraft();
      unawaited(service.saveDraft(draft).catchError((Object _) {}));
    }
    _exposure.dispose();
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final events = ref.read(eventServiceProvider);
      final closeouts = ref.read(closeoutServiceProvider);
      final detail = await events.watchEvent(widget.eventId).first;
      final status = detail.event.status;
      if (status == EventStatus.planned || status == EventStatus.cancelled) {
        if (!mounted) return;
        setState(() {
          _blockedMessage = status == EventStatus.planned
              ? 'Activate this event before closing it out.'
              : 'A cancelled event has no closeout.';
          _loading = false;
        });
        return;
      }
      final prefill = await closeouts.prefill(widget.eventId);
      final draft = await closeouts.loadDraft(widget.eventId);
      var revisions = const <EventCloseout>[];
      if (status == EventStatus.closed) {
        revisions = await closeouts.watchRevisions(widget.eventId).first;
      }
      if (!mounted) return;
      setState(() {
        _revising = status == EventStatus.closed;
        _nextRevision = revisions.isEmpty ? 1 : revisions.first.revision + 1;
        _plannedExposure = prefill.plannedExposure;
        // "Didn't count it" defaults apply to a FRESH closeout only — an
        // autosaved draft or an existing revision already carries the
        // owner's own answers.
        _freshCloseout = draft == null && revisions.isEmpty;
        _lines = [
          for (final line in prefill.lines)
            CloseoutLineController(
              itemId: line.itemId,
              itemName: line.itemName,
              unitLabel: unitFieldLabel(line.unit),
              plannedLoadMicros: line.plannedLoadMicros,
            ),
        ];
        _applyInitial(draft, revisions.isEmpty ? null : revisions.first);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _loading = false;
        });
      }
    }
  }

  /// Resolves every line's demand basis and folder once the watched
  /// providers have data (called from build, one-shot). The latest snapshot
  /// line's STORED basis wins — screens read the resolved value off stored
  /// lines; a line with no snapshot resolves item override → folder default
  /// → per-person via the one resolver. Then, on a fresh closeout only,
  /// per-event lines default to "didn't count it" (recommended: a made-up
  /// count would become permanent history the forecast trusts).
  void _applyBasis(
    List<Folder> folders,
    List<ItemSummary> catalogItems,
    ForecastSnapshotView? snapshot,
  ) {
    final itemsById = {
      for (final summary in catalogItems) summary.item.id.value: summary.item,
    };
    final folderBasisById = {
      for (final folder in folders) folder.id.value: folder.demandBasis,
    };
    final snapshotBasis = {
      for (final line in snapshot?.lines ?? const <ForecastLineView>[])
        line.itemId.value: line.demandBasis,
    };
    for (final line in _lines) {
      final item = itemsById[line.itemId];
      line.folderId = item?.folderId?.value;
      line.demandBasis =
          snapshotBasis[line.itemId] ??
          effectiveDemandBasis(
            itemOverride: item?.demandBasis,
            folderBasis: item?.folderId == null
                ? null
                : folderBasisById[item!.folderId!.value],
          );
      if (_freshCloseout && line.demandBasis == DemandBasis.perEvent) {
        line.skipped = true;
      }
    }
    _folders = folders;
    _basisApplied = true;
  }

  /// Initial values: an autosaved draft wins; otherwise a revise run
  /// prefills from the latest revision; otherwise the planned estimate.
  void _applyInitial(CloseoutFormDraft? draft, EventCloseout? latest) {
    if (draft != null) {
      _exposure.text = draft.confirmedExposure?.toString() ?? '';
      _note.text = draft.note;
      final byId = {for (final line in draft.lines) line.itemId: line};
      for (final line in _lines) {
        final saved = byId[line.itemId];
        if (saved == null) continue;
        _setLine(
          line,
          loaded: saved.loaded,
          returned: saved.returned,
          waste: saved.waste,
          depletion: saved.depletion,
          stockout: saved.stockout,
          approximate: saved.approximate,
          skipped: saved.skipped,
        );
      }
      return;
    }
    if (latest != null) {
      _exposure.text = latest.confirmedExposure.toString();
      _note.text = latest.note;
      final byId = {
        for (final line in latest.lines) line.itemId as String: line,
      };
      for (final line in _lines) {
        final previous = byId[line.itemId];
        if (previous == null) {
          // No line in the latest revision = it was skipped.
          line.skipped = true;
          continue;
        }
        _setLine(
          line,
          loaded: previous.loaded,
          returned: previous.returned,
          waste: previous.waste,
          depletion: previous.depletion,
          stockout: previous.stockout,
          approximate: previous.approximate,
          skipped: false,
        );
      }
      return;
    }
    _exposure.text = _plannedExposure?.toString() ?? '';
  }

  void _setLine(
    CloseoutLineController line, {
    Quantity? loaded,
    Quantity? returned,
    Quantity? waste,
    Quantity? depletion,
    required bool stockout,
    required bool approximate,
    required bool skipped,
  }) {
    if (loaded != null) line.loaded.text = QuantityCodec.format(loaded);
    if (returned != null) line.returned.text = QuantityCodec.format(returned);
    if (waste != null) line.waste.text = QuantityCodec.format(waste);
    final worksheetComplete =
        loaded != null && returned != null && waste != null;
    if (!worksheetComplete && depletion != null) {
      line.depletion.text = QuantityCodec.format(depletion);
    }
    line.stockout = stockout;
    line.approximate = approximate;
    line.skipped = skipped;
    line.worksheetOpen = loaded != null || returned != null || waste != null;
  }

  /// Every edit: rebuild derived displays and (re)schedule the debounced
  /// autosave (§9.1: the closeout controller debounces saveDraft 500 ms).
  void _touched() {
    if (_loading || _confirmed) return;
    setState(() {});
    _autosave?.cancel();
    _autosave = Timer(_autosaveDebounce, _saveDraftNow);
  }

  Future<void> _saveDraftNow() async {
    if (!mounted || _confirmed) return;
    try {
      await ref.read(closeoutServiceProvider).saveDraft(_buildDraft());
    } catch (_) {
      // Autosave is best-effort; the sticky bar still confirms explicitly.
    }
  }

  /// The scan-to-count loop: scanOne → resolve via the barcode → the
  /// matching line in this worksheet → the count sheet → scan again.
  /// The owner cancelling the scanner (or 'Done' on the sheet) stops the
  /// loop silently; a miss re-opens the scanner after its snackbar.
  Future<void> _scanToCount() async {
    if (_scanning) return;
    _scanning = true;
    try {
      final scanner = ref.read(barcodeScanServiceProvider);
      final catalog = ref.read(catalogServiceProvider);
      while (mounted && !_confirmed) {
        final BarcodeScan? scan;
        try {
          scan = await scanner.scanOne();
        } on BarcodeScanException catch (error) {
          if (!mounted) return;
          // Content-free by design: the code picks the copy, and
          // 'camera_denied' points at Settings — nothing else surfaces.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error.code == 'camera_denied'
                    ? 'Camera access is off. Turn it on in Settings.'
                    : "Couldn't open the camera. Try again.",
              ),
            ),
          );
          return;
        }
        if (scan == null || !mounted) return; // cancelled: stop silently
        final item = await catalog.itemByBarcode(scan.payload);
        if (!mounted) return;
        if (item == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("That barcode isn't linked to any item."),
            ),
          );
          continue; // re-open the scanner
        }
        CloseoutLineController? line;
        for (final candidate in _lines) {
          if (candidate.itemId == item.id.value) {
            line = candidate;
            break;
          }
        }
        if (line == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${item.name}" isn\'t on this event\'s list.'),
            ),
          );
          continue; // re-open the scanner
        }
        final scanNext = await _showScanCountSheet(line);
        if (scanNext != true) return; // 'Done' or dismissed: stop the loop
      }
    } finally {
      _scanning = false;
    }
  }

  /// The compact count sheet for one scanned line. Resolves true when the
  /// owner saved and wants the scanner back ('Save & scan next'), false or
  /// null when the session is over.
  Future<bool?> _showScanCountSheet(CloseoutLineController line) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _ScanCountSheet(
          line: line,
          onSave: (returned) => _applyScanCount(line, returned),
        ),
      ),
    );
  }

  /// Writes a scanned "came back" count through the SAME path typing uses:
  /// controllers first, then [_touched] (state recompute + the debounced
  /// autosave). When loaded is blank but a planned load exists, the load
  /// fills from it; and a save through this sheet — only this sheet —
  /// defaults an unset waste to 0 (the sheet caption says so), so a
  /// scan-count alone can complete a line. Without a loaded value the line
  /// just gains its returned count and stays in progress. Scanning a
  /// skipped line means somebody counted it after all, so the skip lifts —
  /// a skipped line would silently record nothing.
  void _applyScanCount(CloseoutLineController line, Quantity returned) {
    line.returned.text = QuantityCodec.format(returned);
    if (line.loaded.text.trim().isEmpty && line.plannedLoadMicros != null) {
      line.loaded.text = QuantityCodec.format(
        Quantity.fromMicros(line.plannedLoadMicros!),
      );
    }
    if (line.loaded.text.trim().isNotEmpty && line.waste.text.trim().isEmpty) {
      line.waste.text = QuantityCodec.format(Quantity.zero);
    }
    line.skipped = false;
    line.worksheetOpen = true;
    _touched();
  }

  CloseoutFormDraft _buildDraft() => CloseoutFormDraft(
    eventId: widget.eventId,
    confirmedExposure: int.tryParse(_exposure.text.trim()),
    note: _note.text.trim(),
    lines: [
      for (final line in _lines)
        CloseoutFormLine(
          itemId: line.itemId,
          loaded: line.loadedQuantity,
          returned: line.returnedQuantity,
          waste: line.wasteQuantity,
          depletion: line.worksheetComplete
              ? line.effectiveDepletion
              : line.directDepletion,
          stockout: line.stockout,
          approximate: line.approximate,
          skipped: line.skipped,
        ),
    ],
  );

  int? get _exposureValue {
    final value = int.tryParse(_exposure.text.trim());
    if (value == null || value < 1 || value > _maxExposure) return null;
    return value;
  }

  bool get _canConfirm =>
      !_submitting &&
      _exposureValue != null &&
      _lines.every((line) => line.done);

  int get _confirmedCount => _lines.where((line) => line.confirmed).length;

  int get _doneCount => _lines.where((line) => line.done).length;

  /// Lines still neither confirmed nor deliberately skipped — the bottom
  /// bar's "2 items not confirmed yet" summary.
  int get _remainingCount => _lines.length - _doneCount;

  Future<void> _confirmFlow(String exposureLabel) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _revising
                    ? 'Confirm revision $_nextRevision?'
                    : 'Confirm this closeout?',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('This becomes the history your forecasts learn from.'),
              const SizedBox(height: 8),
              Text(
                '${_exposureValue ?? '—'} $exposureLabel · '
                '$_confirmedCount of ${_lines.length} items confirmed',
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: primaryButtonMinSize,
                ),
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('Confirm'),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _submitting = true);
    final service = ref.read(closeoutServiceProvider);
    final draft = _buildDraft();
    final result = _revising
        ? await service.revise(draft)
        : await service.confirm(draft);
    if (!mounted) return;
    final receipt = result.fold<CommandReceipt?>((value) => value, (_) => null);
    if (receipt != null) {
      _confirmed = true;
      _autosave?.cancel();
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      // The session commit's haptic (§7: mediumImpact, commit only).
      unawaited(HapticFeedback.mediumImpact());
      await _showCelebration();
      messenger.showSnackBar(SnackBar(content: Text(_receiptMessage(receipt))));
      if (navigator.canPop()) navigator.pop();
    } else {
      setState(() => _submitting = false);
      // Content-free by design (§9.1).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't record this closeout. Try again."),
        ),
      );
    }
  }

  /// The ONE per-session celebration (spec §4): a check disc scaling in and
  /// one line of owner-register copy, self-dismissing. Never stacked,
  /// never per row — it runs only here, on commit success.
  Future<void> _showCelebration() {
    if (_lines.isEmpty || !mounted) return Future<void>.value();
    return showDialog<void>(
      context: context,
      builder: (_) => _CloseoutCelebration(
        confirmedCount: _confirmedCount,
        totalCount: _lines.length,
      ),
    );
  }

  /// Non-blocking receipt warnings (§5: negative on-hand warns, never
  /// blocks — closeout is the label factory).
  String _receiptMessage(CommandReceipt receipt) {
    final base = _revising
        ? 'Closeout revision recorded.'
        : 'Closeout recorded.';
    if (receipt.warnings.contains('NEGATIVE_ON_HAND')) {
      return '$base Some items now show negative on-hand — '
          'record a count to fix.';
    }
    if (receipt.warnings.isNotEmpty) {
      return '$base Recorded with warnings.';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exposureLabel =
        ref.watch(workspaceProvider).valueOrNull?.exposureLabel ?? 'attendance';
    // Folder/item/snapshot projections for the sections and the per-line
    // basis; resolved onto the controllers once, as soon as all three have
    // data (a later basis flip never rewrites a closeout in progress).
    final foldersAsync = ref.watch(eventFoldersProvider);
    final itemsAsync = ref.watch(
      itemListProvider(const ItemFilter(includeArchived: true)),
    );
    final snapshotAsync = ref.watch(latestSnapshotProvider(widget.eventId));
    if (!_basisApplied &&
        !_loading &&
        !_loadFailed &&
        _blockedMessage == null &&
        foldersAsync.hasValue &&
        itemsAsync.hasValue &&
        snapshotAsync.hasValue) {
      _applyBasis(
        foldersAsync.requireValue,
        itemsAsync.requireValue,
        snapshotAsync.requireValue,
      );
    }
    final title = _revising ? 'Revise closeout' : 'Close out';
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const EmptyState(message: 'This closeout could not be loaded.'),
      );
    }
    final blocked = _blockedMessage;
    if (blocked != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(icon: Icons.lock_outline, message: blocked),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          // Probe-gated (like the recipe screen's scanner): hidden until
          // the device says it can present a scanner at all.
          if (_scanAvailable && _lines.isNotEmpty)
            TextButton(
              key: const Key('scan-to-count'),
              onPressed: _scanToCount,
              child: const Text('Scan to count'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Pinned progress header (§4): determinate bar + the fraction
            // in tabular titleMedium, on opaque surfaceContainerLow with a
            // hairline — the floor speaks in "23 of 60", never a percent.
            if (_lines.isNotEmpty) _progressHeader(theme),
            Expanded(child: _formBody(theme, exposureLabel)),
          ],
        ),
      ),
      bottomNavigationBar: _actionBar(theme, exposureLabel),
    );
  }

  Widget _progressHeader(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _lines.isEmpty ? 0 : _doneCount / _lines.length,
            minHeight: 4,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.l,
              vertical: Space.s + 2,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$_confirmedCount of ${_lines.length} confirmed',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: Numerals.tabular,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formBody(ThemeData theme, String exposureLabel) {
    return SingleChildScrollView(
      child: ContentColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_revising) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text('Confirming appends revision $_nextRevision.'),
                  subtitle: const Text(
                    'Earlier revisions stay on record; inventory is '
                    'corrected with mirroring reversals.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _exposure,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Confirmed $exposureLabel',
                helperText: _plannedExposure == null
                    ? 'How many people actually came?'
                    : 'How many people actually came? '
                          'Estimate was $_plannedExposure.',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _touched(),
            ),
            const SizedBox(height: 16),
            if (_lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'This event has no planned items — only the confirmed '
                  '$exposureLabel will be recorded.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              for (final section in sectionEntriesByFolder(
                entries: _lines,
                folders: _folders,
                folderIdOf: (line) => line.folderId,
              )) ...[
                if (_folders.isNotEmpty)
                  _SectionHeader(
                    folder: section.folder,
                    doneCount: section.entries
                        .where((line) => line.done)
                        .length,
                    totalCount: section.entries.length,
                  ),
                for (final line in section.entries)
                  CloseoutLineCard(line: line, onChanged: _touched),
              ],
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _touched(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// The commit bar (§4): a summary line while lines remain, then a plain
  /// 64 dp labeled button — friction is the enablement rule plus the
  /// confirmation sheet, never a hold or a gesture.
  Widget _actionBar(ThemeData theme, String exposureLabel) {
    return FormActionBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_remainingCount > 0) ...[
            Text(
              '$_remainingCount item${_remainingCount == 1 ? '' : 's'} '
              'not confirmed yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: Numerals.tabular,
              ),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
            ),
            onPressed: _canConfirm ? () => _confirmFlow(exposureLabel) : null,
            child: _submitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(_revising ? 'Confirm revision' : 'Finish closeout'),
          ),
        ],
      ),
    );
  }
}

/// One §4 section header on the closeout: 24 dp folder chip + name, and a
/// live "1 of 3" fraction that morphs into a filled check chip reading
/// "Done" the moment every line in the section is handled — fractions
/// always, percentages never.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.folder,
    required this.doneCount,
    required this.totalCount,
  });

  final Folder? folder;
  final int doneCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final complete = doneCount == totalCount;
    final disabled = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          if (folder != null) ...[
            FolderChip.forFolder(folder!, size: FolderChipSize.small),
            const SizedBox(width: Space.s + 2),
          ],
          Expanded(
            child: Text(
              folder?.name ?? 'Unfiled',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          AnimatedSwitcher(
            // Section-complete morph (§7): 200 ms fade + scale.
            duration: disabled
                ? Duration.zero
                : const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: complete
                ? Container(
                    key: const ValueKey('section-done'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.m,
                      vertical: Space.xs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(Radii.small),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check,
                          size: 16,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: Space.xs),
                        Text(
                          'Done',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    '$doneCount of $totalCount',
                    key: const ValueKey('section-fraction'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: Numerals.tabular,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The compact scan-to-count sheet: the item's name, one fraction-capable
/// "How many came back?" count, and two words — 'Save & scan next' keeps
/// the loop going, 'Done' saves whatever is typed and ends it. When the
/// save can complete the line (loaded set, or a planned load about to fill
/// it) the caption says plainly that waste will count as 0 unless set on
/// the card.
class _ScanCountSheet extends StatefulWidget {
  const _ScanCountSheet({required this.line, required this.onSave});

  final CloseoutLineController line;

  /// Fires with the parsed count before the sheet pops; the screen writes
  /// it through the same edit path typing uses.
  final ValueChanged<Quantity> onSave;

  @override
  State<_ScanCountSheet> createState() => _ScanCountSheetState();
}

class _ScanCountSheetState extends State<_ScanCountSheet> {
  /// Prefilled from the line's returned value, if any.
  late final TextEditingController _count = TextEditingController(
    text: widget.line.returned.text,
  );

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Quantity? get _value {
    final text = _count.text.trim();
    return text.isEmpty ? null : QuantityFormField.tryParse(text);
  }

  /// True when saving can complete the line: loaded already holds a value,
  /// or the planned-load prefill is about to fill it — the cases where an
  /// unset waste defaults to 0 on save.
  bool get _completesLine =>
      widget.line.loaded.text.trim().isNotEmpty ||
      widget.line.plannedLoadMicros != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = _value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.line.itemName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            QuantityFormField(
              controller: _count,
              labelText: 'How many came back?',
              unitLabel: widget.line.unitLabel,
              isRequired: false,
              allowZero: true,
              allowFractions: true,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            if (_completesLine) ...[
              const SizedBox(height: 8),
              Text(
                'Waste counts as 0 unless you set it on the card.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
              onPressed: value == null
                  ? null
                  : () {
                      widget.onSave(value);
                      Navigator.of(context).pop(true);
                    },
              child: const Text('Save & scan next'),
            ),
            TextButton(
              onPressed: () {
                final current = _value;
                if (current != null) {
                  widget.onSave(current);
                }
                Navigator.of(context).pop(false);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The §4 celebration: a 48 dp check in a `primaryContainer` disc scaling
/// in (0.6 → 1.0, 350 ms, easeOutBack) with one line of owner-register
/// copy, dismissing itself after a beat. One per session; nothing loops.
class _CloseoutCelebration extends StatefulWidget {
  const _CloseoutCelebration({
    required this.confirmedCount,
    required this.totalCount,
  });

  final int confirmedCount;
  final int totalCount;

  @override
  State<_CloseoutCelebration> createState() => _CloseoutCelebrationState();
}

class _CloseoutCelebrationState extends State<_CloseoutCelebration> {
  double _scale = 0.6;
  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _scale = 1);
      }
    });
    _dismiss = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _scale,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  size: 48,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: Space.l),
            Text(
              'All squared away — ${widget.confirmedCount} of '
              '${widget.totalCount} accounted for.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: Numerals.tabular,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
