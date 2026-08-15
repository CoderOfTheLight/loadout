/// The Home nudge into the one-time tidy-up flow (proposal §5).
///
/// Shown only to migrated workspaces: items exist but the `folders` table
/// is empty, because the v2→v3 migration seeds nothing — a fresh workspace
/// is born with the eight starter folders and never sees this card. It is
/// dismissible ("Not now") and comes back next launch, until the owner
/// either finishes the tidy-up (folders exist) or says "Don't show again",
/// which is remembered for good.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../data/db/app_database.dart' as db;
import '../../../data/db/table_watch.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../catalog/presentation/tidy_folders_screen.dart';

/// Settings key for "Don't show again". Preference, not a record — the
/// same explicit exception to the command path as every other settings row.
const String tidyPromptHiddenKey = 'tidy_folders_prompt_hidden';

/// "Not now" for this session; deliberately NOT autoDispose and NOT
/// persisted, so the card comes back on the next launch.
final tidyPromptSessionDismissedProvider = StateProvider<bool>((_) => false);

/// The persisted "Don't show again" flag.
final tidyPromptHiddenProvider = StreamProvider<bool>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database
      .watchTables('home.tidyPromptHidden', {database.settings})
      .asyncMap(
        (_) async =>
            await database.settingsDao.value(tidyPromptHiddenKey) == 'true',
      );
});

/// Whether Home should show the tidy card: no live folders yet (the
/// migrated-workspace signature — fresh workspaces are seeded with eight),
/// not hidden for good, not dismissed this session. The caller adds the
/// "items exist" half, which it already watches.
final tidyPromptVisibleProvider = Provider.autoDispose<bool>((ref) {
  if (ref.watch(tidyPromptSessionDismissedProvider)) return false;
  final folders = ref.watch(folderListProvider);
  final hidden = ref.watch(tidyPromptHiddenProvider);
  return folders.valueOrNull?.isEmpty == true && hidden.valueOrNull == false;
});

/// The card itself: one tap opens the tidy screen; nothing on it moves any
/// item.
class TidyPromptCard extends ConsumerWidget {
  const TidyPromptCard({super.key});

  Future<void> _hideForGood(WidgetRef ref) async {
    // The settings watcher hides the card as soon as the row lands — the
    // card visibly going away IS the write's receipt. (Deliberately no
    // session-flag shortcut here: flipping it would tear this widget down
    // while its own write is still in flight.)
    final database = ref.read(appDatabaseProvider);
    await database
        .into(database.settings)
        .insertOnConflictUpdate(
          db.SettingsCompanion.insert(
            key: tidyPromptHiddenKey,
            value: jsonEncode(true),
            updatedAtMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            child: InkWell(
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TidyFoldersScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  Space.l,
                  Space.l,
                  Space.s,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(Space.s),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.drive_file_move_outlined,
                        size: 22,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tidy your items into folders',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '2 minutes, once',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.xs),
            child: Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      ref
                              .read(tidyPromptSessionDismissedProvider.notifier)
                              .state =
                          true,
                  child: const Text('Not now'),
                ),
                TextButton(
                  onPressed: () => _hideForGood(ref),
                  child: const Text("Don't show again"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
