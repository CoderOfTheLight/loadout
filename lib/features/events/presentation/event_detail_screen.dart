/// `/events/:eventId` (design §9 EventDetailScreen): the lifecycle hub.
/// Header (name, date, status chip, planned exposure); tiles for Forecast &
/// load list (method/version caption from the latest snapshot row — never
/// hardcoded), Close out (primary-styled once the date passes; closed events
/// show `Closed on <date>` + Revise), the disabled Production tile, and
/// Accuracy review (closed only). Planned items and, for closed events, the
/// closeout revisions summary. App-bar: Edit; Activate (planned → active);
/// Cancel (planned ONLY — an activated event must be closed out, §12.15).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/folder.dart';
import '../application/event_service.dart';
import '../domain/event.dart';
import 'event_ui.dart';
import 'folder_sections.dart';

/// True while an activate command is in flight for this event. The button
/// is stateless, so without this a double tap sends two commands: the
/// second is validated against the already-active event and rejected,
/// reporting a failure for an activation that actually succeeded.
final _activatingProvider = StateProvider.autoDispose.family<bool, String>(
  (ref, eventId) => false,
);

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(eventDetailProvider(eventId));
    return detail.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Event')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Event')),
        body: const EmptyState(message: 'This event could not be loaded.'),
      ),
      data: (data) => _EventDetailBody(eventId: eventId, detail: data),
    );
  }
}

class _EventDetailBody extends ConsumerWidget {
  const _EventDetailBody({required this.eventId, required this.detail});

  final String eventId;
  final EventDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final event = detail.event;
    final exposureLabel =
        ref.watch(workspaceProvider).valueOrNull?.exposureLabel ?? 'attendance';
    final snapshot = ref.watch(latestSnapshotProvider(eventId)).valueOrNull;
    final datePassed = event.scheduledDate.compareTo(todayYmd()) <= 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(event.name),
        actions: [
          if (event.status == EventStatus.planned ||
              event.status == EventStatus.active)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => context.push('/events/$eventId/edit'),
            ),
          if (event.status == EventStatus.planned)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'cancel') _cancelFlow(context, ref);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'cancel', child: Text('Cancel event…')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(theme, event, exposureLabel),
                const SizedBox(height: 16),
                if (event.status == EventStatus.planned) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                    ),
                    onPressed: ref.watch(_activatingProvider(eventId))
                        ? null
                        : () => _activate(context, ref),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Activate event'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (event.status != EventStatus.cancelled) ...[
                  Card(
                    child: ListTile(
                      minVerticalPadding: 12,
                      leading: const Icon(Icons.insights_outlined),
                      title: const Text('Forecast & load list'),
                      subtitle: Text(
                        snapshot == null
                            ? 'No forecast yet'
                            : '${snapshot.method} v${snapshot.methodVersion} · '
                                  'for ${snapshot.upcomingExposure} '
                                  '$exposureLabel',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/events/$eventId/forecast'),
                    ),
                  ),
                  _closeoutTile(context, theme, event, datePassed),
                  Card(
                    child: Semantics(
                      label:
                          'Production planning, available in a future update',
                      child: const ListTile(
                        minVerticalPadding: 12,
                        enabled: false,
                        leading: Icon(Icons.factory_outlined),
                        title: Text('Production plan'),
                        subtitle: Text('Coming soon'),
                      ),
                    ),
                  ),
                  if (event.status == EventStatus.closed)
                    Card(
                      child: ListTile(
                        minVerticalPadding: 12,
                        leading: const Icon(Icons.query_stats_outlined),
                        title: const Text('Accuracy review'),
                        subtitle: const Text('Forecast vs what actually sold'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/events/$eventId/forecast'),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Planned items (${detail.plannedItems.length})',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (detail.plannedItems.isEmpty)
                  Text(
                    'No items planned yet.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  _PlannedItemSections(plannedItems: detail.plannedItems),
                if (event.status == EventStatus.closed) ...[
                  const SizedBox(height: 24),
                  _RevisionsSummary(
                    eventId: eventId,
                    exposureLabel: exposureLabel,
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, Event event, String exposureLabel) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EventStatusChip(status: event.status),
              const Spacer(),
              Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(event.scheduledDate, style: theme.textTheme.bodyMedium),
            ],
          ),
          if (event.venue != null && event.venue!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Venue: ${event.venue}', style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Text(
            event.plannedExposure == null
                ? 'No expected $exposureLabel set yet'
                : '${event.plannedExposure} $exposureLabel planned',
            style: theme.textTheme.bodyMedium,
          ),
          if (event.notes != null && event.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(event.notes!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    ),
  );

  Widget _closeoutTile(
    BuildContext context,
    ThemeData theme,
    Event event,
    bool datePassed,
  ) {
    switch (event.status) {
      case EventStatus.planned:
        return Card(
          child: ListTile(
            minVerticalPadding: 12,
            enabled: false,
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Close out'),
            subtitle: const Text('Activate the event first'),
          ),
        );
      case EventStatus.active:
        // Primary-styled once the event date passes (§9).
        return Card(
          color: datePassed ? theme.colorScheme.primaryContainer : null,
          child: ListTile(
            minVerticalPadding: 12,
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Close out'),
            subtitle: const Text('Confirm what actually happened'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/events/$eventId/closeout'),
          ),
        );
      case EventStatus.closed:
        return Card(
          child: ListTile(
            minVerticalPadding: 12,
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(
              event.closedAt == null
                  ? 'Closed'
                  : 'Closed on ${instantYmd(event.closedAt!)}',
            ),
            subtitle: const Text('Corrections append a new revision'),
            trailing: TextButton(
              onPressed: () => context.push('/events/$eventId/closeout'),
              child: const Text('Revise closeout'),
            ),
          ),
        );
      case EventStatus.cancelled:
        return const SizedBox.shrink();
    }
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final inFlight = ref.read(_activatingProvider(eventId).notifier);
    if (inFlight.state) return;
    inFlight.state = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(eventServiceProvider).activate(eventId);
      result.fold((_) {}, (_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Couldn't activate this event. Try again."),
          ),
        );
      });
    } finally {
      inFlight.state = false;
    }
  }

  Future<void> _cancelFlow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelEventDialog(),
    );
    if (reason == null) return;
    final result = await ref
        .read(eventServiceProvider)
        .cancel(eventId, reason: reason);
    result.fold(
      (_) => messenger.showSnackBar(
        const SnackBar(content: Text('Event cancelled.')),
      ),
      (_) => messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't cancel this event. Try again.")),
      ),
    );
  }
}

