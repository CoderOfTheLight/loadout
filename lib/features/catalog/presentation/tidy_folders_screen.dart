/// The one-time "tidy your items into folders" flow for migrated
/// workspaces (proposal §5): items exist but the `folders` table is empty,
/// because the v2→v3 migration deliberately seeds nothing — folders are the
/// owner's to create, never guessed at.
///
/// Every distinct legacy Group value the owner ever typed is shown once
/// (case-insensitively merged, so "Drinks" and "drinks" read as one), with
/// its item count. She points each group at a starter folder or a new one
/// of her own; groups she skips simply stay in Unfiled — visible at the end
/// of every list, never hidden. NOTHING moves until she confirms: the whole
/// mapping commits as `CreateFolder` + batch `MoveItemsToFolder` commands
/// on the confirm button, and backing out beforehand changes nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/form_action_bar.dart';
import '../../../app/widgets/screen_state.dart';
import '../../../data/db/app_database.dart' as db;
import '../application/catalog_service.dart';
import '../domain/demand_basis.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'demand_basis_choice.dart';

String _countLabel(int count) => count == 1 ? '1 item' : '$count items';

String _folderCountLabel(int count) =>
    count == 1 ? '1 folder' : '$count folders';

/// A destination the owner can point a group at. Identity matters: two
/// groups mapped to the same choice land in the same folder, created once.
/// [folderId] is null until the folder exists (set on confirm, or already
/// set for a live folder).
final class _FolderChoice {
  _FolderChoice({required this.name, required this.basis, this.folderId});

  final String name;
  final DemandBasis basis;
  String? folderId;
}

/// One legacy Group value, case-insensitively merged: [display] is the
/// casing the owner used most (first-typed wins a tie).
final class _LegacyGroup {
  const _LegacyGroup({
    required this.key,
    required this.display,
    required this.itemIds,
  });

  final String key;
  final String display;
  final List<String> itemIds;
}

enum _SheetAction { skip, newFolder }

class TidyFoldersScreen extends ConsumerStatefulWidget {
  const TidyFoldersScreen({super.key});

  @override
  ConsumerState<TidyFoldersScreen> createState() => _TidyFoldersScreenState();
}

class _TidyFoldersScreenState extends ConsumerState<TidyFoldersScreen> {
  /// Group key → chosen destination. Absent = skip (stays in Unfiled).
  final Map<String, _FolderChoice> _assignments = {};

  /// Folders the owner named herself in this session, in the order she
  /// added them; created only on confirm.
  final List<_FolderChoice> _customChoices = [];

  /// Live folders already in the workspace (rare on this screen — it is
  /// offered only while none exist — but correct if it is reopened after a
  /// partial commit).
  final Map<String, _FolderChoice> _existingByFolderId = {};

  /// The eight starters, in packing order, with their seeded answers to the
  /// one question — the same list a fresh workspace is born with.
  late final List<_FolderChoice> _starterChoices = [
    for (final (name, basis) in db.AppDatabase.starterFolders)
      _FolderChoice(name: name, basis: DemandBasis.fromDb(basis)),
  ];

  bool _submitting = false;

  List<_LegacyGroup> _groupsFrom(List<ItemSummary> summaries) {
    final idsByKey = <String, List<String>>{};
    final casingCounts = <String, Map<String, int>>{};
    final firstSeen = <String, String>{};
    for (final summary in summaries) {
      if (summary.item.folderId != null) continue; // already filed
      final raw = summary.item.category?.trim() ?? '';
      if (raw.isEmpty) continue;
      final key = raw.toLowerCase();
      idsByKey.putIfAbsent(key, () => []).add(summary.item.id.value);
      firstSeen.putIfAbsent(key, () => raw);
      final counts = casingCounts.putIfAbsent(key, () => {});
      counts[raw] = (counts[raw] ?? 0) + 1;
    }
    return [
      for (final key in idsByKey.keys)
        _LegacyGroup(
          key: key,
          display: _dominantCasing(casingCounts[key]!, firstSeen[key]!),
          itemIds: idsByKey[key]!,
        ),
    ]..sort((a, b) => a.key.compareTo(b.key));
  }

  String _dominantCasing(Map<String, int> counts, String firstSeen) {
    var best = firstSeen;
    var bestCount = counts[firstSeen] ?? 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }

