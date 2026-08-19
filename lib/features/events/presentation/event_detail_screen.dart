/// `/events/:eventId` (design §9 EventDetailScreen): the lifecycle hub.
/// Header (name, date, status chip, planned exposure); tiles for the Packing
/// list (who it is for, from the latest snapshot row — never hardcoded),
/// Close out (primary-styled once the date passes; closed events show
/// `Closed on <date>` + Revise), and Accuracy review (closed only). Then the
/// money, and it is TWO sections that never overlap: "Estimated cost" while
/// the event is still planned or active (what she is about to spend, with
/// what events like it usually cost as one sentence under it), and "Spent"
/// once it is closed (what it actually used, at the prices snapshotted at
/// closeout). Planned items, and for closed events the closeout revisions
/// summary. App-bar: Edit; Start this event (planned → active); Cancel
/// (planned ONLY — an activated event must be closed out, §12.15).
///
/// There is no Production tile. It was a disabled "Coming soon" row that
/// never navigated anywhere — a dead end a volunteer taps twice and gets
/// nothing from — and the `/production` stub behind it went with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../core/money.dart';
import '../../../core/money_codec.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/folder.dart';
import '../../closeout/application/closeout_service.dart';
import '../../closeout/presentation/closeout_report_screen.dart';
import '../../forecasting/domain/event_cost.dart';
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

