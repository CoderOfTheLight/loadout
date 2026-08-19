/// Append-only record view (design §9 MovementDetailScreen): when it
/// happened, the event link, the note, and correction links. The internal
/// source-command id is model leakage and is not shown; "Recorded" only
/// appears when it differs from "Occurred". Single
/// action "Correct this entry" — no delete, no edit. Consume-kind and
/// closeout-linked rows are refused by the applier, so this screen
/// surfaces that state instead of offering the action; the same goes for
/// reversal rows and already-corrected rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../events/application/event_service.dart';
import 'movement_display.dart';
import 'movement_providers.dart';

class MovementDetailScreen extends ConsumerWidget {
  const MovementDetailScreen({super.key, required this.movementId});

  final String movementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provenance = ref.watch(movementProvenanceProvider(movementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Movement')),
      body: provenance.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text("Couldn't load this entry.")),
        data: (view) => view == null
            ? const Center(child: Text('Entry not found.'))
            : _MovementDetailBody(view: view),
      ),
    );
  }
}

class _MovementDetailBody extends ConsumerWidget {
  const _MovementDetailBody({required this.view});

  final MovementProvenance view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final movement = view.movement;
    final struck = view.isCorrected
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    final eventId = movement.eventId as String?;
    final eventName = eventId == null
        ? null
        : _eventName(ref, eventId) ?? 'Event';

    return ContentColumn(
      child: ListView(
        children: [
          Row(
            children: [
              Icon(movementKindIcon(movement.kind), size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.isReversal
                          ? 'Correction of an earlier entry'
                          : movementKindLabel(movement.kind),
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      view.itemName,
                      style: theme.textTheme.headlineSmall?.merge(struck),
                    ),
                  ],
                ),
              ),
              Text(
                formatDeltaMicros(movement.deltaMicros, view.itemUnit),
                style: theme.textTheme.titleLarge?.merge(struck),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _provenanceCard(context, eventName, eventId),
          const SizedBox(height: 16),
          ..._correctionLinks(context),
          const SizedBox(height: 8),
          _actionArea(context),
        ],
      ),
    );
  }

  String? _eventName(WidgetRef ref, String eventId) {
    final events = ref
        .watch(eventListProvider(EventStatusFilter.all))
        .valueOrNull;
    if (events == null) return null;
    for (final event in events) {
      if (event.id == eventId) return event.name;
    }
    return null;
  }

  Widget _provenanceCard(
    BuildContext context,
    String? eventName,
    String? eventId,
  ) {
    final movement = view.movement;
    final occurred = dateTimeLabel(instantToLocal(movement.occurredAt));
    final recorded = dateTimeLabel(instantToLocal(movement.recordedAt));
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.today_outlined),
            title: const Text('Occurred'),
            subtitle: Text(occurred),
          ),
          // Only worth a row when it says something new: nearly every entry
          // is recorded when it happened, and a second identical timestamp
          // is a row she has to read to learn nothing.
          if (recorded != occurred)
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Recorded'),
              subtitle: Text(recorded),
            ),
          if (eventId != null)
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Event'),
              subtitle: Text(eventName ?? eventId),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/events/$eventId'),
            ),
          if (movement.note.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Note'),
              subtitle: Text(movement.note),
            ),
        ],
      ),
    );
  }

  List<Widget> _correctionLinks(BuildContext context) {
    final links = <Widget>[];
    final reverses = view.movement.reverses;
    if (reverses != null) {
      links.add(
        ListTile(
          leading: const Icon(Icons.undo),
          title: const Text('Corrects an earlier entry'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/movements/${reverses as String}'),
        ),
      );
    }
    final reversedBy = view.reversedByMovementId;
    if (reversedBy != null) {
      links.add(
        ListTile(
          leading: const Icon(Icons.undo),
          title: const Text('Corrected by a later entry'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/movements/$reversedBy'),
        ),
      );
    }
    final replacement = view.replacementMovementId;
    if (replacement != null && view.isCorrected && !view.isCloseoutWritten) {
      links.add(
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Replaced by a corrected entry'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/movements/$replacement'),
        ),
      );
    }
    return links;
  }

  /// §9: single action "Correct this entry" when the applier would accept
  /// it; otherwise a clear statement of why not — never a disabled button.
  Widget _actionArea(BuildContext context) {
    if (view.isCloseoutWritten) {
      final eventId = view.movement.eventId as String?;
      return _stateCard(
        context,
        icon: Icons.lock_outline,
        text:
            'This entry was written by an event closeout. To change it, '
            'revise that event\'s closeout — inventory and event history '
            'always stay in step.',
        actionLabel: eventId == null ? null : 'Open closeout',
        onAction: eventId == null
            ? null
            : () => context.push('/events/$eventId/closeout'),
      );
    }
    if (view.isReversal) {
      return _stateCard(
        context,
        icon: Icons.undo,
        text:
            'This is a correction entry. It cannot be corrected again — '
            'record a fresh entry instead.',
      );
    }
    if (view.isCorrected) {
      return _stateCard(
        context,
        icon: Icons.check_circle_outline,
        text:
            'This entry has already been corrected. The original stays '
            'visible; the correction carries the change.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Corrections keep the original entry visible and add a '
          'reversing entry.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
          onPressed: () =>
              context.push('/movements/${view.movement.id}/correct'),
          child: const Text('Correct this entry'),
        ),
      ],
    );
  }

  Widget _stateCard(
    BuildContext context, {
    required IconData icon,
    required String text,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
              ],
            ),
            if (actionLabel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
