/// The only manual ledger entry (design §9 MovementEntryScreen).
///
/// Kinds: Purchase (`receive`), Waste, Count (`adjust`) — nothing else.
/// The UI never does ledger math: Purchase/Waste submit a positive
/// quantity via [InventoryService.record]; Count submits the counted
/// on-hand via [InventoryService.recordCount] and the service derives the
/// signed adjustment. Receipt warnings (NEGATIVE_ON_HAND) surface as a
/// non-blocking snackbar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../catalog/application/catalog_service.dart';
import '../../events/application/event_service.dart';
import '../application/inventory_service.dart';
import '../domain/ledger_math.dart';
import '../domain/movement.dart';
import 'item_picker_sheet.dart';
import 'movement_display.dart';
import '../../../app/widgets/form_action_bar.dart';

class MovementEntryScreen extends ConsumerStatefulWidget {
  const MovementEntryScreen({super.key, this.kind, this.itemId});

  /// `?kind=` prefill: receive | waste | count (adjust).
  final String? kind;

  /// `?itemId=` prefill.
  final String? itemId;

  @override
  ConsumerState<MovementEntryScreen> createState() =>
      _MovementEntryScreenState();
}

class _MovementEntryScreenState extends ConsumerState<MovementEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityCtrl = TextEditingController();
  final _countedCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late MovementKind _kind;
  ItemSummary? _item;
  String? _itemError;
  String? _eventId;
  late DateTime _occurredAt;
  bool _submitting = false;
  bool _itemPrefillResolved = false;
  bool _eventPrefillResolved = false;

  @override
  void initState() {
    super.initState();
    _kind = switch (widget.kind) {
      'waste' => MovementKind.waste,
      'count' || 'adjust' => MovementKind.adjust,
      _ => MovementKind.receive,
    };
    _occurredAt = DateTime.now();
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _countedCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _quantityCtrl.text.isNotEmpty ||
      _countedCtrl.text.isNotEmpty ||
      _noteCtrl.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    _resolvePrefills();
    final item = _item;

    // An empty catalog makes every field on this screen unanswerable: there
    // is nothing to record against. Explain that and offer the way out
    // instead of an item picker that opens onto nothing.
    final catalog = ref.watch(itemListProvider(const ItemFilter()));
    if (catalog.valueOrNull?.isEmpty ?? false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record movement')),
        body: SafeArea(
          child: EmptyState(
            title: 'Add an item first',
            message:
                'Purchases, waste and counts are all recorded against '
                'something you have — its name and how many.',
            actionLabel: 'Add an item',
            onAction: () => context.push('/items/new'),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: _confirmDiscard,
      child: Scaffold(
        appBar: AppBar(title: const Text('Record movement')),
        body: ContentColumn(
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                SegmentedButton<MovementKind>(
                  segments: const [
                    ButtonSegment(
                      value: MovementKind.receive,
                      icon: Icon(Icons.shopping_bag_outlined),
                      label: Text('Purchase'),
                    ),
                    ButtonSegment(
                      value: MovementKind.waste,
                      icon: Icon(Icons.delete_outline),
                      label: Text('Waste'),
                    ),
                    ButtonSegment(
                      value: MovementKind.adjust,
                      icon: Icon(Icons.rule),
                      label: Text('Count'),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (selection) =>
                      setState(() => _kind = selection.first),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickItem,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Item',
                      border: const OutlineInputBorder(),
                      errorText: _itemError,
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    isEmpty: item == null,
                    child: item == null
                        ? null
                        : Text(
                            '${item.item.name} · you have '
                            '${_onHandLabel(item)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_kind == MovementKind.adjust)
                  ..._countFields()
                else
                  QuantityFormField(
                    controller: _quantityCtrl,
                    labelText: 'How many?',
                    onChanged: (_) => setState(() {}),
                  ),
                if (_kind == MovementKind.waste) ...[
                  const SizedBox(height: 16),
                  _eventField(),
                ],
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.today_outlined),
                  title: const Text('Occurred'),
                  subtitle: Text(dateTimeLabel(_occurredAt)),
                  onTap: _pickOccurredDate,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    helperText: 'Stored encrypted, never logged',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 96),
              ],
            ),
          ),
        ),
        bottomNavigationBar: FormActionBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: primaryButtonMinSize,
                ),
                onPressed: _submitting
                    ? null
                    : () => _submit(addAnother: false),
                child: const Text('Record'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _submitting ? null : () => _submit(addAnother: true),
                child: const Text('Record & add another'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _countFields() {
    final item = _item;
    final position = item == null
        ? null
        : ref.watch(stockPositionProvider(item.item.id as String)).valueOrNull;
    final derivedLabel = item == null
        ? '—'
        : position == null
        ? '…'
        : formatSignedMicros(position.onHandMicros, item.item.unit);
    return [
      Text(
        'Loadout has $derivedLabel',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 12),
      QuantityFormField(
        controller: _countedCtrl,
        labelText: 'How many did you count?',
        allowZero: true,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Text(
        _adjustPreview(position),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ];
  }

  /// Signed-adjustment preview ("will record a change of −1.5 kg") —
  /// display only; the service recomputes the delta at submit time.
  String _adjustPreview(StockPosition? position) {
    final item = _item;
    final counted = QuantityFormField.tryParse(_countedCtrl.text);
    if (item == null || position == null || counted == null) {
      return 'Enter what you counted to see the change.';
    }
    final delta = counted.micros - position.onHandMicros;
    if (delta == 0) return 'No change to record.';
    return 'Will record a change of '
        '${formatDeltaMicros(delta, item.item.unit)}';
  }

  Widget _eventField() {
    final events =
        ref.watch(eventListProvider(EventStatusFilter.active)).valueOrNull ??
        const <EventSummary>[];
    return DropdownButtonFormField<String?>(
      // Recreate when the default association resolves (§9: waste defaults
      // to the active event) — FormFields read initialValue only once.
      key: ValueKey(_eventId),
      initialValue: _eventId,
      decoration: const InputDecoration(
        labelText: 'Event (optional)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(child: Text('No event')),
        for (final event in events)
          DropdownMenuItem<String?>(value: event.id, child: Text(event.name)),
      ],
      onChanged: (value) => setState(() => _eventId = value),
    );
  }

  void _resolvePrefills() {
    if (!_itemPrefillResolved) {
      final items = ref.watch(itemListProvider(const ItemFilter())).valueOrNull;
      if (items != null) {
        _itemPrefillResolved = true;
        final wanted = widget.itemId;
        if (wanted != null) {
          for (final summary in items) {
            if (summary.item.id as String == wanted) {
              _item = summary;
              break;
            }
          }
        }
      }
    }
    if (!_eventPrefillResolved) {
      final events = ref
          .watch(eventListProvider(EventStatusFilter.active))
          .valueOrNull;
      if (events != null) {
        _eventPrefillResolved = true;
        // Waste association defaults to the active event (§9).
        if (events.isNotEmpty) _eventId = events.first.id;
      }
    }
  }

  /// Live on-hand, not the value captured when the item was picked: after
  /// "Record & add another" the summary snapshot is a movement out of date.
  String _onHandLabel(ItemSummary item) {
    final live = ref
        .watch(stockPositionProvider(item.item.id as String))
        .valueOrNull;
    return formatSignedMicros(
      live?.onHandMicros ?? item.onHandMicros,
      item.item.unit,
    );
  }

  Future<void> _pickItem() async {
    final picked = await showItemPickerSheet(context);
    if (picked != null && mounted) {
      setState(() {
        _item = picked;
        _itemError = null;
      });
    }
  }

  Future<void> _pickOccurredDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _occurredAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _occurredAt.hour,
          _occurredAt.minute,
        );
      });
    }
  }

  Future<void> _submit({required bool addAnother}) async {
    if (_submitting) return;
    final item = _item;
    if (item == null) {
      setState(() => _itemError = 'Choose an item');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    final service = ref.read(inventoryServiceProvider);
    final note = _noteCtrl.text.trim();
    final itemId = item.item.id as String;

    final result = _kind == MovementKind.adjust
        ? await service.recordCount(
            itemId: itemId,
            countedOnHand: QuantityFormField.tryParse(_countedCtrl.text)!,
            occurredAt: _occurredAt,
            note: note.isEmpty ? null : note,
          )
        : await service.record(
            MovementFormDraft(
              itemId: itemId,
              kind: _kind,
              quantity: QuantityFormField.tryParse(_quantityCtrl.text)!,
              eventId: _kind == MovementKind.waste ? _eventId : null,
              occurredAt: _occurredAt,
              note: note,
            ),
          );
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (receipt) {
        final message = receipt.warnings.contains('NEGATIVE_ON_HAND')
            ? 'Recorded — on hand is now below zero. '
                  'Record a count when you can.'
            : receipt.createdRecordIds.isEmpty
            ? 'On hand already matches your count.'
            : 'Recorded.';
        messenger.showSnackBar(SnackBar(content: Text(message)));
        if (addAnother) {
          setState(() {
            _quantityCtrl.clear();
            _countedCtrl.clear();
            _noteCtrl.clear();
            _submitting = false;
          });
        } else {
          _leave();
        }
      },
      (_) {
        // Content-free by design (§9.1): never echo names or quantities.
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't save this entry. Try again.")),
        );
        setState(() => _submitting = false);
      },
    );
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _confirmDiscard(bool didPop, Object? result) async {
    if (didPop) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this entry?'),
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
    if ((discard ?? false) && mounted) _leave();
  }
}
