/// `/events` (design §9 EventListScreen): `SegmentedButton` status filter
/// (Upcoming / Active / Closed / All), event cards (name, date, status chip
/// — icon + text, never color-only — planned exposure), FAB → `/events/new`.
/// Under All the list is sectioned by status; cancelled events appear there
/// only. No commands — read-only over [eventListProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../application/event_service.dart';
import '../domain/event.dart';
import 'event_ui.dart';

class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen> {
  EventStatusFilter _filter = EventStatusFilter.upcoming;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventListProvider(_filter));
    final exposureLabel =
        ref.watch(workspaceProvider).valueOrNull?.exposureLabel ?? 'attendance';
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay mounted together, so every FAB needs its own
        // hero tag.
        heroTag: 'fab-events',
        onPressed: () => context.push('/events/new'),
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<EventStatusFilter>(
              segments: const [
                ButtonSegment(
                  value: EventStatusFilter.upcoming,
                  label: Text('Upcoming'),
                ),
                ButtonSegment(
                  value: EventStatusFilter.active,
                  label: Text('Active'),
                ),
                ButtonSegment(
                  value: EventStatusFilter.closed,
                  label: Text('Closed'),
                ),
                ButtonSegment(value: EventStatusFilter.all, label: Text('All')),
              ],
              selected: {_filter},
              onSelectionChanged: (selection) =>
                  setState(() => _filter = selection.first),
            ),
          ),
          Expanded(
            child: events.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const EmptyState(message: 'Events could not be loaded.'),
              data: (summaries) => summaries.isEmpty
                  ? _empty(context)
                  : ContentColumn(
                      padding: EdgeInsets.zero,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        children: _filter == EventStatusFilter.all
                            ? _sectioned(context, summaries, exposureLabel)
                            : [
                                for (final summary in summaries)
                                  _EventCard(
                                    summary: summary,
                                    exposureLabel: exposureLabel,
                                  ),
                              ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => switch (_filter) {
    EventStatusFilter.upcoming || EventStatusFilter.all => EmptyState(
      icon: Icons.event_outlined,
      message: 'Plan your first event to get a load list.',
      actionLabel: 'New event',
      onAction: () => context.push('/events/new'),
    ),
    EventStatusFilter.active => const EmptyState(
      icon: Icons.event_outlined,
      message: 'No active events right now.',
    ),
    EventStatusFilter.closed => const EmptyState(
      icon: Icons.event_outlined,
      message: 'No closed events yet — closeouts land here.',
    ),
  };

  /// The All view, sectioned by status in lifecycle order.
  List<Widget> _sectioned(
    BuildContext context,
    List<EventSummary> summaries,
    String exposureLabel,
  ) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (final status in const [
      EventStatus.planned,
      EventStatus.active,
      EventStatus.closed,
      EventStatus.cancelled,
    ]) {
      final section = [
        for (final summary in summaries)
          if (summary.status == status) summary,
      ];
      if (section.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Text(
            eventStatusLabel(status),
            style: theme.textTheme.titleSmall,
          ),
        ),
      );
      widgets.addAll([
        for (final summary in section)
          _EventCard(summary: summary, exposureLabel: exposureLabel),
      ]);
    }
    return widgets;
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.summary, required this.exposureLabel});

  final EventSummary summary;
  final String exposureLabel;

  @override
  Widget build(BuildContext context) {
    final exposure = summary.plannedExposure;
    final subtitle = [
      summary.scheduledDate,
      if (summary.venue != null && summary.venue!.isNotEmpty) summary.venue!,
      if (exposure != null) '$exposure $exposureLabel planned',
    ].join(' · ');
    return Card(
      child: ListTile(
        minVerticalPadding: 12,
        title: Text(summary.name),
        subtitle: Text(subtitle),
        trailing: EventStatusChip(status: summary.status),
        onTap: () => context.push('/events/${summary.id}'),
      ),
    );
  }
}
