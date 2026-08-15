/// "What needs attention now" (design §9 HomeScreen). Read-only dashboard,
/// in priority order: (1) pending-closeout nudges for active events past
/// their date; (2) next-event card with packing-list readiness; (3) the
/// one-time tidy-up nudge for migrated workspaces; (4) quick actions;
/// (5) data health — items with negative derived on-hand; (6) last five
/// movements + "See all". No commands are issued here.
///
/// Owner feedback: *"The menu is confusing, just add item? We need to make
/// that better."* A fresh workspace used to offer a single bare button with
/// no explanation of what the app was for. It now opens with the three-step
/// loop in her words — add the things you bring, plan an event, say how it
/// went — and two obvious first steps. Once there is data the screen leads
/// with the day and with what needs doing, not with a list of nouns.
///
/// Copy is proposal §4 verbatim: it must read true from the kitchen AND
/// the sales table, so "used or sold", "packing list" (never "forecast" on
/// Home — that word lives on the detail screens with the evidence), and
/// "add stock" (half of what arrives was never purchased).
///
/// Quantities are shown without a unit: an item is a NAME and a COUNT now,
/// and "each" is noise on a dashboard.
///
/// Visual language (design-spec §6 Home tiles): the lead "what needs doing"
/// tile carries at most two data points — an eyebrow stating the task, ONE
/// hero figure (a relative date), one supporting line. Urgency is the
/// complete KDS ladder and nothing else — neutral / amber "Due soon" / red
/// "Overdue" / green "All set" — always encoded as 4 dp left border + icon
/// + word + tint, never color alone, and pending cards sort oldest-first so
/// position redundantly encodes urgency. Quick actions are a 2-up grid of
/// labeled tiles. Data rows stay monochrome and motionless.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/screen_state.dart';
import '../../../app/widgets/section_header.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../catalog/application/catalog_service.dart';
import '../../events/application/event_service.dart';
import '../../forecasting/domain/snapshot.dart';
import '../../inventory/application/inventory_service.dart';
import '../../inventory/presentation/movement_display.dart';
import 'tidy_prompt.dart';

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// `2026-08-12` for comparing against stored `scheduled_date` strings.
String _isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// `Wednesday 12 August` — the line above the dashboard heading.
String _longDay(DateTime day) =>
    '${_weekdayNames[day.weekday - 1]} ${day.day} '
    '${_monthNames[day.month - 1]}';

/// `Today` / `Tomorrow` / `In 3 days` / `4 days ago` / `15 Aug`.
String relativeDayLabel(String scheduledDate, DateTime now) {
  final parsed = DateTime.tryParse(scheduledDate);
  if (parsed == null) return scheduledDate;
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = day.difference(today).inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    > 1 && <= 7 => 'In $days days',
    < -1 && >= -7 => '${-days} days ago',
    _ => '${day.day} ${_monthNames[day.month - 1].substring(0, 3)}',
  };
}

