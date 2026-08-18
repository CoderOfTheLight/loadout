/// `/events/:eventId/closeout/report` — what the count produced.
///
/// A closeout used to end in a snackbar. SafetyCulture's finding is that a
/// count only feels consequential when it hands back an ARTIFACT: something
/// the person who did the counting can read, keep, and show. So confirming
/// now lands here, on a page that answers the two questions the worksheet
/// could not:
///
///  * **What did this event cost?** Σ (confirmed depletion × the unit price
///    SNAPSHOTTED onto the line at confirm time). Frozen history: editing an
///    item's price afterwards never moves this figure — only a revise, which
///    re-snapshots, can. The estimate on the forecast screen is the live
///    number; this is the record.
///  * **How close was the plan?** Per item, what was counted against what
///    the forecast expected, and the variance between them.
///
/// Honesty rules, same as everywhere else in v7:
///
///  * no forecast for the event (or for one item) → it SAYS there is nothing
///    to compare against, rather than inventing an expectation;
///  * a line whose price was unknown at confirm is counted out loud and
///    contributes nothing, and with no priced line at all there is no total
///    at all — a "$0" over unknown prices would claim the event was free.
///
/// Data comes from two existing read surfaces, joined here on itemId; no
/// application-layer change was needed:
///
///  * `CloseoutService.latestCloseoutCostLines` — the latest revision's
///    lines with their price snapshots and item names, name-ordered;
///  * [accuracyReviewProvider] — the same latest snapshot ⋈ latest closeout
///    join the closed-event accuracy review already reads, which is where
///    the expected figure and the variance come from (`AccuracyLine
///    .expectedUseMicros` is the forecast's `plannedExpectedUse`, and
///    `varianceMicros` is `actual − expected`, both derived, never stored).
///
/// The report is a READ surface: it records nothing, changes nothing, and
/// leaves the worksheet's grammar — the leftover-first cards, the quick
/// chips, scan-to-count, the one celebration, the single confirm haptic and
/// skip semantics — exactly as they were.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../core/money.dart';
import '../../../core/money_codec.dart';
import '../../../core/quantity_codec.dart';
import '../../forecasting/domain/snapshot.dart';
import '../application/closeout_service.dart';

/// The route this screen is mounted at (see `lib/app/router.dart`); the
/// event screen can push it with the event's own id interpolated.
String closeoutReportLocation(String eventId) =>
    '/events/$eventId/closeout/report';

/// The latest revision's cost lines, re-read whenever a revision lands (a
/// revise re-snapshots every price, so the report must follow it).
final _reportLinesProvider = FutureProvider.autoDispose
    .family<List<CloseoutCostLine>, String>((ref, eventId) {
      ref.watch(closeoutRevisionsProvider(eventId));
      return ref
          .watch(closeoutServiceProvider)
          .latestCloseoutCostLines(eventId);
    });

class CloseoutReportScreen extends ConsumerWidget {
  const CloseoutReportScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesAsync = ref.watch(_reportLinesProvider(eventId));
    final reviewAsync = ref.watch(accuracyReviewProvider(eventId));
    return Scaffold(
      appBar: AppBar(title: const Text('Closeout report')),
      body: _body(linesAsync, reviewAsync),
    );
  }

  Widget _body(
    AsyncValue<List<CloseoutCostLine>> linesAsync,
    AsyncValue<AccuracyReview> reviewAsync,
  ) {
    // Content-free by design (§10): no exception text reaches the UI.
    if (linesAsync.hasError || reviewAsync.hasError) {
      return const EmptyState(
        icon: Icons.error_outline,
        message: 'This report could not be loaded.',
      );
    }
    final lines = linesAsync.valueOrNull;
    final review = reviewAsync.valueOrNull;
    if (lines == null || review == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (lines.isEmpty) {
      return const EmptyState(
        icon: Icons.fact_check_outlined,
        message:
            'Nothing has been counted for this event yet, so there is no '
            'report to show.',
      );
    }
    return _ReportBody(lines: lines, review: review);
  }
}

/// One item's line in the report, already joined and costed.
@immutable
class _ReportRow {
  const _ReportRow({
    required this.itemName,
    required this.usedMicros,
    this.expectedMicros,
    this.varianceMicros,
    this.unitPrice,
    this.cost,
  });

