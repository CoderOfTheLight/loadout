/// "Copy items from a previous event" (proposal §3): a chooser, not a
/// write. Pick an event and its still-live planned items arrive pre-ticked
/// in the planned-items picker — untick what differs. Returns the chosen
/// eventId, or null when dismissed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/empty_state.dart';
import '../application/event_service.dart';
import 'event_ui.dart';

Future<String?> showPreviousEventPicker(
  BuildContext context, {
  String? excludeEventId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => PreviousEventSheet(excludeEventId: excludeEventId),
);

class PreviousEventSheet extends ConsumerWidget {
  const PreviousEventSheet({super.key, this.excludeEventId});

  /// The event being edited, if any — copying an event onto itself is
  /// never a meaningful offer.
  final String? excludeEventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final events = ref.watch(eventListProvider(EventStatusFilter.all));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Copy items from a previous event',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Its list arrives pre-ticked — untick what differs.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: events.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Events could not be loaded.'),
                  ),
                  data: (all) {
                    final candidates =
                        [
                          for (final event in all)
                            if (event.id != excludeEventId) event,
                        ]..sort(
                          (a, b) => b.scheduledDate.compareTo(a.scheduledDate),
                        );
                    if (candidates.isEmpty) {
                      return const EmptyState(
                        message: 'No other events to copy from yet.',
                      );
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final event in candidates)
                          ListTile(
                            title: Text(event.name),
                            subtitle: Text(
                              '${event.scheduledDate} · '
                              '${eventStatusLabel(event.status)}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).pop(event.id),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