  /// Destinations offered in the picker: the owner's live folders, then the
  /// starters that would not collide with one, then her session-added ones.
  List<_FolderChoice> _options() {
    final createdIds = {
      for (final choice in [..._starterChoices, ..._customChoices])
        if (choice.folderId != null) choice.folderId,
    };
    final existing = [
      for (final choice in _existingByFolderId.values)
        if (!createdIds.contains(choice.folderId)) choice,
    ];
    final taken = {
      for (final choice in existing) choice.name.toLowerCase(),
      for (final choice in _customChoices) choice.name.toLowerCase(),
    };
    return [
      ...existing,
      for (final starter in _starterChoices)
        if (!taken.contains(starter.name.toLowerCase())) starter,
      ..._customChoices,
    ];
  }

  Future<void> _pickDestination(_LegacyGroup group) async {
    final options = _options();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  0,
                  Space.l,
                  Space.s,
                ),
                child: Text(
                  'Where do "${group.display}" items go?',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: const Text('Leave in Unfiled'),
                subtitle: const Text('Skip for now — stays in plain sight.'),
                onTap: () => Navigator.of(sheetContext).pop(_SheetAction.skip),
              ),
              for (final option in options)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(option.name),
                  subtitle: Text(demandBasisLabel(option.basis)),
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('New folder…'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_SheetAction.newFolder),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _SheetAction.skip:
        setState(() => _assignments.remove(group.key));
      case _SheetAction.newFolder:
        final created = await _newFolderDialog(suggestedName: group.display);
        if (created != null && mounted) {
          setState(() {
            if (!_customChoices.contains(created) &&
                !_starterChoices.contains(created) &&
                !_existingByFolderId.values.contains(created)) {
              _customChoices.add(created);
            }
            _assignments[group.key] = created;
          });
        }
      case final _FolderChoice picked:
        setState(() => _assignments[group.key] = picked);
    }
  }

  /// Names a new folder and answers the one question for it. Nothing is
  /// created here — the choice is staged and lands with the confirm.
  /// Typing a name that matches a starter or an already-staged folder
  /// simply picks that folder instead of inventing a duplicate.
  Future<_FolderChoice?> _newFolderDialog({
    required String suggestedName,
  }) async {
    final controller = TextEditingController(text: suggestedName);
    var basis = DemandBasis.perPerson;
    String? error;
    final result = await showDialog<_FolderChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            title: const Text('New folder'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Folder name',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  Text(
                    'Does how much you bring depend on how many people come?',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Space.s),
                  DemandBasisChoice(
                    value: basis,
                    onChanged: (option) => setDialogState(() => basis = option),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) {
                    setDialogState(() => error = 'Enter a name');
                    return;
                  }
                  if (name.length > 60) {
                    setDialogState(
                      () => error = 'Keep the name under 60 characters',
                    );
                    return;
                  }
                  final lower = name.toLowerCase();
                  final match = [
                    ..._existingByFolderId.values,
                    ..._customChoices,
                    ..._starterChoices,
                  ].where((choice) => choice.name.toLowerCase() == lower);
                  Navigator.of(dialogContext).pop(
                    match.isEmpty
                        ? _FolderChoice(name: name, basis: basis)
                        : match.first,
                  );
                },
                child: const Text('Add folder'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  /// The confirm: create the still-missing folders (starters in their
  /// canonical order, then the owner's own), then move each mapped group's
  /// items in one batch command per destination folder. Skipped groups get
  /// no command at all — their items are already Unfiled.
  Future<void> _commit(List<_LegacyGroup> groups) async {
    final itemIdsByChoice = <_FolderChoice, List<String>>{};
    for (final group in groups) {
      final choice = _assignments[group.key];
      if (choice == null) continue;
      itemIdsByChoice.putIfAbsent(choice, () => []).addAll(group.itemIds);
    }
    // A no-op tidy: everything stays in Unfiled, which is a legal outcome.
    // Leave without writing anything and without a snackbar about zeroes.
    if (itemIdsByChoice.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _submitting = true);
    final service = ref.read(catalogServiceProvider);
    final toCreate = [
      for (final choice in _starterChoices)
        if (itemIdsByChoice.containsKey(choice) && choice.folderId == null)
          choice,
      for (final choice in _customChoices)
        if (itemIdsByChoice.containsKey(choice) && choice.folderId == null)
          choice,
    ];
    for (final choice in toCreate) {
      final created = await service.createFolder(
        name: choice.name,
        demandBasis: choice.basis,
      );
      final failed = created.fold((id) {
        choice.folderId = id;
        return false;
      }, (_) => true);
      if (failed) {
        _failCommit('Couldn\'t create the folder "${choice.name}". Try again.');
        return;
      }
    }
    var moved = 0;
    for (final entry in itemIdsByChoice.entries) {
      final result = await service.moveItemsToFolder(
        itemIds: entry.value,
        folderId: entry.key.folderId!,
      );
      final failed = result.fold((_) {
        moved += entry.value.length;
        return false;
      }, (_) => true);
      if (failed) {
        _failCommit("Couldn't move some items. Try again.");
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Filed ${_countLabel(moved)} into '
          '${_folderCountLabel(itemIdsByChoice.length)}.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  void _failCommit(String message) {
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemListProvider(const ItemFilter()));
    final foldersAsync = ref.watch(folderListProvider);
    final theme = Theme.of(context);

    final Widget body;
    Widget? actionBar;
    if (itemsAsync.hasError || foldersAsync.hasError) {
      body = ErrorState(
        message: "Couldn't load your items.",
        onRetry: () {
          ref.invalidate(itemListProvider);
          ref.invalidate(folderListProvider);
        },
      );
    } else if (itemsAsync.valueOrNull == null ||
        foldersAsync.valueOrNull == null) {
      body = const LoadingState();
    } else {
      // Idempotent memo: register the owner's live folders as reusable
      // destination choices, keeping one identity per folder across builds.
      for (final folder in foldersAsync.value!) {
        _existingByFolderId.putIfAbsent(
          folder.id.value,
          () => _FolderChoice(
            name: folder.name,
            basis: folder.demandBasis,
            folderId: folder.id.value,
          ),
        );
      }
      final summaries = itemsAsync.value!;
      final groups = _groupsFrom(summaries);
      final ungrouped = summaries
          .where(
            (summary) =>
                summary.item.folderId == null &&
                (summary.item.category?.trim() ?? '').isEmpty,
          )
          .length;
      final mappedItemCount = [
        for (final group in groups)
          if (_assignments.containsKey(group.key)) group.itemIds.length,
      ].fold(0, (a, b) => a + b);
      final mappedFolderCount = {
        for (final group in groups) ?_assignments[group.key],
      }.length;

      body = ContentColumn(
        padding: const EdgeInsets.fromLTRB(
          Space.l,
          Space.l,
          Space.l,
          Space.xxl,
        ),
        child: ListView(
          children: [
            Text(
              'Point each group at a folder — anything you skip stays in '
              'Unfiled.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.l),
            if (groups.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: Text(
                    'None of your items has a group, so there is nothing to '
                    'tidy here. They stay in Unfiled until you file them '
                    'from an item\'s own page.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final group in groups)
                      ListTile(
                        title: Text(group.display),
                        subtitle: Text(switch (_assignments[group.key]) {
                          final choice? =>
                            '${_countLabel(group.itemIds.length)} · moves to '
                                '${choice.name}',
                          null =>
                            '${_countLabel(group.itemIds.length)} · stays in '
                                'Unfiled',
                        }),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _submitting
                            ? null
                            : () => _pickDestination(group),
                      ),
                  ],
                ),
              ),
            if (groups.isNotEmpty && ungrouped > 0) ...[
              const SizedBox(height: Space.l),
              Text(
                ungrouped == 1
                    ? '1 item with no group stays in Unfiled.'
                    : '$ungrouped items with no group stay in Unfiled.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
      // The button is LIVE from the moment the screen opens. Moving nothing
      // is a legal answer to "where should these go?" — arriving at a
      // disabled button reading "Nothing to move yet" made a working screen
      // look broken before the owner had done anything at all.
      actionBar = FormActionBar(
        child: FilledButton(
          onPressed: _submitting ? null : () => _commit(groups),
          style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
          child: _submitting
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Text(
                  mappedItemCount == 0
                      ? 'Done'
                      : 'Move ${_countLabel(mappedItemCount)} into '
                            '${_folderCountLabel(mappedFolderCount)}',
                  textAlign: TextAlign.center,
                ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tidy your items into folders')),
      body: SafeArea(child: body),
      bottomNavigationBar: actionBar,
    );
  }
}
