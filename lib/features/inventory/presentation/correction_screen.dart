/// Correction form (design §9 CorrectionScreen): a required reason, the
/// prefilled quantity, and TWO plain buttons that say what they do —
/// **Change the number** (reversal + replacement) and **Delete this entry**
/// (reversal only). Either way it is ONE `InventoryService.correct` command
/// (atomic reversal + optional replacement, §5); the buttons replaced a
/// switch labelled "Reverse only (no replacement)", which asked the owner to
/// translate before she could act. Targets the applier refuses — reversals,
/// consume-kind and closeout-linked rows, already-corrected rows — get a
/// clear state message instead of the form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_display.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../events/domain/event.dart';
import '../application/inventory_service.dart';
import '../domain/movement.dart';
import 'movement_display.dart';
import 'movement_providers.dart';

class CorrectionScreen extends ConsumerStatefulWidget {
  const CorrectionScreen({super.key, required this.movementId});

  final String movementId;

  @override
  ConsumerState<CorrectionScreen> createState() => _CorrectionScreenState();
}

class _CorrectionScreenState extends ConsumerState<CorrectionScreen> {
  /// Two forms, because the two buttons ask different questions: deleting
  /// an entry needs a reason and nothing else, so the quantity box must not
  /// be able to block it.
  final _reasonKey = GlobalKey<FormState>();
  final _quantityKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();

  bool _negativeAdjust = false;
  bool _prefilled = false;
  bool _submitting = false;
  String _initialQuantityText = '';

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _quantityCtrl.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _reasonCtrl.text.isNotEmpty || _quantityCtrl.text != _initialQuantityText;

