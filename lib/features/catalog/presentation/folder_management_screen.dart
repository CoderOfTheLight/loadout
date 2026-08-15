/// Folder management (folders proposal §2): the short managed list every
/// screen sections by. Rename, add, drag into the packing order, archive,
/// set the folder's default answer to the one question, and mark a folder
/// as coming along to every event.
///
/// Reached from the item list's overflow menu (a plain [Navigator] push —
/// this is catalog furniture, not a tab). Every write goes through
/// `CatalogService`; the screen holds no state of its own beyond what the
/// streams say.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../core/result.dart';
import '../application/catalog_service.dart';
import '../domain/demand_basis.dart';
import '../domain/folder.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'demand_basis_choice.dart';
import 'folder_dialogs.dart';

class FolderManagementScreen extends ConsumerWidget {
  const FolderManagementScreen({super.key});

  void _showError(BuildContext context) {
    // Content-free by design (§9): no names or quantities in errors.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't save this change. Try again.")),
    );
  }

  /// [newIndex] arrives already adjusted for the removed item
  /// (`onReorderItem` semantics).
  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<Folder> folders,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex == oldIndex) {
      return;
    }
    final ids = [for (final folder in folders) folder.id.value];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    final result = await ref.read(catalogServiceProvider).reorderFolders(ids);
    if (result case Err() when context.mounted) {
      _showError(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(folderListProvider);
    final counts = {
      for (final section
          in ref.watch(foldersWithItemsProvider).valueOrNull ??
              const <FolderWithItems>[])
        if (section.folder != null)
          section.folder!.id.value: section.items.length,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
        actions: [
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => showCreateFolderDialog(context),
          ),
        ],
      ),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          message: "Folders couldn't be loaded.",
          icon: Icons.error_outline,
        ),
        data: (folders) {
          if (folders.isEmpty) {
            return EmptyState(
              title: 'No folders yet',
              message:
                  'Folders put every list in your packing order — items, '
                  'packing lists, closeout. Add one and file items into it.',
              icon: Icons.folder_outlined,
              actionLabel: 'Add a folder',
              onAction: () => showCreateFolderDialog(context),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: contentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.l,
                      Space.l,
                      Space.l,
                      Space.s,
                    ),
                    child: Text(
                      'Drag to match the order you pack. Every list in the '
                      'app reads in this order.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: Space.xxl),
                      itemCount: folders.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          _reorder(context, ref, folders, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        final count = counts[folder.id.value] ?? 0;
                        return ListTile(
                          key: ValueKey(folder.id.value),
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: Icon(
                              Icons.drag_indicator,
                              semanticLabel: 'Reorder ${folder.name}',
                            ),
                          ),
                          title: Text(folder.name),
                          subtitle: Text(
                            [
                              demandBasisLabel(folder.demandBasis),
                              '$count item${count == 1 ? '' : 's'}',
                              if (folder.alwaysPlanned)
                                'Comes along to every event',
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              _showFolderEditor(context, folder.id.value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFolderEditor(BuildContext context, String folderId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FolderEditorSheet(folderId: folderId),
    );
  }
}

/// The per-folder editor. Watches the folder stream so every control shows
/// what the workspace now says, and every change is an immediate service
/// write — no local draft to lose.
class _FolderEditorSheet extends ConsumerWidget {
  const _FolderEditorSheet({required this.folderId});

  final String folderId;

  Future<void> _setBasis(
    BuildContext context,
    WidgetRef ref, {
    DemandBasis? demandBasis,
    bool? alwaysPlanned,
  }) async {
    final result = await ref
        .read(catalogServiceProvider)
        .setFolderBasis(
          folderId: folderId,
          demandBasis: demandBasis,
          alwaysPlanned: alwaysPlanned,
        );
    if (result case Err() when context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save this change. Try again.")),
      );
    }
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    Folder folder,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Archive '${folder.name}'?"),
        content: const Text(
          'Its items move to Unfiled — nothing is deleted. The folder '
          "can't be brought back; if you need it again, add a new one "
          'with the same name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final result = await ref
        .read(catalogServiceProvider)
        .archiveFolder(folder.id.value);
    result.fold(
      (_) {
        if (navigator.mounted) {
          navigator.pop();
        }
      },
      (_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Couldn't save this change. Try again."),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folders = ref.watch(folderListProvider).valueOrNull ?? const [];
    Folder? folder;
    for (final candidate in folders) {
      if (candidate.id.value == folderId) {
        folder = candidate;
        break;
      }
    }
    if (folder == null) {
      // Archived (or gone) while the sheet was open: nothing to edit.
      return const SizedBox.shrink();
    }
    final live = folder;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.l,
            Space.xl,
            Space.l,
            Space.l,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                child: Text(live.name, style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: Space.m),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename'),
                onTap: () => showRenameFolderDialog(
                  context,
                  folderId: live.id.value,
                  currentName: live.name,
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xs,
                  Space.s,
                  Space.xs,
                  Space.xs,
                ),
                child: Text(
                  'Does how much you bring depend on how many people come?',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xs,
                  0,
                  Space.xs,
                  Space.m,
                ),
                child: Text(
                  'New items filed here start with this answer. Any single '
                  'item can differ.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              DemandBasisChoice(
                value: live.demandBasis,
                onChanged: (basis) =>
                    _setBasis(context, ref, demandBasis: basis),
              ),
              const SizedBox(height: Space.s),
              SwitchListTile(
                title: const Text('Comes along to every event'),
                subtitle: const Text(
                  "This folder's items are put on every new event's list "
                  'from the start.',
                ),
                value: live.alwaysPlanned,
                onChanged: (value) =>
                    _setBasis(context, ref, alwaysPlanned: value),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.archive_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Archive folder',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => _archive(context, ref, live),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