  final String itemName;

  /// Confirmed depletion — what the count says was used.
  final int usedMicros;

  /// The forecast's expected use, or null when no snapshot covered this
  /// item. Never substituted with anything.
  final int? expectedMicros;

  /// `used − expected`, or null when there is nothing to compare against.
  final int? varianceMicros;

  /// The price SNAPSHOTTED at confirm time, or null when it was unknown.
  final Money? unitPrice;

  /// [usedMicros] at [unitPrice]; null exactly when [unitPrice] is.
  final Money? cost;
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.lines, required this.review});

  final List<CloseoutCostLine> lines;
  final AccuracyReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracyByItem = {
      for (final line in review.lines) line.itemId as String: line,
    };
    final rows = <_ReportRow>[];
    var total = Money.zero;
    var pricedCount = 0;
    var unpricedCount = 0;
    var matched = 0;
    var over = 0;
    var short = 0;
    var noForecast = 0;
    for (final line in lines) {
      final accuracy = accuracyByItem[line.itemId];
      final expected = accuracy?.expectedUseMicros;
      // Recomputed here rather than read off the join so the arithmetic
      // always matches the two figures printed beside it.
      final variance = expected == null
          ? null
          : line.depletionMicros - expected;
      if (variance == null) {
        noForecast++;
      } else if (variance == 0) {
        matched++;
      } else if (variance > 0) {
        over++;
      } else {
        short++;
      }
      final price = line.unitPriceCents == null
          ? null
          : Money.fromCents(line.unitPriceCents!);
      final cost = price?.timesQuantityMicros(line.depletionMicros);
      if (cost == null) {
        unpricedCount++;
      } else {
        total = total.plus(cost);
        pricedCount++;
      }
      rows.add(
        _ReportRow(
          itemName: line.itemName,
          usedMicros: line.depletionMicros,
          expectedMicros: expected,
          varianceMicros: variance,
          unitPrice: price,
          cost: cost,
        ),
      );
    }
    return ContentColumn(
      child: ListView(
        children: [
          _TotalsCard(
            total: total,
            pricedCount: pricedCount,
            unpricedCount: unpricedCount,
            matched: matched,
            over: over,
            short: short,
            noForecast: noForecast,
            hadForecast: review.snapshotId != null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, Space.xl, 4, Space.s),
            child: Text(
              'WHAT YOU USED',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final row in rows) _ReportRowCard(row: row),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }
}

/// The two answers, at the top: what it cost, and how close the plan was.
///
/// The money is the hero ([Numerals.hero]) because it is the one FIGURE the
/// page exists to give. The variance headline sits one tier down
/// ([Numerals.glance]): it is a sentence, not a numeral, and a card carries
/// one hero — 34 pt prose would read as shouting, not as hierarchy.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.total,
    required this.pricedCount,
    required this.unpricedCount,
    required this.matched,
    required this.over,
    required this.short,
    required this.noForecast,
    required this.hadForecast,
  });

  final Money total;
  final int pricedCount;
  final int unpricedCount;
  final int matched;
  final int over;
  final int short;
  final int noForecast;

  /// True when a snapshot existed for this event at all — the difference
  /// between "nothing was forecast" and "this item was not in the forecast".
  final bool hadForecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOTAL SPENT',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.xs),
            // No priced line → no figure at all. An invented $0 would say
            // the event was free.
            if (pricedCount > 0) ...[
              Text(
                MoneyCodec.format(total),
                style: Numerals.hero(theme.textTheme),
              ),
              const SizedBox(height: Space.xs),
              Text('At the prices recorded when you closed out.', style: muted),
            ] else
              Text(
                'No prices were recorded, so there is no total to show.',
                style: theme.textTheme.bodyMedium,
              ),
            if (unpricedCount > 0) ...[
              const SizedBox(height: Space.xs),
              Text(
                unpricedCount == 1
                    ? '1 item had no price — not counted.'
                    : '$unpricedCount items had no price — not counted.',
                style: muted,
              ),
            ],
            const Divider(height: Space.xl),
            Text(
              'AGAINST THE FORECAST',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              varianceHeadline(
                matched: matched,
                over: over,
                short: short,
                hadForecast: hadForecast,
              ),
              style: Numerals.glance(theme.textTheme),
            ),
            // The legend only when one of those two words is actually on
            // screen: "short" reads as "we ran out" at a stall, so it is
            // defined rather than assumed — but never explained in the
            // abstract.
            if (over > 0 || short > 0) ...[
              const SizedBox(height: Space.xs),
              Text(
                'Over means you used more than the forecast expected; '
                'short means you used less.',
                style: muted,
              ),
            ],
            if (noForecast > 0 && hadForecast) ...[
              const SizedBox(height: Space.xs),
              Text(
                noForecast == 1
                    ? '1 item was not in the forecast — nothing to compare.'
                    : '$noForecast items were not in the forecast — nothing '
                          'to compare.',
                style: muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The headline variance sentence — "12 items matched, 3 over, 1 short" —
/// or the plain truth when there is nothing to compare against. Only
/// non-zero counts are said; a clause is never padded with a 0.
@visibleForTesting
String varianceHeadline({
  required int matched,
  required int over,
  required int short,
  required bool hadForecast,
}) {
  if (matched + over + short == 0) {
    return hadForecast
        ? 'None of these items was in the forecast, so there is nothing to '
              'compare with.'
        : 'No forecast was made for this event, so there is nothing to '
              'compare with.';
  }
  // "12 items matched, 3 over, 1 short": every clause counts items, so the
  // noun is said once, on the first one, and agrees with ITS number.
  final clauses = <({int count, String word})>[
    if (matched > 0) (count: matched, word: 'matched'),
    if (over > 0) (count: over, word: 'over'),
    if (short > 0) (count: short, word: 'short'),
  ];
  final lead = clauses.first;
  return [
    '${lead.count} ${lead.count == 1 ? 'item' : 'items'} ${lead.word}',
    for (final clause in clauses.skip(1)) '${clause.count} ${clause.word}',
  ].join(', ');
}

/// One item: what was counted (the row's trailing quantity), what was
/// expected and by how much it differed, and what it cost at the
/// snapshotted price.
class _ReportRowCard extends StatelessWidget {
  const _ReportRowCard({required this.row});

  final _ReportRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    // `bodyMedium`, not the caption tier: these two lines are the only
    // place the absence is stated, and a caption may never be the sole
    // carrier of meaning (theme.dart, on the 13 pt reading floor). The
    // figures beside them qualify the row quantity, so those may be
    // captions.
    final absent = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final variance = row.varianceMicros;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(row.itemName, style: theme.textTheme.titleMedium),
                ),
                const SizedBox(width: Space.m),
                Text(
                  QuantityCodec.formatDisplayMicros(row.usedMicros),
                  style: Numerals.rowQuantity(theme.textTheme),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            if (row.expectedMicros case final expected?)
              // Icon + word + colour: a state is never colour alone (§5).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    variance == 0
                        ? Icons.check_circle_outline
                        : variance! > 0
                        ? Icons.trending_up
                        : Icons.trending_down,
                    size: 18,
                    color: variance == 0
                        ? status.confirmed.foreground
                        : status.pending.foreground,
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      _varianceCaption(expected, variance!),
                      style: Numerals.caption(theme.textTheme)?.copyWith(
                        color: variance == 0
                            ? status.confirmed.foreground
                            : status.pending.foreground,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text('No forecast for this item.', style: absent),
            const SizedBox(height: Space.xs),
            if ((row.cost, row.unitPrice) case (final cost?, final price?))
              Text(
                '${MoneyCodec.format(cost)} · '
                '${MoneyCodec.format(price)} each',
                style: Numerals.caption(
                  theme.textTheme,
                )?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Text('No price recorded — not counted.', style: absent),
          ],
        ),
      ),
    );
  }

  /// "Expected 45 · 14 fewer" — the two figures and the gap between them,
  /// in words the owner can check by subtracting.
  String _varianceCaption(int expected, int variance) {
    final expectedText =
        'Expected ${QuantityCodec.formatDisplayMicros(expected)}';
    if (variance == 0) return '$expectedText · matched';
    final size = QuantityCodec.formatDisplayMicros(variance.abs());
    return variance > 0
        ? '$expectedText · $size more'
        : '$expectedText · $size fewer';
  }
}
