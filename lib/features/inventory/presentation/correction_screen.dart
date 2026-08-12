/// Correction form (design §9 CorrectionScreen): prefilled replacement +
/// required reason + "Reverse only (no replacement)" toggle, submitted as
/// ONE `InventoryService.correct` command (atomic reversal + optional
/// replacement, §5). Targets the applier refuses — reversals, consume-kind
/// and closeout-linked rows, already-corrected rows — get a clear state
/// message instead of the form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();

  bool _reverseOnly = false;
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
      child: Form(
        key: _formKey,
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
              'Corrections keep the original entry visible and add a '
              'reversing entry.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
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
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reverse only (no replacement)'),
              subtitle: const Text(
                'Undo the entry without recording a corrected one',
              ),
              value: _reverseOnly,
              onChanged: (value) => setState(() => _reverseOnly = value),
            ),
            if (!_reverseOnly) ...[
              const SizedBox(height: 8),
              QuantityFormField(
                controller: _quantityCtrl,
                labelText: 'Corrected quantity',
                helperText:
                    'Replaces the original '
                    '${movementKindLabel(movement.kind).toLowerCase()} entry',
                unitLabel: view.itemUnit.dbValue,
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
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
              onPressed: _submitting ? null : () => _submit(view),
              child: const Text('Record correction'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(MovementProvenance view) async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);

    final movement = view.movement;
    final replacement = _reverseOnly
        ? null
        : MovementFormDraft(
            itemId: movement.itemId as String,
            kind: movement.kind,
            quantity: QuantityFormField.tryParse(_quantityCtrl.text)!,
            negativeAdjust: _negativeAdjust,
            eventId: movement.kind == MovementKind.waste
                ? movement.eventId as String?
                : null,
            occurredAt: instantToLocal(movement.occurredAt),
            note: movement.note,
          );
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
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              receipt.warnings.contains('NEGATIVE_ON_HAND')
                  ? 'Correction recorded — on hand is now below zero.'
                  : 'Correction recorded.',
            ),
          ),
        );
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