/// Signed count with no unit: `−2`, `12`. Negatives keep U+2212.
String formatSignedCount(int micros) {
  final magnitude = QuantityCodec.format(Quantity.fromMicros(micros.abs()));
  return micros < 0 ? '−$magnitude' : magnitude;
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider).valueOrNull;
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
      body = ErrorState(
        message: "Couldn't load your workspace.",
        onRetry: () {
          ref.invalidate(itemListProvider);
          ref.invalidate(eventListProvider);
          ref.invalidate(movementLogProvider);
        },
      );
    } else if (items.valueOrNull == null ||
        active.valueOrNull == null ||
        upcoming.valueOrNull == null ||
        recent.valueOrNull == null) {
      body = const LoadingState();
    } else {
      body = _Dashboard(
        items: items.value!,
        activeEvents: active.value!,
        upcomingEvents: upcoming.value!,
        recentMovements: recent.value!,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(workspace?.displayName ?? 'Loadout')),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty &&
        activeEvents.isEmpty &&
        upcomingEvents.isEmpty &&
        recentMovements.isEmpty) {
      return const _FirstRunGuide();
    }

    final now = DateTime.now();
    final today = _isoDay(now);
    // Most important nudge in the app: activated but never closed out.
    // Oldest first: position redundantly encodes urgency (spec §6).
    final pendingCloseouts = [
      for (final event in activeEvents)
        if (event.scheduledDate.compareTo(today) < 0) event,
    ]..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final nextEvent = _nextEvent(today);
    final negatives = [
      for (final summary in items)
        if (summary.isNegative) summary,
    ];
    final hasWork = pendingCloseouts.isNotEmpty || nextEvent != null;

    return ContentColumn(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
      child: ListView(
        children: [
          _DayHeading(
            date: _longDay(now),
            heading: hasWork ? 'What needs doing' : "You're up to date",
          ),
          const SizedBox(height: Space.l),

          for (final event in pendingCloseouts) ...[
            _CloseoutNudge(event: event, now: now),
            const SizedBox(height: Space.m),
          ],

          if (nextEvent != null)
            _NextEventCard(event: nextEvent, now: now)
          else if (pendingCloseouts.isEmpty)
            const _NoEventCard(),

          // Migrated workspace (items, but no folders yet): the one-time
          // tidy-up nudge. Nothing moves unless she opens it and confirms.
          if (items.isNotEmpty && ref.watch(tidyPromptVisibleProvider)) ...[
            const SizedBox(height: Space.m),
            const TidyPromptCard(),
          ],

          SectionHeader('Quick actions'),
          // Spec §6: quick actions are a 2-up grid of labeled tiles —
          // icon + word, never icon alone. IntrinsicHeight keeps the pair
          // the same height when one label wraps at a large text size.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Add stock',
                    onTap: () => context.push('/movements/new?kind=receive'),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.rule,
                    label: "Count what's there",
                    onTap: () => context.push('/movements/new?kind=count'),
                  ),
                ),
              ],
            ),
          ),

          if (negatives.isNotEmpty) ...[
            SectionHeader('Worth a look'),
            _NegativeStockCard(negatives: negatives),
          ],

          SectionHeader(
            'Recent activity',
            actionLabel: 'See all',
            onAction: () => context.push('/activity'),
          ),
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

  Widget _recentActivity(BuildContext context, WidgetRef ref) {
    if (recentMovements.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Text(
            'Nothing recorded yet. A purchase or a count is what gives an '
            'item its number.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final eventNames = {
      for (final event
          in ref.watch(eventListProvider(EventStatusFilter.all)).valueOrNull ??
              const <EventSummary>[])
        event.id: event.name,
    };
    return Card(
      child: Column(
        children: [
          for (final view in recentMovements)
            MovementRow(
              view: view,
              eventName: view.movement.eventId == null
                  ? null
                  : eventNames[view.movement.eventId as String],
              onTap: () => context.push('/movements/${view.movement.id}'),
            ),
        ],
      ),
    );
  }
}

/// The date line plus the one-line answer to "is there anything for me?".
class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.date, required this.heading});

  final String date;
  final String heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          date,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(heading, style: theme.textTheme.headlineSmall),
      ],
    );
  }
}

/// An event that was activated and never closed out. Everything the
/// forecast learns comes from closeouts, so this outranks the whole screen.
///
/// The lead tile (spec §6): eyebrow states the task, the hero figure is the
/// relative date, one supporting line carries the rest. Urgency rides the
/// ladder — amber "Due soon" the day after, red "Overdue" from then on —
/// always border + icon + word + tint together, never color alone.
class _CloseoutNudge extends StatelessWidget {
  const _CloseoutNudge({required this.event, required this.now});

