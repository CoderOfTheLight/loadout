/// `/events/:eventId/forecast` — the release-contract surface (design §9,
/// §6.6). Renders the LATEST PERSISTED snapshot ([latestSnapshotProvider])
/// — never a live recompute. A staleness banner appears when the inputs
/// changed since the snapshot; Refresh APPENDS a new snapshot (the old one
/// remains). Snapshot generation exists only for planned/active events; for
/// CLOSED events the screen becomes the accuracy review
/// ([accuracyReviewProvider]: planned vs confirmed actuals, derived by
/// join, never stored).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../catalog/domain/item.dart';
import '../../events/application/event_service.dart';
import '../../events/domain/event.dart';
import '../domain/snapshot.dart';
import 'forecast_presentation_support.dart';

class ForecastReviewScreen extends ConsumerWidget {
  const ForecastReviewScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(eventDetailProvider(eventId));
    return detail.when(
      loading: () => const _MessageScaffold(
        title: 'Forecast',
        child: Center(child: CircularProgressIndicator()),
      ),
      // Content-free by design (§10): no exception text reaches the UI.
      error: (_, _) => const _MessageScaffold(
        title: 'Forecast',
        child: EmptyState(
          icon: Icons.error_outline,
          message: 'This event could not be loaded.',
        ),
      ),
      data: (detail) => detail.event.status == EventStatus.closed
          ? _AccuracyReviewBody(eventId: eventId)
          : _ForecastReviewBody(eventId: eventId, detail: detail),
    );
  }
}

class _MessageScaffold extends StatelessWidget {
  const _MessageScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

// ----------------------------------------------------- planned / active

class _ForecastReviewBody extends ConsumerWidget {
  const _ForecastReviewBody({required this.eventId, required this.detail});

  final String eventId;
  final EventDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(latestSnapshotProvider(eventId));
    return Scaffold(
      appBar: AppBar(title: const Text('Forecast')),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: Icons.error_outline,
          message: 'The forecast could not be loaded.',
        ),
        data: (snapshot) => snapshot == null
            ? _NoSnapshotBody(eventId: eventId, detail: detail)
            : _SnapshotBody(
                eventId: eventId,
                detail: detail,
                snapshot: snapshot,
              ),
      ),
    );
  }
}

/// Empty state (§9): explainer + Generate for planned/active events; no
/// generation for cancelled events (forbidden by the validator too).
class _NoSnapshotBody extends ConsumerStatefulWidget {
  const _NoSnapshotBody({required this.eventId, required this.detail});

  final String eventId;
  final EventDetail detail;

  @override
  ConsumerState<_NoSnapshotBody> createState() => _NoSnapshotBodyState();
}

class _NoSnapshotBodyState extends ConsumerState<_NoSnapshotBody> {
  bool _generating = false;

