/// "What needs attention now" (design §9 HomeScreen). Read-only dashboard,
/// in priority order: (1) pending-closeout nudges for active events past
/// their date; (2) next-event card with forecast readiness; (3) quick
/// actions; (4) data health — items with negative derived on-hand;
/// (5) last five movements + "See all". No commands are issued here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../catalog/application/catalog_service.dart';
import '../../events/application/event_service.dart';
import '../../forecasting/domain/forecast_engine.dart';
import '../../inventory/application/inventory_service.dart';
import '../../inventory/presentation/movement_display.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemListProvider(const ItemFilter()));
    final active = ref.watch(eventListProvider(EventStatusFilter.active));
    final upcoming = ref.watch(eventListProvider(EventStatusFilter.upcoming));
    final recent = ref.watch(
      movementLogProvider(const MovementFilter(limit: 5)),
    );

    final Widget body;
    if (items.hasError ||
        active.hasError ||
        upcoming.hasError ||
        recent.hasError) {
      body = const Center(child: Text("Couldn't load your workspace."));
    } else if (items.valueOrNull == null ||
        active.valueOrNull == null ||
        upcoming.valueOrNull == null ||
        recent.valueOrNull == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _Dashboard(
        items: items.value!,
        activeEvents: active.value!,
        upcomingEvents: upcoming.value!,
        recentMovements: recent.value!,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: body,
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({
    required this.items,
    required this.activeEvents,
    required this.upcomingEvents,
    required this.recentMovements,
  });

  final List<ItemSummary> items;
  final List<EventSummary> activeEvents;
  final List<EventSummary> upcomingEvents;
  final List<MovementView> recentMovements;

  static String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty &&
        activeEvents.isEmpty &&
        upcomingEvents.isEmpty &&
        recentMovements.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'Start by adding the items you bring to events',
        actionLabel: 'Add item',
        onAction: () => context.push('/items/new'),
      );
    }

    final today = _today();
    // Most important nudge in the app: activated but never closed out.
    final pendingCloseouts = [
      for (final event in activeEvents)
        if (event.scheduledDate.compareTo(today) < 0) event,
    ];
    final nextEvent = _nextEvent(today);
    final negatives = [
      for (final summary in items)
        if (summary.isNegative) summary,
    ];

    return ContentColumn(
      child: ListView(
        children: [
          for (final event in pendingCloseouts) ...[
            _closeoutNudge(context, event),
            const SizedBox(height: 12),
          ],
          if (nextEvent != null) ...[
            _nextEventCard(context, ref, nextEvent),
            const SizedBox(height: 12),
          ],
          _quickActions(context),
          if (negatives.isNotEmpty) ...[
            const SizedBox(height: 12),
            _dataHealthCard(context, negatives),
          ],
          const SizedBox(height: 16),
          _recentActivity(context, ref),
        ],
      ),
    );
  }

  EventSummary? _nextEvent(String today) {
    final candidates = [
      for (final event in [...upcomingEvents, ...activeEvents])
        if (event.scheduledDate.compareTo(today) >= 0) event,
    ]..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    return candidates.isEmpty ? null : candidates.first;
  }

  Widget _closeoutNudge(BuildContext context, EventSummary event) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Card(
        color: scheme.primaryContainer,
        child: InkWell(
          onTap: () => context.push('/events/${event.id}/closeout'),
          child: ListTile(
            minTileHeight: 56,
            leading: Icon(Icons.fact_check_outlined, color: scheme.primary),
            title: Text('Close out ${event.name}'),
            subtitle: Text(
              'Held ${event.scheduledDate} — confirm what was used so '
              'your forecasts can learn from it.',
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }

  Widget _nextEventCard(
    BuildContext context,
    WidgetRef ref,
    EventSummary event,
  ) {
    final snapshot = ref.watch(latestSnapshotProvider(event.id));
    final readiness = snapshot.when(
      loading: () => '…',
      error: (_, _) => 'Forecast unavailable',
      data: (view) {
        if (view == null || view.lines.isEmpty) {
          return 'No forecast yet — generate one from the event page.';
        }
        final noHistory = view.lines
            .where(
              (line) => line.evidenceGrade == EvidenceGrade.insufficientData,
            )
            .length;
        if (noHistory > 0) {
          return '$noHistory of ${view.lines.length} items have no history';
        }
        return 'Forecast ready · ${view.lines.length} items';
      },
    );
    return Semantics(
      button: true,
      child: Card(
        child: InkWell(
          onTap: () => context.push('/events/${event.id}'),
          child: ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.event_outlined),
            title: Text(event.name),
            subtitle: Text('${event.scheduledDate} · $readiness'),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.tonalIcon(
        style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
        icon: const Icon(Icons.shopping_bag_outlined),
        label: const Text('Record purchase'),
        onPressed: () => context.push('/movements/new?kind=receive'),
      ),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
        icon: const Icon(Icons.rule),
        label: const Text('Count stock'),
        onPressed: () => context.push('/movements/new?kind=count'),
      ),
    ],
  );

  Widget _dataHealthCard(BuildContext context, List<ItemSummary> negatives) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: scheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Data health',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
          for (final summary in negatives)
            Semantics(
              button: true,
              child: ListTile(
                minTileHeight: 56,
                title: Text(
                  '${summary.item.name} shows '
                  '${formatSignedMicros(summary.onHandMicros, summary.item.unit)}'
                  ' — record a count to fix',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  '/movements/new?kind=count'
                  '&itemId=${summary.item.id as String}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recentActivity(BuildContext context, WidgetRef ref) {
    final eventNames = {
      for (final event
          in ref.watch(eventListProvider(EventStatusFilter.all)).valueOrNull ??
              const <EventSummary>[])
        event.id: event.name,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/activity'),
              child: const Text('See all'),
            ),
          ],
        ),
        if (recentMovements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No movements yet. Record a purchase or a count to '
              'establish on-hand.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          for (final view in recentMovements)
            MovementRow(
              view: view,
              eventName: view.movement.eventId == null
                  ? null
                  : eventNames[view.movement.eventId as String],
              onTap: () => context.push('/movements/${view.movement.id}'),
            ),
      ],
    );
  }
}
