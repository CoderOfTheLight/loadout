/// The only manual ledger entry (design §9 MovementEntryScreen) — THREE
/// plain screens, one per `?kind=`, chosen by the link that got here:
///
///   * `?kind=count`   → **Count what you have** (`adjust`)
///   * `?kind=receive` → **Something arrived** (the default)
///   * `?kind=waste`   → **Something was thrown out**
///
/// There is no kind picker: a screen that has to be configured before its
/// form makes sense is a screen the owner has to think about. Each one asks
/// for an item, one number, and an optional note; the date defaults to now
/// and lives in the overflow ("Change the date").
///
/// The UI never does ledger math: arrived/thrown-out submit a positive
/// quantity via [InventoryService.record]; a count submits the counted
/// on-hand via [InventoryService.recordCount] and the service derives the
/// signed adjustment. Receipt warnings (NEGATIVE_ON_HAND) surface as a
/// non-blocking snackbar. Waste keeps its silent association with the
/// active event (§9) — recorded, never asked.
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

  /// `?kind=` — which of the three screens this is: receive | waste |
  /// count (adjust). Unknown or absent reads as `receive`.
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

  /// Fixed by the route for this screen's whole life — there is no control
  /// that changes it.
  late final MovementKind _kind;
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

  /// What this screen is called, in the words of what happened.
  String get _title => switch (_kind) {
    MovementKind.adjust => 'Count what you have',
    MovementKind.waste => 'Something was thrown out',
    _ => 'Something arrived',
  };

  /// The label over this screen's one number.
  String get _quantityLabel => switch (_kind) {
    MovementKind.waste => 'How many were thrown out?',
    _ => 'How many arrived?',
  };

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
        appBar: AppBar(title: Text(_title)),
        body: SafeArea(
          child: EmptyState(
            title: 'Add an item first',
            message:
                'Counts, arrivals and waste are all recorded against '
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
        appBar: AppBar(
          title: Text(_title),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (action) {
                if (action == 'date') {
                  _pickOccurredDate();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'date', child: Text('Change the date')),
              ],
            ),
          ],
        ),
        body: ContentColumn(
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
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
                    labelText: _quantityLabel,
                    onChanged: (_) => setState(() {}),
                  ),
                // The date is today unless she said otherwise, and it only
                // takes up a line once she has.
                if (!_isToday(_occurredAt)) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Dated ${dateTimeLabel(_occurredAt)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
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
                child: const Text('Save and do another'),
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
        'You have $derivedLabel',
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

  /// What the count will do, said the way a person would say it ("That's 7
  /// fewer than before") — display only; the service recomputes the delta
  /// at submit time.
  String _adjustPreview(StockPosition? position) {
    final item = _item;
    final counted = QuantityFormField.tryParse(_countedCtrl.text);
    if (item == null || position == null || counted == null) {
      return 'Enter what you counted to see the change.';
    }
    final delta = counted.micros - position.onHandMicros;
    if (delta == 0) return 'No change to record.';
    final magnitude = formatSignedMicros(delta.abs(), item.item.unit);
    return delta < 0
        ? "That's $magnitude fewer than before"
        : "That's $magnitude more than before";
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
    if (!_eventPrefillResolved && _kind == MovementKind.waste) {
      final events = ref
          .watch(eventListProvider(EventStatusFilter.active))
          .valueOrNull;
      if (events != null) {
        _eventPrefillResolved = true;
        // Waste association defaults to the active event (§9) — the same
        // default as before, now silent instead of a dropdown she has to
        // read and leave alone.
        if (events.isNotEmpty) _eventId = events.first.id;
      }
    }
  }

  /// Live on-hand, not the value captured when the item was picked: after
  /// "Save and do another" the summary snapshot is a movement out of date.
  String _onHandLabel(ItemSummary item) {
    final live = ref
        .watch(stockPositionProvider(item.item.id as String))
        .valueOrNull;
    return formatSignedMicros(
      live?.onHandMicros ?? item.onHandMicros,
      item.item.unit,
    );
  }

  static bool _isToday(DateTime value) {
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
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
