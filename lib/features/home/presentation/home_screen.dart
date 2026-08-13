/// "What needs attention now" (design §9 HomeScreen). Read-only dashboard,
/// in priority order: (1) pending-closeout nudges for active events past
/// their date; (2) next-event card with forecast readiness; (3) quick
/// actions; (4) data health — items with negative derived on-hand;
/// (5) last five movements + "See all". No commands are issued here.
///
/// Owner feedback: *"The menu is confusing, just add item? We need to make
/// that better."* A fresh workspace used to offer a single bare button with
/// no explanation of what the app was for. It now opens with the three-step
/// loop in her words — add what you sell, plan an event, say what you used —
/// and two obvious first steps. Once there is data the screen leads with the
/// day and with what needs doing, not with a list of nouns.
///
/// Quantities are shown without a unit: an item is a NAME and a COUNT now,
/// and "each" is noise on a dashboard.
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
    final pendingCloseouts = [
      for (final event in activeEvents)
        if (event.scheduledDate.compareTo(today) < 0) event,
    ];
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

          SectionHeader('Quick actions'),
          _ActionTile(
            icon: Icons.shopping_bag_outlined,
            title: 'Record a purchase',
            subtitle: 'Stock you bought or brought in',
            onTap: () => context.push('/movements/new?kind=receive'),
          ),
          const SizedBox(height: Space.s),
          _ActionTile(
            icon: Icons.rule,
            title: 'Count stock',
            subtitle: "Set an item to what's actually there",
            onTap: () => context.push('/movements/new?kind=count'),
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

/// A market day that was activated and never closed out. Everything the
/// forecast learns comes from closeouts, so this outranks the whole screen.
class _CloseoutNudge extends StatelessWidget {
  const _CloseoutNudge({required this.event, required this.now});

  final EventSummary event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final held = relativeDayLabel(event.scheduledDate, now).toLowerCase();
    return Semantics(
      button: true,
      child: Card(
        color: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          onTap: () => context.push('/events/${event.id}/closeout'),
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconDisc(
                  icon: Icons.fact_check_outlined,
                  background: scheme.primary,
                  foreground: scheme.onPrimary,
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Close out ${event.name}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Held $held. Say what you actually used and the next '
                        'list gets closer.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The next market day, with how ready its forecast is.
class _NextEventCard extends ConsumerWidget {
  const _NextEventCard({required this.event, required this.now});

  final EventSummary event;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = ref.watch(latestSnapshotProvider(event.id));
    final readiness = snapshot.when(
      loading: () => 'Checking the forecast…',
      error: (_, _) => 'Forecast unavailable',
      data: (view) {
        if (view == null || view.lines.isEmpty) {
          return 'No forecast yet — open the event to make one.';
        }
        final total = view.lines.length;
        // Switch on `basis`, not `evidenceGrade`: a line with no closeout
        // history but a "1 serves 4" baseline DOES carry a number, and
        // calling it "no history" would hide a usable estimate.
        final blank = view.lines
            .where((line) => line.basis == ForecastBasis.insufficientData)
            .length;
        final estimated = view.lines
            .where((line) => line.basis == ForecastBasis.servesBaseline)
            .length;
        if (blank > 0) {
          return 'Forecast ready · $blank of $total items have nothing to go '
              'on yet';
        }
        if (estimated > 0) {
          return 'Forecast ready · $estimated estimated, not yet proven';
        }
        return 'Forecast ready · $total items';
      },
    );
    return Semantics(
      button: true,
      child: Card(
        child: InkWell(
          onTap: () => context.push('/events/${event.id}'),
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconDisc(
                  icon: Icons.event_outlined,
                  background: scheme.secondaryContainer,
                  foreground: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relativeDayLabel(event.scheduledDate, now),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(event.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: Space.xs),
                      Text(
                        readiness,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
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
              'Plan your next market day and Loadout works out what to take.',
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
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: scheme.onTertiaryContainer,
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    'These counts have gone below zero',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
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
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                subtitle: Text(
                  'Count it to set it straight',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: scheme.onTertiaryContainer,
                ),
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

/// A quick action. A card rather than an icon button: the label gets to
/// wrap at large text sizes, the explanation fits, and the whole row is the
/// target rather than a 56 dp strip.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconDisc(
                  icon: icon,
                  background: scheme.surfaceContainerHigh,
                  foreground: scheme.onSurface,
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconDisc extends StatelessWidget {
  const _IconDisc({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s),
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Icon(icon, size: 22, color: foreground),
  );
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
            'Tell Loadout what you sell and where you are selling it, and it '
            'works out what to take.',
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
                    title: 'Add what you sell',
                    body:
                        'The name, and how many you have. '
                        'That is the whole thing.',
                  ),
                  _Step(
                    number: 2,
                    title: 'Plan an event',
                    body:
                        'A market, a fair, a match day — Loadout turns it '
                        'into a list of what to pack.',
                  ),
                  _Step(
                    number: 3,
                    title: 'Say what you used',
                    body:
                        'Close out the day afterwards, and the next list is '
                        'built from what really happened.',
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