  @override
  Widget build(BuildContext context) {
    final provenance = ref.watch(movementProvenanceProvider(widget.movementId));
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: _confirmDiscard,
      child: Scaffold(
        appBar: AppBar(title: const Text('Correct entry')),
        body: provenance.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text("Couldn't load this entry.")),
          data: (view) {
            if (view == null) {
              return const Center(child: Text('Entry not found.'));
            }
            if (!view.isCorrectable) return _refusalState(view);
            _prefill(view);
            return _form(view);
          },
        ),
      ),
    );
  }

  void _prefill(MovementProvenance view) {
    if (_prefilled) return;
    _prefilled = true;
    _initialQuantityText = QuantityCodec.format(
      Quantity.fromMicros(view.movement.deltaMicros.abs()),
    );
    _quantityCtrl.text = _initialQuantityText;
    _negativeAdjust = view.movement.deltaMicros < 0;
  }

  /// The applier refuses these targets (§5); say so instead of offering
  /// the action.
  Widget _refusalState(MovementProvenance view) {
    final String message;
    if (view.isCloseoutWritten) {
      message =
          'This entry was written by an event closeout and cannot be '
          'corrected here. Revise that event\'s closeout instead.';
    } else if (view.isReversal) {
      message =
          'This is a correction entry. It cannot be corrected again — '
          'record a fresh entry instead.';
    } else {
      message =
          'This entry has already been corrected. The original stays '
          'visible; the correction carries the change.';
    }
    return ContentColumn(
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(MovementProvenance view) {
    final theme = Theme.of(context);
    final movement = view.movement;
    return ContentColumn(
      child: ListView(
        children: [
          Card(
            child: ListTile(
              leading: Icon(movementKindIcon(movement.kind)),
              title: Text(view.itemName),
              subtitle: Text(
                '${movementKindLabel(movement.kind)} · '
                '${dateTimeLabel(instantToLocal(movement.occurredAt))}',
              ),
              trailing: Text(
                formatDeltaMicros(movement.deltaMicros, view.itemUnit),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The original stays on record.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Form(
            key: _reasonKey,
            child: TextFormField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason',
                helperText: 'Why the original entry was wrong',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              validator: (text) => (text ?? '').trim().isEmpty
                  ? 'Enter a reason for the correction'
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Form(
            key: _quantityKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QuantityFormField(
                  controller: _quantityCtrl,
                  labelText: 'Corrected quantity',
                  unitLabel: unitFieldLabel(view.itemUnit),
                  onChanged: (_) => setState(() {}),
                ),
                if (movement.kind == MovementKind.adjust) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.add),
                        label: Text('Add to stock'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.remove),
                        label: Text('Remove from stock'),
                      ),
                    ],
                    selected: {_negativeAdjust},
                    onSelectionChanged: (selection) =>
                        setState(() => _negativeAdjust = selection.first),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // The two things she can actually mean, each on its own button.
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            onPressed: _submitting ? null : () => _submit(view, replace: true),
            child: const Text('Change the number'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: primaryButtonMinSize),
            onPressed: _submitting ? null : () => _submit(view, replace: false),
            child: const Text('Delete this entry'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// [replace] true = "Change the number" (reversal + replacement); false =
  /// "Delete this entry" (reversal only). Both are the same one command —
  /// the buttons only decide whether it carries a replacement.
  Future<void> _submit(MovementProvenance view, {required bool replace}) async {
    if (_submitting) return;
    final reasonOk = _reasonKey.currentState?.validate() ?? false;
    // Deleting needs a reason and nothing else: the quantity box is not
    // part of that answer, so it never gets to block it.
    final quantityOk =
        !replace || (_quantityKey.currentState?.validate() ?? false);
    if (!reasonOk || !quantityOk) return;
    setState(() => _submitting = true);

    final movement = view.movement;
    // A replacement is a NEW movement, and new movements may not attach to an
    // event that is no longer open (§12.14). Carrying the original's link
    // over would make every correction of an event-linked waste fail once
    // that event closes, so the link is dropped and the user is told.
    final linkedEventId = movement.kind == MovementKind.waste
        ? movement.eventId as String?
        : null;
    final eventStillOpen =
        linkedEventId == null || await _eventAcceptsMovements(linkedEventId);
    if (!mounted) return;
    final replacement = !replace
        ? null
        : MovementFormDraft(
            itemId: movement.itemId as String,
            kind: movement.kind,
            quantity: QuantityFormField.tryParse(_quantityCtrl.text)!,
            negativeAdjust: _negativeAdjust,
            eventId: eventStillOpen ? linkedEventId : null,
            occurredAt: instantToLocal(movement.occurredAt),
            note: movement.note,
          );
    final droppedEventLink =
        replacement != null && linkedEventId != null && !eventStillOpen;
    final result = await ref
        .read(inventoryServiceProvider)
        .correct(
          movementId: widget.movementId,
          replacement: replacement,
          reason: _reasonCtrl.text.trim(),
        );
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (receipt) {
        final String message;
        if (receipt.warnings.contains('NEGATIVE_ON_HAND')) {
          message = 'Correction recorded — on hand is now below zero.';
        } else if (droppedEventLink) {
          message =
              'Correction recorded. Its event is closed, so the new entry '
              'is not linked to it.';
        } else {
          message = 'Correction recorded.';
        }
        messenger.showSnackBar(SnackBar(content: Text(message)));
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/activity');
        }
      },
      (_) {
        // Content-free by design (§9.1). Refusal states (e.g. corrected
        // elsewhere meanwhile) re-render through the provenance stream.
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't save this entry. Try again.")),
        );
        setState(() => _submitting = false);
      },
    );
  }

  /// Whether [eventId] still accepts new movements (planned or active).
  /// Unknown events answer "no" — the applier would refuse either way.
  Future<bool> _eventAcceptsMovements(String eventId) async {
    try {
      final detail = await ref
          .read(eventServiceProvider)
          .watchEvent(eventId)
          .first;
      final status = detail.event.status;
      return status == EventStatus.planned || status == EventStatus.active;
    } catch (_) {
      return false;
    }
  }

  Future<void> _confirmDiscard(bool didPop, Object? result) async {
    if (didPop) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this correction?'),
        content: const Text('Nothing has been recorded yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if ((discard ?? false) && mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/activity');
      }
    }
  }
}
