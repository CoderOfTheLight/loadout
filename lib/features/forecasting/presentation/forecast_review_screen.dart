/// `/events/:eventId/forecast` — the release-contract surface (design §9,
/// §6.6). Renders the LATEST PERSISTED snapshot ([latestSnapshotProvider])
/// — never a live recompute. A staleness banner appears when the inputs
/// changed since the snapshot; Refresh APPENDS a new snapshot (the old one
/// remains). Snapshot generation exists only for planned/active events; for
/// CLOSED events the screen becomes the accuracy review
/// ([accuracyReviewProvider]: planned vs confirmed actuals, derived by
/// join, never stored).
///
/// The line cards read in the same folder sections as every other
/// event-scoped list (proposal §3), each section led by the folder's
/// [FolderChip] — the same chip as Items, the picker, and closeout, which
/// is what makes the app feel organized (design-spec §3). Warnings paint
/// with the semantic [StatusColors] amber — `pending` (spec §5) — so every
/// warning, including the per-event supplies-jump note, carries the same
/// visual weight.
///
/// Each line card gives ONE answer rather than four equal figures: see
/// [_ForecastLineCard] for the hierarchy and why.
///
/// v7 cost estimate: lines whose item carries a price get a cost caption
/// (effective load × unit price, exact cents via `timesQuantityMicros`),
/// and the list closes with an "Estimated cost" summary card. Prices are
/// the items' CURRENT ones on purpose — this is a live estimate of an
/// upcoming event, not a record; the after-the-fact number on a closed
/// event reads the closeout's price snapshots instead. Honesty: unpriced
/// items are counted out loud, never treated as free, and with no priced
/// item at all no cost UI renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../../core/money.dart';
import '../../../core/money_codec.dart';
import '../../catalog/domain/folder.dart';
import '../../catalog/domain/item.dart';
import '../../events/application/event_service.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/folder_sections.dart';
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
            '${widget.detail.plannedItems.length} planned '
            '${widget.detail.plannedItems.length == 1 ? 'item' : 'items'} '
            'from the confirmed history of past events — generate one to '
            'review it here.',
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
    // A snapshot from an older method is out of date for a different reason
    // than changed inputs, and saying "inputs changed" when they did not
    // would be a lie. The stored version says which. `isStale` also reports
    // true here (the method version tags the inputs hash), so this case is
    // checked first.
    final olderMethod =
        canRegenerate && snapshot.methodVersion != forecastMethodVersion;
    final items =
        ref.watch(forecastItemIndexProvider).valueOrNull ??
        const <String, Item>{};
    // The same folder sections every event-scoped list reads in; a
    // workspace with no folders at all renders flat, as it always did.
    final folders =
        ref.watch(eventFoldersProvider).valueOrNull ?? const <Folder>[];
    // v7: Σ (effective load × CURRENT unit price) over the lines that have
    // both. Exact cents; a priced line with no load number contributes
    // nothing (its card already shows the missing figure as an em-dash).
    var estimatedTotal = Money.zero;
    var costedLines = 0;
    var unpricedCount = 0;
    for (final line in snapshot.lines) {
      final price = items[line.itemId as String]?.unitPrice;
      if (price == null) {
        unpricedCount++;
        continue;
      }
      if (line.effectiveLoadMicros case final load?) {
        estimatedTotal = estimatedTotal.plus(price.timesQuantityMicros(load));
        costedLines++;
      }
    }
    return ContentColumn(
      child: ListView(
        children: [
          if (olderMethod)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: WarningBanner(
                message:
                    'This forecast was worked out before Loadout learned to '
                    'allow for days you ran out — Refresh to redo it.',
                actionLabel: 'Refresh',
                onAction: _refresh,
              ),
            )
          else if (stale)
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
          for (final section in sectionEntriesByFolder(
            entries: snapshot.lines,
            folders: folders,
            folderIdOf: (line) => items[line.itemId as String]?.folderId?.value,
          )) ...[
            if (folders.isNotEmpty)
              _FolderSectionHeader(
                folder: section.folder,
                count: section.entries.length,
              ),
            for (final line in section.entries)
              _ForecastLineCard(
                line: line,
                item: items[line.itemId as String],
                onOpen: () => context.push(
                  '/events/${widget.eventId}/forecast/'
                  '${line.itemId as String}',
                ),
              ),
          ],
          // No priced line → no cost UI at all: an "Estimated cost: $0"
          // over unpriced items would be an invented number.
          if (costedLines > 0)
            _EstimatedCostCard(
              total: estimatedTotal,
              unpricedCount: unpricedCount,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The closing cost summary (v7): the total the priced lines' loads come
/// to at the items' CURRENT prices — a LIVE estimate that follows a
/// catalog price edit, unlike the closed-event "Spent" figure, which reads
/// the closeout's snapshots. Unpriced items are said out loud, never
/// silently counted as free.
///
/// The money is the card's own hero ([Numerals.hero]): "what will this cost
/// me?" is the screen's second real answer, and a `titleMedium` sentence
/// buried it under every line card's figure.
class _EstimatedCostCard extends StatelessWidget {
  const _EstimatedCostCard({required this.total, required this.unpricedCount});

  final Money total;

  /// Shown lines whose item has no price — the honesty caption's count.
  final int unpricedCount;

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
              'ESTIMATED COST',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              MoneyCodec.format(total),
              style: Numerals.hero(theme.textTheme),
            ),
            const SizedBox(height: 4),
            Text(
              'At your current item prices.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (unpricedCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                unpricedCount == 1
                    ? '1 item has no price yet — not counted.'
                    : '$unpricedCount items have no price yet — not counted.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One folder section label: the folder's small chip, its name, and the
/// line count right-aligned in tabular figures — Airtable's header anatomy
/// pared down to what this read-only list needs. No fill, no color beyond
/// the chip itself (spec §3: color never as a header background).
class _FolderSectionHeader extends StatelessWidget {
  const _FolderSectionHeader({required this.folder, required this.count});

  /// Null for the Unfiled section, which gets a name and no chip.
  final Folder? folder;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Space.l, 4, Space.xs),
      child: Row(
        children: [
          if (folder case final folder?) ...[
            FolderChip.forFolder(folder, size: FolderChipSize.small),
            const SizedBox(width: Space.s),
          ],
          Expanded(
            child: Text(
              folder?.name ?? 'Unfiled',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: Numerals.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header (§9): the provenance line + policy chip + exposure — every value
/// from the persisted snapshot row, never hardcoded.
///
/// The provenance line is [snapshotProvenanceLabel] ("From your last 2
/// events · updated just now"), NOT the stored method identifier: the owner
/// is a volunteer kitchen coordinator, and `direct_median v3` is an internal
/// algorithm name. The identifier stays on the snapshot and stays visible in
/// the per-line Assumptions detail and on the About screen, where someone
/// asking that question is actually standing.
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
              snapshotProvenanceLabel(snapshot),
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

/// One per-item row (§9 `ForecastLineCard`) — ONE answer, not four numbers.
///
/// The card used to print Expected / Planned / Load / Acquire at identical
/// weight: four figures and no answer, so the owner had to work out which
/// one she was meant to act on. Square's and Tide Guide's rule applies here
/// exactly — lead with the single actionable figure, demote the rest to
/// captions, and let the detail live one tap deeper (the line-detail screen,
/// which this card already opens).
///
/// So the card carries exactly two figures, and both are actions:
///
///  * **Hero** — "Bring N", the EFFECTIVE load ([ForecastLineView
///    .effectiveLoadMicros], the override-winning figure the cost caption
///    already multiplies). That is what the owner physically does.
///  * **Secondary emphasis** — "Buy N more", and only when an acquisition is
///    actually needed: it is the other action, and it is silent when there
///    is nothing to buy rather than printing a 0.
///
/// Expected and Planned are gone. They are engine intermediates — the median
/// before the reserve, and the reserve before the pack rounding — and the
/// owner cannot act on either; they were the last of the four-up grid still
/// standing. The line-detail screen states what the number rests on in a
/// sentence instead.
///
/// No forecast math, no stored value and no engine behaviour changes here:
/// every figure is the same field the four-up layout read.
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
    final load = line.effectiveLoadMicros;
    // Only a real acquisition earns the second emphasis: null (nothing was
    // computed) and 0 (you already have enough) are both "nothing to buy".
    final acquire = line.suggestedAcquireMicros;
    final acquiring = acquire != null && acquire > 0;
    final coldStart = isColdStartLine(line);
    final warnings = coldStart
        ? [
            for (final warning in line.warnings)
              if (!isColdStartWarning(warning)) warning,
          ]
        : line.warnings;
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
              const SizedBox(height: Space.m),
              // THE answer. A Wrap, not a Row: at 200 % text scale the
              // 34 pt figure moves to its own line instead of overflowing.
              if (load != null)
                // Merged so a screen reader says "Bring 60" in one breath
                // rather than reading a label and a figure as two rows.
                MergeSemantics(
                  child: Wrap(
                    spacing: Space.s,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Bring', style: theme.textTheme.titleMedium),
                      Text(
                        formatQuantity(load, unit),
                        style: Numerals.hero(theme.textTheme),
                      ),
                      // The engine's own number, struck, when an override
                      // is in force (§9) — caption tier, beside the hero.
                      // A strike-through is invisible to a screen reader,
                      // so the word it means is spoken instead.
                      if (overridden)
                        Semantics(
                          excludeSemantics: true,
                          label:
                              'was '
                              '${formatQuantity(line.suggestedLoadMicros, unit)}',
                          child: Text(
                            formatQuantity(line.suggestedLoadMicros, unit),
                            style: Numerals.caption(theme.textTheme)?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                // No number at all — say so in words rather than lead with
                // an em-dash where the answer belongs. The 'Set a baseline'
                // prompt below is the way out.
                Text(
                  'No number yet.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (acquiring) ...[
                const SizedBox(height: Space.xs),
                Text(
                  'Buy ${formatQuantity(acquire, unit)} more',
                  style: Numerals.glance(theme.textTheme),
                ),
              ],
              // v7: what this load would cost at the item's CURRENT price
              // (a live estimate — see the library doc). Only when both a
              // price and a load exist; nothing is ever invented.
              if ((item?.unitPrice, load) case (
                final price?,
                final amount?,
              )) ...[
                const SizedBox(height: Space.s),
                Text(
                  'Cost: '
                  '${MoneyCodec.format(price.timesQuantityMicros(amount))}'
                  ' · ${MoneyCodec.format(price)} each',
                  style: Numerals.caption(
                    theme.textTheme,
                  )?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (overridden) ...[
                const SizedBox(height: 8),
                _IndicatorChip(
                  icon: Icons.edit_outlined,
                  label: 'Overridden: ${line.override!.reason}',
                  background: theme.colorScheme.secondaryContainer,
                  foreground: theme.colorScheme.onSecondaryContainer,
                ),
              ],
              // A cold-start line used to stack TWO amber banners saying the
              // same thing in the engine's words ("No comparable confirmed
              // outcomes…" and "Estimate only: worked out from '1 serves
              // 4'…"). One short line in the owner's words says it once.
              if (coldStart) ...[
                const SizedBox(height: 8),
                _IndicatorChip(
                  icon: Icons.lightbulb_outline,
                  label: coldStartNoteFor(line),
                  background: StatusColors.of(context).pending.container,
                  foreground: StatusColors.of(context).pending.foreground,
                ),
              ],
              // Every other stored warning — the engine's own and the
              // application-layer notes like the supplies jump — renders
              // with the same semantic amber weight (spec §5).
              for (final warning in warnings) ...[
                const SizedBox(height: 8),
                _IndicatorChip(
                  icon: Icons.warning_amber_outlined,
                  label: warning,
                  background: StatusColors.of(context).pending.container,
                  foreground: StatusColors.of(context).pending.foreground,
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

/// A labelled figure on the closed-event accuracy review, where three
/// numbers side by side ARE the content (forecast vs load vs actual is a
/// comparison, not an instruction). The planned/active line card leads with
/// one hero instead — see [_ForecastLineCard].
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

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
          Text(value, style: Numerals.rowQuantity(theme.textTheme)),
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
    final folders =
        ref.watch(eventFoldersProvider).valueOrNull ?? const <Folder>[];
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
                            snapshotProvenanceLabel(snapshot),
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
                for (final section in sectionEntriesByFolder(
                  entries: review.lines,
                  folders: folders,
                  folderIdOf: (line) =>
                      items[line.itemId as String]?.folderId?.value,
                )) ...[
                  if (folders.isNotEmpty)
                    _FolderSectionHeader(
                      folder: section.folder,
                      count: section.entries.length,
                    ),
                  for (final line in section.entries)
                    _AccuracyLineCard(
                      line: line,
                      item: items[line.itemId as String],
                      onOpen: () => context.push(
                        '/events/$eventId/forecast/${line.itemId as String}',
                      ),
                    ),
                ],
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
                  line.basis == ForecastBasis.perEventBaseline ||
                  line.override?.overrideLoadMicros != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Never let a cold-start guess ("1 serves N", "N per
                    // person", or "you usually bring N") be read as a miss
                    // against confirmed history: say what it was measured
                    // against before the variance is believed.
                    if (line.basis == ForecastBasis.servesBaseline ||
                        line.basis == ForecastBasis.perEventBaseline)
                      _IndicatorChip(
                        icon: Icons.lightbulb_outline,
                        label: 'Compared against an estimate, not history',
                        background: StatusColors.of(context).pending.container,
                        foreground: StatusColors.of(context).pending.foreground,
                      ),
                    if (line.stockout)
                      _IndicatorChip(
                        icon: Icons.warning_amber_outlined,
                        label: 'Ran out',
                        background: StatusColors.of(context).pending.container,
                        foreground: StatusColors.of(context).pending.foreground,
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