  final EventSummary event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final parsed = DateTime.tryParse(event.scheduledDate);
    final daysAgo = parsed == null
        ? 1
        : DateTime(
            now.year,
            now.month,
            now.day,
          ).difference(DateTime(parsed.year, parsed.month, parsed.day)).inDays;
    // The complete ladder, nothing finer: yesterday is amber "Due soon",
    // older is red "Overdue". Never a fourth threshold.
    final overdue = daysAgo > 1;
    final tint = overdue ? scheme.errorContainer : status.warning;
    final ink = overdue ? scheme.onErrorContainer : status.onWarning;
    final urgencyWord = overdue ? 'Overdue' : 'Due soon';
    final urgencyIcon = overdue ? Icons.error_outline : Icons.schedule_outlined;
    return Semantics(
      button: true,
      child: Card(
        color: tint,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: ink.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          onTap: () => context.push('/events/${event.id}/closeout'),
          // IntrinsicHeight bounds the stretch so the 4 dp border strip can
          // fill the card's height inside an unbounded ListView.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The 4 dp urgency border — one edge, never a full fill.
                Container(width: 4, color: ink),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Eyebrow + state word wrap instead of overflowing at
                        // 200 % text scale on a narrow phone.
                        Wrap(
                          spacing: Space.m,
                          runSpacing: Space.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'CLOSEOUT PENDING',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: ink,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(urgencyIcon, size: 18, color: ink),
                                const SizedBox(width: Space.xs),
                                // Flexible so the word can never overflow
                                // a narrow run at 200 % text scale.
                                Flexible(
                                  child: Text(
                                    urgencyWord,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          relativeDayLabel(event.scheduledDate, now),
                          style: Numerals.hero(
                            theme.textTheme,
                          )?.copyWith(color: ink),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'Close out ${event.name} — confirm what was used '
                          'and sold, and the next packing list gets sharper.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: Space.m),
                  child: Center(child: Icon(Icons.chevron_right, color: ink)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The next event, with how ready its packing list is. On Home it is a
/// packing list — that is what the owner is holding; "forecast" stays on
/// the detail screens, where the evidence lives.
class _NextEventCard extends ConsumerWidget {
  const _NextEventCard({required this.event, required this.now});

  final EventSummary event;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = ref.watch(latestSnapshotProvider(event.id));
    // (message, allSet): allSet only when every line carries a number the
    // engine learned from confirmed history — that is the green "All set"
    // rung of the ladder; anything less stays neutral.
    final (readiness, allSet) = snapshot.when(
      loading: () => ('Checking the packing list…', false),
      error: (_, _) => ('Packing list unavailable', false),
      data: (view) {
        if (view == null || view.lines.isEmpty) {
          return ('No packing list yet — open the event to make one.', false);
        }
        final total = view.lines.length;
        // Switch on `basis`, not `evidenceGrade`: a line with no closeout
        // history but a "1 serves 4" or "usually bring 2" baseline DOES
        // carry a number, and calling it "no history" would hide a usable
        // estimate.
        final blank = view.lines
            .where((line) => line.basis == ForecastBasis.insufficientData)
            .length;
        final estimated = view.lines
            .where(
              (line) =>
                  line.basis == ForecastBasis.servesBaseline ||
                  line.basis == ForecastBasis.perEventBaseline,
            )
            .length;
        if (blank > 0) {
          return (
            blank == 1
                ? 'Packing list ready · 1 item Loadout knows nothing about yet'
                : 'Packing list ready · $blank items Loadout knows nothing '
                      'about yet',
            false,
          );
        }
        if (estimated > 0) {
          return (
            estimated == 1
                ? 'Packing list ready · 1 amount is still a first guess'
                : 'Packing list ready · $estimated amounts are still first '
                      'guesses',
            false,
          );
        }
        return (
          total == 1
              ? 'Packing list ready · 1 item'
              : 'Packing list ready · $total items',
          true,
        );
      },
    );
    final ink = allSet ? scheme.onPrimaryContainer : null;
    return Semantics(
      button: true,
      child: Card(
        color: allSet ? scheme.primaryContainer : null,
        clipBehavior: Clip.antiAlias,
        shape: allSet
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.card),
                side: BorderSide(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.35),
                ),
              )
            : null,
        child: InkWell(
          onTap: () => context.push('/events/${event.id}'),
          // IntrinsicHeight bounds the stretch so the 4 dp border strip can
          // fill the card's height inside an unbounded ListView.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Green "All set" keeps the same border + icon + word
                // anatomy as the amber and red rungs; neutral cards carry
                // no border.
                if (allSet) Container(width: 4, color: scheme.primary),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: Space.m,
                          runSpacing: Space.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              relativeDayLabel(event.scheduledDate, now),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: ink ?? scheme.primary,
                              ),
                            ),
                            if (allSet)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                    color: ink,
                                  ),
                                  const SizedBox(width: Space.xs),
                                  Flexible(
                                    child: Text(
                                      'All set',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(color: ink),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          event.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          readiness,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ink ?? scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: Space.m),
                  child: Center(
                    child: Icon(
                      Icons.chevron_right,
                      color: ink ?? scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing on the calendar: say so, and offer the one useful next move.
class _NoEventCard extends StatelessWidget {
  const _NoEventCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('No event coming up', style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'Plan your next event and Loadout will work out what to bring.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.m),
            OutlinedButton(
              onPressed: () => context.push('/events/new'),
              child: const Text('Plan an event', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

/// Items whose derived on-hand went below zero. Never clamped, never hidden
/// — but phrased as something to tidy, not as an error the owner caused.
class _NegativeStockCard extends StatelessWidget {
  const _NegativeStockCard({required this.negatives});

  final List<ItemSummary> negatives;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The semantic amber (spec §5) — the ONE warning color in the state
    // grammar, with icon + words carrying the meaning beside it.
    final status = StatusColors.of(context);
    return Card(
      color: status.warning,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: status.onWarning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: status.onWarning),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    'These counts have gone below zero',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: status.onWarning,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final summary in negatives)
            Semantics(
              button: true,
              // U+2212 is not reliably announced; spell the sign out.
              label:
                  '${summary.item.name} is showing minus '
                  '${formatSignedCount(-summary.onHandMicros)}. '
                  'Count it to set it straight.',
              excludeSemantics: true,
              child: ListTile(
                title: Text(
                  '${summary.item.name} is showing '
                  '${formatSignedCount(summary.onHandMicros)}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: status.onWarning,
                  ),
                ),
                subtitle: Text(
                  'Count it to set it straight',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: status.onWarning,
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: status.onWarning),
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
}

/// One quick-action tile (spec §6): a 2-up grid cell, at least 88 dp tall,
/// icon + label — labeled always, never icon alone. The whole card is the
/// target, and the label wraps rather than truncating at large text sizes.
class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.m,
                vertical: Space.l,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: scheme.onSurfaceVariant),
                  const SizedBox(height: Space.s),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The fresh-workspace screen. Owner feedback #5 in full: this is where the
/// app has to say what it is FOR before it asks for anything.
class _FirstRunGuide extends StatelessWidget {
  const _FirstRunGuide();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ContentColumn(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
      child: ListView(
        children: [
          Text(
            'Bring the right amount to every event.',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.m),
          Text(
            'List what you bring — the food you make, the supplies you set '
            'out, the things you sell — and Loadout works out how much to '
            'take.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(
                children: const [
                  _Step(
                    number: 1,
                    title: 'Add the things you bring',
                    body:
                        'Cooked, bought, supplies, or things you sell. '
                        'A name and a count is enough.',
                  ),
                  _Step(
                    number: 2,
                    title: 'Plan an event',
                    body:
                        'Set the date and roughly how many people. Loadout '
                        'turns that into a packing list.',
                  ),
                  _Step(
                    number: 3,
                    title: 'Say how it went',
                    body:
                        'Afterwards, confirm what was used or sold. Every '
                        'next list is built from what really happened.',
                    last: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () => context.push('/items/new'),
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            child: const Text('Add my first item', textAlign: TextAlign.center),
          ),
          const SizedBox(height: Space.m),
          OutlinedButton(
            onPressed: () => context.push('/events/new'),
            style: OutlinedButton.styleFrom(minimumSize: primaryButtonMinSize),
            child: const Text('Plan an event', textAlign: TextAlign.center),
          ),
          const SizedBox(height: Space.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  'Everything you enter stays on this phone.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    this.last = false,
  });

  final int number;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.l,
        Space.m,
        Space.l,
        last ? Space.m : Space.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            // Constraints rather than a fixed box: at a large system text
            // size the numeral has to be allowed to grow the badge.
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
