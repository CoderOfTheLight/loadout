/// `/events/new` and `/events/:eventId/edit` (design §9 EventEditScreen):
/// name, scheduled date (`showDatePicker` → stored TEXT `YYYY-MM-DD`),
/// planned exposure (digits-only integer, label from the `exposure_label`
/// setting; optional at create — required before forecasting), venue, notes,
/// and the planned-items multi-select (bottom sheet over the live catalog,
/// chips inline). Commands: `EventService.createEvent` / `updateEvent`.
/// Editing is allowed while planned/active only (§12.14: closed events are
/// permanently locked; cancelled events reject writes).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../catalog/application/catalog_service.dart';
import '../domain/event.dart';
import 'event_ui.dart';
import 'planned_items_picker.dart';
import '../../../app/widgets/form_action_bar.dart';

class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({super.key, this.eventId});

  /// Null for `/events/new`.
  final String? eventId;

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  static const int _maxExposure = 1000000;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _date = TextEditingController(
    text: widget.eventId == null ? todayYmd() : '',
  );
  final _exposure = TextEditingController();
  final _venue = TextEditingController();
  final _notes = TextEditingController();
  List<String> _plannedItemIds = const [];

  bool get _isEdit => widget.eventId != null;
  late bool _loading = _isEdit;
  bool _loadFailed = false;
  EventStatus _status = EventStatus.planned;
  bool _dirty = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _date.dispose();
    _exposure.dispose();
    _venue.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await ref
          .read(eventServiceProvider)
          .watchEvent(widget.eventId!)
          .first;
      if (!mounted) return;
      final event = detail.event;
      setState(() {
        _name.text = event.name;
        _date.text = event.scheduledDate;
        _exposure.text = event.plannedExposure?.toString() ?? '';
        _venue.text = event.venue ?? '';
        _notes.text = event.notes ?? '';
        _plannedItemIds = [for (final id in event.plannedItemIds) id as String];
        _status = event.status;
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

  void _touched() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _pickDate() async {
    final initial = parseYmd(_date.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _date.text = formatYmd(picked);
        _dirty = true;
      });
    }
  }

  Future<void> _pickPlannedItems() async {
    final selection = await showPlannedItemsPicker(
      context,
      selected: _plannedItemIds,
    );
    if (selection != null && mounted) {
      setState(() {
        _plannedItemIds = selection;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final venue = _venue.text.trim();
    final notes = _notes.text.trim();
    final exposureText = _exposure.text.trim();
    final draft = EventDraft(
      name: _name.text.trim(),
      scheduledDate: _date.text,
      plannedExposure: exposureText.isEmpty ? null : int.parse(exposureText),
      venue: venue.isEmpty ? null : venue,
      notes: notes.isEmpty ? null : notes,
      plannedItemIds: _plannedItemIds,
    );
    final service = ref.read(eventServiceProvider);
    if (_isEdit) {
      final result = await service.updateEvent(
        eventId: widget.eventId!,
        draft: draft,
      );
      if (!mounted) return;
      result.fold((_) {
        _dirty = false;
        Navigator.of(context).pop();
      }, (_) => _saveFailed());
    } else {
      final result = await service.createEvent(draft);
      if (!mounted) return;
      result.fold((eventId) {
        _dirty = false;
        context.go('/events/$eventId');
      }, (_) => _saveFailed());
    }
  }

  /// Content-free failure snackbar (§9.1 cross-cutting UX).
  void _saveFailed() {
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't save this event. Try again.")),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Nothing has been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if ((discard ?? false) && mounted) {
      // Force-pop past the PopScope guard.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final exposureLabel =
        ref.watch(workspaceProvider).valueOrNull?.exposureLabel ?? 'attendance';
    final catalogIsEmpty =
        ref.watch(itemListProvider(const ItemFilter())).valueOrNull?.isEmpty ??
        false;
    final title = _isEdit ? 'Edit event' : 'New event';
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const EmptyState(message: 'This event could not be loaded.'),
      );
    }
    if (_status == EventStatus.closed || _status == EventStatus.cancelled) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(
          icon: Icons.lock_outline,
          message:
              'This event is ${eventStatusLabel(_status).toLowerCase()} and '
              'can no longer be edited.',
        ),
      );
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
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
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _touched(),
                      validator: (text) {
                        final trimmed = (text ?? '').trim();
                        if (trimmed.isEmpty) return 'Enter a name';
                        if (trimmed.length > 120) {
                          return 'Keep the name under 120 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _date,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (text) => parseYmd((text ?? '').trim()) == null
                          ? 'Pick a date'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _exposure,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Expected $exposureLabel',
                        helperText:
                            'Optional now — required before forecasting.',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => _touched(),
                      validator: (text) {
                        final trimmed = (text ?? '').trim();
                        if (trimmed.isEmpty) return null;
                        final value = int.tryParse(trimmed);
                        if (value == null ||
                            value < 1 ||
                            value > _maxExposure) {
                          return 'Enter a number from 1 to 1,000,000';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _venue,
                      decoration: const InputDecoration(
                        labelText: 'Venue (optional)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _touched(),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Planned items',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    // With nothing to pick, the picker would open onto an
                    // empty checklist: this section explains itself instead.
                    // The rest of the event stays answerable, and an event
                    // that already has items keeps its chips (and the way to
                    // remove them) even if every item was since archived.
                    if (catalogIsEmpty && _plannedItemIds.isEmpty)
                      _EmptyCatalogNote(
                        onAddItem: () => context.push('/items/new'),
                      )
                    else ...[
                      _PlannedItemChips(
                        plannedItemIds: _plannedItemIds,
                        onRemove: (itemId) => setState(() {
                          _plannedItemIds = [
                            for (final id in _plannedItemIds)
                              if (id != itemId) id,
                          ];
                          _dirty = true;
                        }),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _pickPlannedItems,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Add items'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _touched(),
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
                : const Text('Save event'),
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the planned-items picker when the catalog is empty:
/// the picker would open onto an empty checklist, which explains nothing.
class _EmptyCatalogNote extends StatelessWidget {
  const _EmptyCatalogNote({required this.onAddItem});

  final VoidCallback onAddItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have no items yet. Add what you will bring — its name '
              'and how many you have — then plan it into this event.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddItem,
              icon: const Icon(Icons.add),
              label: const Text('Add an item'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline chips for the current selection; names resolved from the catalog
/// (archived included so a stale selection still renders).
class _PlannedItemChips extends ConsumerWidget {
  const _PlannedItemChips({
    required this.plannedItemIds,
    required this.onRemove,
  });

  final List<String> plannedItemIds;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plannedItemIds.isEmpty) {
      return Text(
        'No items planned yet.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final items =
        ref
            .watch(itemListProvider(const ItemFilter(includeArchived: true)))
            .valueOrNull ??
        const <ItemSummary>[];
    final namesById = {
      for (final summary in items) summary.item.id as String: summary.item.name,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final itemId in plannedItemIds)
          InputChip(
            label: Text(namesById[itemId] ?? 'Item'),
            onDeleted: () => onRemove(itemId),
            deleteButtonTooltipMessage: 'Remove from plan',
          ),
      ],
    );
  }
}
