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
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../approval/domain/proposal.dart';
import '../../events/domain/event.dart';
import '../application/closeout_service.dart';
import '../domain/closeout.dart';
import '../domain/closeout_form.dart';
import 'closeout_line_card.dart';

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

  /// Resolved while mounted: `dispose()` runs after the element is defunct,
  /// so reading `ref` there throws and the pending draft would be lost.
  CloseoutService? _closeoutService;

  @override
  void initState() {
    super.initState();
    _load();
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
        _lines = [
          for (final line in prefill.lines)
            CloseoutLineController(
              itemId: line.itemId,
              itemName: line.itemName,
              unitLabel: line.unit.dbValue,
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
    result.fold(
      (receipt) {
        _confirmed = true;
        _autosave?.cancel();
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(content: Text(_receiptMessage(receipt))),
        );
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
      },
      (_) {
        setState(() => _submitting = false);
        // Content-free by design (§9.1).
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't record this closeout. Try again."),
          ),
        );
      },
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
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_revising) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.history_outlined),
                      title: Text(
                        'Confirming appends revision $_nextRevision.',
                      ),
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
                  for (final line in _lines)
                    CloseoutLineCard(line: line, onChanged: _touched),
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
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$_confirmedCount of ${_lines.length} items confirmed',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: primaryButtonMinSize,
                  ),
                  onPressed: _canConfirm
                      ? () => _confirmFlow(exposureLabel)
                      : null,
                  child: _submitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(
                          _revising ? 'Confirm revision' : 'Confirm closeout',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
