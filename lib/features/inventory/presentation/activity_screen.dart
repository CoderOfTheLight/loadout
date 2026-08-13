/// Global movement log (design §9 ActivityScreen): newest first,
/// day-grouped, `FilterChip`s for kind/item/event. Reversed rows are
/// struck through with "Corrected"; reversal rows read "Correction of an
/// earlier entry". Read-only — corrections start from the detail screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../catalog/application/catalog_service.dart';
import '../../events/application/event_service.dart';
import '../application/inventory_service.dart';
import '../domain/movement.dart';
import 'item_picker_sheet.dart';
import 'movement_display.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  static const _kindChips = [
    (MovementKind.receive, 'Purchases'),
    (MovementKind.waste, 'Waste'),
    (MovementKind.adjust, 'Counts'),
    (MovementKind.consume, 'Closeouts'),
    (MovementKind.reversal, 'Corrections'),
  ];

  final Set<MovementKind> _kinds = {};
  ItemSummary? _itemFilter;
  EventSummary? _eventFilter;

  /// Memoized so the provider family key is stable across rebuilds.
  MovementFilter _filter = const MovementFilter();

  void _applyFilter() => setState(() {
    _filter = MovementFilter(
      itemId: _itemFilter == null ? null : _itemFilter!.item.id as String,
      eventId: _eventFilter?.id,
      kinds: _kinds.isEmpty ? null : Set.of(_kinds),
    );
  });

  @override
  Widget build(BuildContext context) {
    final movements = ref.watch(movementLogProvider(_filter));
    final eventNames = {
      for (final event
          in ref.watch(eventListProvider(EventStatusFilter.all)).valueOrNull ??
              const <EventSummary>[])
        event.id: event.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        // `/activity` is a root-level route with no tab bar, and
        // CorrectionScreen lands here with `go` (not `push`) when it has
        // nothing to pop back to — which leaves no automatic back button
        // either. Offer the way out explicitly rather than stranding the
        // owner in the log.
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.home_outlined),
                tooltip: 'Home',
                onPressed: () => context.go('/home'),
              ),
      ),
      body: Column(
        children: [
          _filterRow(),
          Expanded(
            child: movements.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text("Couldn't load activity.")),
              data: (views) => views.isEmpty
                  ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: _filterActive
                          ? 'No entries match these filters.'
                          : 'Every purchase, waste, count, and closeout '
                                'lands here — permanently.',
                    )
                  : ContentColumn(
                      padding: EdgeInsets.zero,
                      child: _groupedList(views, eventNames),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _filterActive =>
      _kinds.isNotEmpty || _itemFilter != null || _eventFilter != null;

  Widget _filterRow() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        for (final (kind, label) in _kindChips) ...[
          FilterChip(
            avatar: Icon(movementKindIcon(kind), size: 18),
            label: Text(label),
            selected: _kinds.contains(kind),
            onSelected: (selected) {
              selected ? _kinds.add(kind) : _kinds.remove(kind);
              _applyFilter();
            },
          ),
          const SizedBox(width: 8),
        ],
        FilterChip(
          avatar: const Icon(Icons.inventory_2_outlined, size: 18),
          label: Text(
            _itemFilter == null ? 'Item' : 'Item: ${_itemFilter!.item.name}',
          ),
          selected: _itemFilter != null,
          onSelected: (_) => _pickItemFilter(),
        ),
        const SizedBox(width: 8),
        FilterChip(
          avatar: const Icon(Icons.event_outlined, size: 18),
          label: Text(
            _eventFilter == null ? 'Event' : 'Event: ${_eventFilter!.name}',
          ),
          selected: _eventFilter != null,
          onSelected: (_) => _pickEventFilter(),
        ),
      ],
    ),
  );

  Future<void> _pickItemFilter() async {
    if (_itemFilter != null) {
      _itemFilter = null;
      _applyFilter();
      return;
    }
    final picked = await showItemPickerSheet(context);
    if (picked != null && mounted) {
      _itemFilter = picked;
      _applyFilter();
    }
  }

  Future<void> _pickEventFilter() async {
    if (_eventFilter != null) {
      _eventFilter = null;
      _applyFilter();
      return;
    }
    final events =
        ref.read(eventListProvider(EventStatusFilter.all)).valueOrNull ??
        const <EventSummary>[];
    final picked = await showModalBottomSheet<EventSummary>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: events.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No events yet.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final event in events)
                    ListTile(
                      minTileHeight: 56,
                      title: Text(event.name),
                      subtitle: Text(event.scheduledDate),
                      onTap: () => Navigator.of(context).pop(event),
                    ),
                ],
              ),
      ),
    );
    if (picked != null && mounted) {
      _eventFilter = picked;
      _applyFilter();
    }
  }

  Widget _groupedList(
    List<MovementView> views,
    Map<String, String> eventNames,
  ) {
    final children = <Widget>[];
    String? currentDay;
    for (final view in views) {
      final local = instantToLocal(view.movement.occurredAt);
      final label = dayLabel(local);
      if (label != currentDay) {
        currentDay = label;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final eventId = view.movement.eventId as String?;
      children.add(
        MovementRow(
          view: view,
          eventName: eventId == null ? null : eventNames[eventId],
          onTap: () => context.push('/movements/${view.movement.id}'),
        ),
      );
    }
    return ListView(children: children);
  }
}