  Future<void> _generate() async {
    setState(() => _generating = true);
    final result = await ref
        .read(forecastServiceProvider)
        .generateSnapshot(widget.eventId);
    if (!mounted) return;
    setState(() => _generating = false);
    ref.invalidate(forecastStalenessProvider(widget.eventId));
    result.fold((_) {}, (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.detail.event;
    if (event.status == EventStatus.cancelled) {
      return const EmptyState(
        icon: Icons.event_busy_outlined,
        message: 'This event was cancelled before a forecast was generated.',
      );
    }
    if (widget.detail.plannedItems.isEmpty) {
      return const EmptyState(
        icon: Icons.playlist_add_outlined,
        message: 'Add items to this event to see a load list.',
      );
    }
    final theme = Theme.of(context);
    final exposureMissing = event.plannedExposure == null;
    return ContentColumn(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.insights_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No forecast yet. Loadout builds a load list for the '
            '${widget.detail.plannedItems.length} planned item(s) from the '
            'confirmed history of past events — generate one to review it '
            'here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: exposureMissing || _generating ? null : _generate,
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            child: _generating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Generate forecast'),
          ),
          if (exposureMissing) ...[
            const SizedBox(height: 12),
            Text(
              'Set a planned exposure on the event before generating.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SnapshotBody extends ConsumerStatefulWidget {
  const _SnapshotBody({
    required this.eventId,
    required this.detail,
    required this.snapshot,
  });

  final String eventId;
  final EventDetail detail;
  final ForecastSnapshotView snapshot;

  @override
  ConsumerState<_SnapshotBody> createState() => _SnapshotBodyState();
}

class _SnapshotBodyState extends ConsumerState<_SnapshotBody> {
  bool _refreshing = false;

  /// Refresh APPENDS a new snapshot; the old one remains (§6.6).
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final result = await ref
        .read(forecastServiceProvider)
        .generateSnapshot(widget.eventId);
    if (!mounted) return;
    setState(() => _refreshing = false);
    // The frozen staleness provider re-fires on ledger/event changes but a
    // fresh snapshot append is invisible to it (see [latestSnapshotProvider]);
    // recompute explicitly so the banner clears.
    ref.invalidate(forecastStalenessProvider(widget.eventId));
    result.fold((_) {}, (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final status = widget.detail.event.status;
    final canRegenerate =
        status == EventStatus.planned || status == EventStatus.active;
    final stale =
        canRegenerate &&
        (ref.watch(forecastStalenessProvider(widget.eventId)).valueOrNull ??
            false);
    final items =
        ref.watch(forecastItemIndexProvider).valueOrNull ??
        const <String, Item>{};
    return ContentColumn(
      child: ListView(
        children: [
          if (stale)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: WarningBanner(
                message:
                    'Inputs changed since this forecast — Refresh to '
                    'update.',
                actionLabel: 'Refresh',
                onAction: _refresh,
              ),
            ),
          _SnapshotHeader(snapshot: snapshot),
          const SizedBox(height: 4),
          for (final line in snapshot.lines)
            _ForecastLineCard(
              line: line,
              item: items[line.itemId as String],
              onOpen: () => context.push(
                '/events/${widget.eventId}/forecast/${line.itemId as String}',
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Header (§9): `Method: direct_median v1 · computed [relative time]` +
/// policy chip + exposure — every value from the persisted snapshot row,
/// never hardcoded.
class _SnapshotHeader extends StatelessWidget {
  const _SnapshotHeader({required this.snapshot});

  final ForecastSnapshotView snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Method: ${snapshot.method} v${snapshot.methodVersion} · '
              'computed ${relativeTimeLabel(snapshot.createdAt)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: const Icon(Icons.tune_outlined, size: 18),
                  label: Text(policyChipLabel(snapshot.policy)),
                ),
                Text(
                  'for ${snapshot.upcomingExposure} '
                  '${exposureLabelOf(snapshot)}',
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One per-item row (§9 `ForecastLineCard`): evidence badge, the four
/// figures, warning indicators, and the effective override.
class _ForecastLineCard extends StatelessWidget {
  const _ForecastLineCard({
    required this.line,
    required this.item,
    required this.onOpen,
  });

  final ForecastLineView line;
  final Item? item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = item?.unit;
    final overridden = line.isOverridden;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item?.name ?? (line.itemId as String),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.history_outlined, size: 18),
                    label: Text(evidenceBadgeLabel(line)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Four figures; wraps 2×2 at large type (§9 a11y).
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  // `suggested*` / `plannedExpectedUse*`, not the raw engine
                  // fields: those are null on a "1 serves N" line and would
                  // print four em-dashes beside a usable estimate.
                  _Figure(
                    label: 'Expected',
                    value: formatQuantity(line.plannedExpectedUseMicros, unit),
                  ),
                  _Figure(
                    label: 'Planned',
                    value: formatQuantity(line.suggestedPlannedMicros, unit),
                  ),
                  _Figure(
                    label: 'Load',
                    value: formatQuantity(line.effectiveLoadMicros, unit),
                    struckValue: overridden
                        ? formatQuantity(line.suggestedLoadMicros, unit)
                        : null,
                  ),
                  _Figure(
                    label: 'Acquire',
                    value: formatQuantity(line.suggestedAcquireMicros, unit),
                  ),
                ],
              ),
              if (overridden) ...[
                const SizedBox(height: 8),
                _IndicatorChip(
                  icon: Icons.edit_outlined,
                  label: 'Overridden: ${line.override!.reason}',
                  background: theme.colorScheme.secondaryContainer,
                  foreground: theme.colorScheme.onSecondaryContainer,
                ),
              ],
              for (final warning in line.warnings) ...[
                const SizedBox(height: 8),
                _IndicatorChip(
                  icon: Icons.warning_amber_outlined,
                  label: warning,
                  background: theme.colorScheme.tertiaryContainer,
                  foreground: theme.colorScheme.onTertiaryContainer,
                ),
              ],
              // Only a line with NO number at all needs this prompt; a
              // "1 serves N" estimate already has one and is still editable
              // by tapping the card.
              if (line.basis == ForecastBasis.insufficientData)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onOpen,
                    child: const Text('Set a baseline'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.struckValue});

  final String label;
  final String value;

  /// The engine value shown struck-through beside an override (§9).
  final String? struckValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(value, style: theme.textTheme.titleMedium),
              if (struckValue != null)
                Text(
                  struckValue!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Icon + text indicator — meaning never color-only (§9 a11y).
class _IndicatorChip extends StatelessWidget {
  const _IndicatorChip({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: foreground),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ),
      ],
    ),
  );
}

// -------------------------------------------------------- closed events

/// Accuracy review (§6.6): the latest snapshot's lines joined to the latest
/// closeout revision's lines — variance, stockout/approximate flags — via
/// [accuracyReviewProvider]. Read-only.
class _AccuracyReviewBody extends ConsumerWidget {
  const _AccuracyReviewBody({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(accuracyReviewProvider(eventId));
    final snapshot = ref.watch(latestSnapshotProvider(eventId)).valueOrNull;
    final items =
        ref.watch(forecastItemIndexProvider).valueOrNull ??
        const <String, Item>{};
    return Scaffold(
      appBar: AppBar(title: const Text('Accuracy review')),
      body: reviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: Icons.error_outline,
          message: 'The accuracy review could not be loaded.',
        ),
        data: (review) {
          if (review.snapshotId == null) {
            return const EmptyState(
              icon: Icons.insights_outlined,
              message:
                  'No forecast was generated for this event, so there '
                  'is nothing to compare with the confirmed closeout.',
            );
          }
          return ContentColumn(
            child: ListView(
              children: [
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (snapshot != null)
                          Text(
                            'Method: ${snapshot.method} '
                            'v${snapshot.methodVersion} · computed '
                            '${relativeTimeLabel(snapshot.createdAt)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          _exposureCaption(review, snapshot),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                for (final line in review.lines)
                  _AccuracyLineCard(
                    line: line,
                    item: items[line.itemId as String],
                    onOpen: () => context.push(
                      '/events/$eventId/forecast/${line.itemId as String}',
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  String _exposureCaption(
    AccuracyReview review,
    ForecastSnapshotView? snapshot,
  ) {
    final label = snapshot == null ? 'attendance' : exposureLabelOf(snapshot);
    final planned = review.upcomingExposure;
    final confirmed = review.confirmedExposure;
    return 'Planned for ${planned ?? '—'} $label · '
        'confirmed ${confirmed ?? '—'}';
  }
}

class _AccuracyLineCard extends StatelessWidget {
  const _AccuracyLineCard({
    required this.line,
    required this.item,
    required this.onOpen,
  });

  final AccuracyLine line;
  final Item? item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = item?.unit;
    final effectiveLoad = line.override?.overrideLoadMicros ?? line.loadMicros;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item?.name ?? (line.itemId as String),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Figure(
                    label: 'Forecast',
                    value: formatQuantity(line.expectedUseMicros, unit),
                  ),
                  _Figure(
                    label: 'Load',
                    value: formatQuantity(effectiveLoad, unit),
                  ),
                  _Figure(
                    label: 'Actual',
                    value: formatQuantity(line.actualDepletionMicros, unit),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                accuracyCaption(
                  expectedUseMicros: line.expectedUseMicros,
                  actualDepletionMicros: line.actualDepletionMicros,
                  varianceMicros: line.varianceMicros,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (line.stockout ||
                  line.approximate ||
                  line.basis == ForecastBasis.servesBaseline ||
                  line.override?.overrideLoadMicros != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Never let a "1 serves N" guess be read as a miss
                    // against confirmed history: say what it was measured
                    // against before the variance is believed.
                    if (line.basis == ForecastBasis.servesBaseline)
                      _IndicatorChip(
                        icon: Icons.lightbulb_outline,
                        label: 'Compared against an estimate, not history',
                        background: theme.colorScheme.tertiaryContainer,
                        foreground: theme.colorScheme.onTertiaryContainer,
                      ),
                    if (line.stockout)
                      _IndicatorChip(
                        icon: Icons.warning_amber_outlined,
                        label: 'Ran out',
                        background: theme.colorScheme.tertiaryContainer,
                        foreground: theme.colorScheme.onTertiaryContainer,
                      ),
                    if (line.approximate)
                      _IndicatorChip(
                        icon: Icons.help_outline,
                        label: 'Estimate',
                        background: theme.colorScheme.surfaceContainerHighest,
                        foreground: theme.colorScheme.onSurfaceVariant,
                      ),
                    if (line.override?.overrideLoadMicros != null)
                      _IndicatorChip(
                        icon: Icons.edit_outlined,
                        label: 'Overridden: ${line.override!.reason}',
                        background: theme.colorScheme.secondaryContainer,
                        foreground: theme.colorScheme.onSecondaryContainer,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
