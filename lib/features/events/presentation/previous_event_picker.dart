/// "Copy items from a previous event" (proposal §3): the owner's events
/// repeat — the same Friday dinner, largely the same supplies — so planning
/// the next one should not mean re-picking forty items by hand.
///
/// This file is the whole feature bar the button that opens it: the chooser
/// sheet (past events newest first, with what each was called, when it ran,
/// and how long its list was), the pure merge that folds a chosen event's
/// list into the one on screen, and the sentences that report what happened.
///
/// Two properties the flow is built around:
///
///  * **Additive, never destructive.** What is already planned stays,
///    duplicates are not created, nothing is removed. [planCopy] only ever
///    appends.
///  * **Not a write.** [planCopy] returns a new list of item ids; the edit
///    form submits it through `createEvent` / `updateEvent` exactly as it
///    submits a hand-picked list. A copy is an ordinary edit to the planned
///    list, so it inherits the same validation and the same single write
///    path — one command, one transaction, one audit row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/empty_state.dart';
import '../application/event_service.dart';

/// Past events available to copy from, excluding the event being edited
/// (null at `/events/new`). One-shot rather than a live query: a modal
/// chooser has nothing to gain from a redraw, and `autoDispose` refetches
/// each time the form is entered.
final copySourceEventsProvider = FutureProvider.autoDispose
    .family<List<CopySourceEvent>, String?>(
      (ref, excludingEventId) => ref
          .watch(eventServiceProvider)
          .copySourceEvents(excludingEventId: excludingEventId),
    );

/// Opens the chooser. Returns the event picked, or null when dismissed.
Future<CopySourceEvent?> showPreviousEventPicker(
  BuildContext context, {
  String? excludeEventId,
}) => showModalBottomSheet<CopySourceEvent>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
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
    final sources = ref.watch(copySourceEventsProvider(excludeEventId));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                'Its items are added to this event. '
                'Nothing already planned is removed.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: sources.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Events could not be loaded.'),
                  ),
                  data: (events) => events.isEmpty
                      // Unreachable from the form, which hides the button
                      // with nothing to copy from — kept for the race where
                      // the last other event goes while the form is open.
                      ? const EmptyState(
                          message: 'No other events to copy from yet.',
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final (index, event) in events.indexed)
                              ListTile(
                                title: Text(event.name),
                                // Newest first, so the top row IS the most
                                // recent — saying so turns the ordering into
                                // a suggestion rather than trivia.
                                subtitle: Text(
                                  '${event.scheduledDate} · '
                                  '${copyItemCount(event.itemCount)}'
                                  '${index == 0 ? ' · Most recent' : ''}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).pop(event),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What copying a past event's list would do to the list on screen.
final class CopyOutcome {
  const CopyOutcome({
    required this.merged,
    required this.addedCount,
    required this.alreadyThereCount,
    required this.missingCount,
  });

  /// The list on screen with the copied items appended — existing entries
  /// first, in their existing order. This is what gets submitted.
  final List<String> merged;
  final int addedCount;

  /// Copied items that were already planned here: counted, not re-added.
  final int alreadyThereCount;

  /// Items the past event planned that have since been archived or deleted.
  final int missingCount;

  /// Nothing to add — the source was empty, or everything it still has is
  /// already here. The offer becomes an explanation rather than a button.
  bool get addsNothing => addedCount == 0;
}

/// Folds [copy] into [current], additively: order preserved, duplicates
/// counted instead of created, nothing removed.
CopyOutcome planCopy({
  required List<String> current,
  required PlannedItemsCopy copy,
}) {
  final seen = current.toSet();
  final additions = [
    for (final itemId in copy.itemIds)
      if (seen.add(itemId)) itemId,
  ];
  return CopyOutcome(
    merged: [...current, ...additions],
    addedCount: additions.length,
    alreadyThereCount: copy.itemIds.length - additions.length,
    missingCount: copy.missingCount,
  );
}

String copyItemCount(int count) => '$count item${count == 1 ? '' : 's'}';

String _noLonger(int count) => 'no longer ${count == 1 ? 'exists' : 'exist'}';

/// The consequence, stated before the tap that causes it.
String copyConfirmMessage(CopyOutcome outcome) => [
  'Adds ${copyItemCount(outcome.addedCount)} to this event.',
  if (outcome.alreadyThereCount > 0)
    '${outcome.alreadyThereCount} '
        '${outcome.alreadyThereCount == 1 ? 'is' : 'are'} '
        'already on the list.',
  if (outcome.missingCount > 0)
    '${copyItemCount(outcome.missingCount)} '
        '${_noLonger(outcome.missingCount)}.',
].join(' ');

/// The receipt afterwards: what landed, what was already there, what could
/// not come.
String copyOutcomeMessage(CopyOutcome outcome) => [
  'Added ${copyItemCount(outcome.addedCount)}',
  if (outcome.alreadyThereCount > 0)
    '${outcome.alreadyThereCount} '
        '${outcome.alreadyThereCount == 1 ? 'was' : 'were'} '
        'already on the list',
  if (outcome.missingCount > 0)
    '${outcome.missingCount} ${_noLonger(outcome.missingCount)}',
].join(' · ');

/// Why a copy has nothing to add — said plainly, never as a failure.
String copyNothingToAddMessage(
  CopyOutcome outcome, {
  required int sourceItemCount,
}) {
  if (sourceItemCount == 0) return 'That event has no items to copy.';
  if (outcome.missingCount == 0) {
    return 'Everything on that list is already here.';
  }
  if (outcome.alreadyThereCount == 0) {
    return 'Nothing to copy: ${copyItemCount(outcome.missingCount)} '
        '${_noLonger(outcome.missingCount)}.';
  }
  return 'Nothing new to add: the rest is already here, and '
      '${copyItemCount(outcome.missingCount)} '
      '${_noLonger(outcome.missingCount)}.';
}