/// The planned list in the same folder sections every list reads in
/// (proposal §3): headers carry the folder's 40 dp identity chip
/// (design-spec §3: large chips on event-detail folder groupings) and the
/// per-section count ("Disposables · 12"), folder order, Unfiled last.
/// Items whose folder is unknown (or archived) fall into Unfiled; while no
/// folders exist at all the list renders flat, exactly as it did before
/// folders.
class _PlannedItemSections extends ConsumerWidget {
  const _PlannedItemSections({required this.plannedItems});

  final List<EventPlannedItem> plannedItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folders =
        ref.watch(eventFoldersProvider).valueOrNull ?? const <Folder>[];
    final catalog =
        ref
            .watch(itemListProvider(const ItemFilter(includeArchived: true)))
            .valueOrNull ??
        const <ItemSummary>[];
    final folderIdByItem = {
      for (final summary in catalog)
        summary.item.id.value: summary.item.folderId?.value,
    };
    final sections = sectionEntriesByFolder(
      entries: plannedItems,
      folders: folders,
      folderIdOf: (item) => folderIdByItem[item.itemId],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections) ...[
          if (folders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Row(
                children: [
                  if (section.folder case final folder?) ...[
                    FolderChip.forFolder(folder),
                    const SizedBox(width: Space.m),
                  ],
                  Expanded(
                    child: Text(
                      folderSectionLabel(
                        section.folder,
                        section.entries.length,
                      ),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in section.entries) Chip(label: Text(item.name)),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Confirm dialog with the mandatory cancellation reason. Cancel is valid
/// only pre-activation (§12.15) — the entry point is hidden otherwise.
class _CancelEventDialog extends StatefulWidget {
  const _CancelEventDialog();

  @override
  State<_CancelEventDialog> createState() => _CancelEventDialogState();
}

class _CancelEventDialogState extends State<_CancelEventDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cancel this event?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'A cancelled event keeps its records but can no longer be '
          'activated or closed out.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reason,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Keep event'),
      ),
      TextButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_reason.text.trim()),
        child: const Text('Cancel event'),
      ),
    ],
  );
}

/// Closeout revisions summary for closed events (design §9: after closing
/// the detail screen surfaces the outcome + a revise entry).
class _RevisionsSummary extends ConsumerWidget {
  const _RevisionsSummary({required this.eventId, required this.exposureLabel});

  final String eventId;
  final String exposureLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final revisions = ref.watch(closeoutRevisionsProvider(eventId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Closeout revisions', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        revisions.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('Revisions could not be loaded.'),
          data: (headers) => Column(
            children: [
              for (final header in headers)
                Card(
                  child: ListTile(
                    minVerticalPadding: 12,
                    leading: const Icon(Icons.history_outlined),
                    title: Text('Revision ${header.revision}'),
                    subtitle: Text(
                      '${header.confirmedExposure} $exposureLabel confirmed · '
                      '${header.lines.length} '
                      'item${header.lines.length == 1 ? '' : 's'} · '
                      '${instantYmd(header.confirmedAt)}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