/// The latest revision's cost lines for the "Spent" section (v7): confirmed
/// depletions with the unit prices SNAPSHOTTED at confirm time — a later
/// catalog price edit never moves a closed event's number. Watches the
/// revisions stream so a revise recomputes; empty when never closed out.
final _closeoutCostLinesProvider = FutureProvider.autoDispose
    .family<List<CloseoutCostLine>, String>((ref, eventId) async {
      ref.watch(closeoutRevisionsProvider(eventId));
      return ref
          .watch(closeoutServiceProvider)
          .latestCloseoutCostLines(eventId);
    });

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
                    label: const Text('Start this event'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (event.status != EventStatus.cancelled) ...[
                  Card(
                    child: ListTile(
                      minVerticalPadding: 12,
                      leading: const Icon(Icons.insights_outlined),
                      title: const Text('Packing list'),
                      // Never `direct_median v3`: the method identifier is an
                      // internal algorithm name, and it was the loudest thing
                      // on the tile. What she needs to know before tapping is
                      // whether the list exists and who it is for.
                      subtitle: Text(
                        snapshot == null
                            ? 'Not made yet'
                            : 'For ${snapshot.upcomingExposure} '
                                  '$exposureLabel',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/events/$eventId/forecast'),
                    ),
                  ),
                  _closeoutTile(context, theme, event, datePassed),
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
                // Spaces itself: renders nothing at all when neither the
                // planned cost nor the history has an answer.
                if (event.status == EventStatus.planned ||
                    event.status == EventStatus.active)
                  _EstimatedCostSection(eventId: eventId),
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
                  // Spaces itself: it renders nothing when no closeout line
                  // carried a price snapshot.
                  _SpentSummary(eventId: eventId),
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
          // A Wrap, not a Row with a Spacer: at 200 % text scale on a 320 dp
          // phone the chip and the date together are wider than the card,
          // and a Spacer has no way to give. Wrapped, the date simply drops
          // to its own line; at every normal size it still sits hard right.
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              EventStatusChip(status: event.status),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      event.scheduledDate,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
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

/// "What is this going to cost?", asked while the event can still be
/// changed — planned and active only, because once it is closed the
/// question is answered by [_SpentSummary] and an estimate beside a fact
/// would only invite arithmetic nobody asked for.
///
/// ONE figure, and it is the planned one.
///
/// The card used to stack two: "$787.61" (the list at today's prices) over
/// "Events like this usually cost about $295.50" with three lines of
/// qualifier under it. The two are different kinds of number and can
/// legitimately differ by 2.7×, but nothing on the card said so, so it read
/// as a contradiction — and the qualifiers made the loudest thing on a
/// TOTAL a list of reasons not to believe it.
///
/// So the card's figure is the PLANNED cost: it is the one tied to the list
/// she is looking at, and it is arithmetic rather than prediction. Items
/// with no price (or no forecast quantity yet) contribute nothing and are
/// still said out loud, and with nothing priced at all there is no figure —
/// never a $0 standing in for "unknown".
///
/// The history goes below it as ONE plain sentence with no qualifiers on its
/// face. Every qualifier still exists, word for word, one tap away behind
/// "How is this worked out?" ([_CostExplainerDialog]) — the honesty rules are
/// unchanged, they have just stopped shouting at someone reading a total.
/// Absent entirely when nothing confirmed backs it: no empty state, no
/// placeholder, no zero.
///
/// Loading and error render as NOTHING on purpose. The cost is a supporting
/// answer on a screen whose job is the lifecycle, so a spinner or an error
/// string here would be louder than the thing it is standing in for.
class _EstimatedCostSection extends ConsumerWidget {
  const _EstimatedCostSection({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final planned = ref.watch(plannedCostProvider(eventId)).valueOrNull;
    final prediction = ref
        .watch(eventCostPredictionProvider(eventId))
        .valueOrNull;
    // `isEmpty` means nothing on the list is priced — the figure would be a
    // lie, so there is no figure.
    final showPlanned = planned != null && !planned.isEmpty;
    if (!showPlanned && prediction == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Estimated cost', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showPlanned) ...[
                  Text(
                    MoneyCodec.format(planned.total),
                    style: Numerals.hero(theme.textTheme),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "What you're bringing, at today's prices.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (planned.isPartial) ...[
                    const SizedBox(height: 4),
                    Text(
                      planned.unpricedItemCount == 1
                          ? '1 item has no price yet — not counted.'
                          : '${planned.unpricedItemCount} items have no price '
                                'yet — not counted.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
                if (prediction != null) ...[
                  if (showPlanned) const Divider(height: 24),
                  Text(
                    'Past events like this averaged about '
                    '${MoneyCodec.format(prediction.total)}.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: Numerals.tabular,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => _CostExplainerDialog(
                          prediction: prediction,
                          planned: showPlanned ? planned : null,
                        ),
                      ),
                      child: const Text('How is this worked out?'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Everything the history sentence does not say on its face, kept word for
/// word:
///
///  * the RATE it was scaled at, so "$315" is traceable to "$2.10 a person
///    × 150" rather than arriving from nowhere;
///  * HOW MANY events it read — and when that is one or two, wording that
///    says so in words instead of leaving a count to be interpreted. One
///    event is a data point; calling it a pattern would be the app lying
///    about its own confidence;
///  * whether those events had unpriced lines, in which case the rate — and
///    so this figure — is a FLOOR, not an estimate;
///  * and, when both figures are on the card, what makes them different
///    kinds of number — which the old layout never said at all.
class _CostExplainerDialog extends StatelessWidget {
  const _CostExplainerDialog({required this.prediction, this.planned});

  final EventCostPrediction prediction;

  /// Null when the card shows no planned figure to explain.
  final PlannedCost? planned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    return AlertDialog(
      title: const Text('How is this worked out?'),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (planned != null) ...[
            Text(
              'The big figure is your own packing list, priced at the prices '
              'on your items today. It is arithmetic, not a guess.',
              style: body,
            ),
            if (planned!.isPartial) ...[
              const SizedBox(height: 8),
              Text(
                planned!.unpricedItemCount == 1
                    ? '1 item has no price yet — not counted.'
                    : '${planned!.unpricedItemCount} items have no price yet '
                          '— not counted.',
                style: body,
              ),
            ],
            const Divider(height: 24),
          ],
          Text(
            'The past-events figure comes from events you have closed out. '
            'Loadout takes what each one actually cost, divides by the people '
            'it served, and takes the middle figure.',
            style: body,
          ),
          const SizedBox(height: 8),
          Text(
            '${MoneyCodec.format(prediction.perPerson)} a person × '
            '${prediction.exposure}',
            style: Numerals.caption(
              theme.textTheme,
            )?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(costHistoryEvidenceLine(prediction), style: body),
          if (prediction.understates) ...[
            const SizedBox(height: 8),
            Text(
              'Some of those events had items with no price, so this is a '
              'floor.',
              style: body,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'The two answer different questions, so they can differ. Neither '
            'is a correction of the other.',
            style: body,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// "from N past events", and at one or two the sentence goes on to admit
/// what N that small is worth.
@visibleForTesting
String costHistoryEvidenceLine(EventCostPrediction prediction) {
  final count = prediction.evidence.length;
  if (!prediction.isThin) return 'from $count past events';
  return count == 1
      ? 'from 1 past event — one event is a data point, not a pattern.'
      : 'from $count past events — two is thin evidence, not a pattern.';
}

/// "What it all was" for a closed event (v7): Σ (confirmed depletion ×
/// the unit price snapshotted at confirm) over the latest revision's
/// priced lines. The money is frozen history — editing an item's price
/// later never moves it; only a revise (which re-snapshots) can. Honesty:
/// lines whose price was unknown at confirm are counted out loud, never
/// treated as free, and with no priced line at all the section does not
/// render — a "$0" over unknown prices would pretend the event was free.
/// A never-closed event has no lines, so it shows nothing.
class _SpentSummary extends ConsumerWidget {
  const _SpentSummary({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lines =
        ref.watch(_closeoutCostLinesProvider(eventId)).valueOrNull ??
        const <CloseoutCostLine>[];
    var total = Money.zero;
    var pricedCount = 0;
    var unpricedCount = 0;
    for (final line in lines) {
      if (line.unitPriceCents case final cents?) {
        total = total.plus(
          Money.fromCents(cents).timesQuantityMicros(line.depletionMicros),
        );
        pricedCount++;
      } else {
        unpricedCount++;
      }
    }
    if (pricedCount == 0) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Spent', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MoneyCodec.format(total),
                  style: Numerals.glance(theme.textTheme),
                ),
                const SizedBox(height: 4),
                Text(
                  'What this event used, at the prices recorded when you '
                  'closed out.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (unpricedCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    unpricedCount == 1
                        ? '1 item had no price — not counted.'
                        : '$unpricedCount items had no price — not counted.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        context.push(closeoutReportLocation(eventId)),
                    child: const Text('See the full count'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
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
