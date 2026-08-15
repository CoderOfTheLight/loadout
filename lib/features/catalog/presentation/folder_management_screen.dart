/// Folder management (folders proposal §2, design-spec §3): the short
/// managed list every screen sections by. Rename, add, drag into the
/// packing order, archive, set the folder's default answer to the one
/// question, mark a folder as coming along to every event — and choose the
/// folder's identity: one of eight named hues and one curated icon, shown
/// as the same tinted chip everywhere the folder appears.
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
import '../../../app/widgets/folder_chip.dart';
import '../../../core/folder_appearance.dart';
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
    final theme = Theme.of(context);
    final foldersAsync = ref.watch(folderListProvider);
    final counts = {
      for (final section
          in ref.watch(foldersWithItemsProvider).valueOrNull ??
              const <FolderWithItems>[])
        if (section.folder != null)
          section.folder!.id.value: section.items.length,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      // Words on every FAB (spec §2: no icon-only actions).
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-folders',
        onPressed: () => showCreateFolderDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New folder'),
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: folders.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          _reorder(context, ref, folders, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        final count = counts[folder.id.value] ?? 0;
                        // Spec §3 row: 40 dp chip, name, count right-aligned,
                        // drag handle. 64 dp tall.
                        return ListTile(
                          key: ValueKey(folder.id.value),
                          minTileHeight: 64,
                          leading: FolderChip.forFolder(folder),
                          title: Text(folder.name),
                          subtitle: Text(
                            [
                              demandBasisLabel(folder.demandBasis),
                              if (folder.alwaysPlanned)
                                'Comes along to every event',
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                label: '$count item${count == 1 ? '' : 's'}',
                                excludeSemantics: true,
                                child: Text(
                                  '$count',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFeatures: Numerals.tabular,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Space.m),
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_indicator,
                                  semanticLabel: 'Reorder ${folder.name}',
                                ),
                              ),
                            ],
                          ),
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

/// The per-folder editor (design-spec §3): live chip preview at the top,
/// the eight swatches in a row, the curated icon grid, then rename, the
/// folder's default answer, the comes-along flag, and archive. Watches the
/// folder stream so every control shows what the workspace now says, and
/// every change is an immediate service write — no local draft to lose.
class _FolderEditorSheet extends ConsumerWidget {
  const _FolderEditorSheet({required this.folderId});

  final String folderId;

  void _writeFailed(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't save this change. Try again.")),
    );
  }

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
      _writeFailed(context);
    }
  }

  Future<void> _setAppearance(
    BuildContext context,
    WidgetRef ref, {
    FolderHue? hue,
    String? iconName,
  }) async {
    final result = await ref
        .read(catalogServiceProvider)
        .setFolderAppearance(folderId: folderId, hue: hue, iconName: iconName);
    if (result case Err() when context.mounted) {
      _writeFailed(context);
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
              // Live preview: the exact chip every list will show.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                child: Row(
                  children: [
                    FolderChip.forFolder(live),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Text(live.name, style: theme.textTheme.titleLarge),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.l),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                child: Text('COLOR', style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: Space.s),
              _HueSwatchRow(
                selected: live.effectiveHue,
                onSelect: (hue) => _setAppearance(context, ref, hue: hue),
              ),
              const SizedBox(height: Space.l),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                child: Text('ICON', style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: Space.s),
              _IconGrid(
                hue: live.effectiveHue,
                selectedIconName: live.effectiveIconName,
                onSelect: (name) =>
                    _setAppearance(context, ref, iconName: name),
              ),
              const SizedBox(height: Space.s),
              const Divider(),
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

/// The eight named hues as 44 dp swatches in one row (spec §3). Selected =
/// a check drawn in the swatch's own ink — never color alone. Not a free
/// color picker: eight derivation-safe hues or the palette stops being a
/// system.
class _HueSwatchRow extends StatelessWidget {
  const _HueSwatchRow({required this.selected, required this.onSelect});

  final FolderHue selected;
  final ValueChanged<FolderHue> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = FolderPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final hue in FolderHue.values)
            Padding(
              padding: const EdgeInsets.only(right: Space.s),
              child: Semantics(
                key: ValueKey('hue-${hue.dbValue}'),
                button: true,
                selected: hue == selected,
                label: hue.displayName,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => onSelect(hue),
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: palette.pair(hue).tint,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: hue == selected
                                  ? palette.pair(hue).ink
                                  : scheme.outlineVariant,
                              width: hue == selected ? 2 : 1,
                            ),
                          ),
                          child: hue == selected
                              ? Icon(
                                  Icons.check,
                                  size: 22,
                                  color: palette.pair(hue).ink,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The curated icon grid (spec §3): 48 dp cells, six per row, recognition
/// over choice. The selected cell fills with the chosen hue's tint.
class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.hue,
    required this.selectedIconName,
    required this.onSelect,
  });

  final FolderHue hue;
  final String selectedIconName;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = FolderPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = palette.pair(hue);
    return GridView.count(
      crossAxisCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Space.xs,
      crossAxisSpacing: Space.xs,
      children: [
        for (final choice in folderIconChoices)
          Semantics(
            key: ValueKey('icon-${choice.name}'),
            button: true,
            selected: choice.name == selectedIconName,
            label: choice.name.replaceAll('_', ' '),
            child: ExcludeSemantics(
              child: InkWell(
                onTap: () => onSelect(choice.name),
                borderRadius: BorderRadius.circular(Radii.small),
                child: Container(
                  decoration: BoxDecoration(
                    color: choice.name == selectedIconName ? colors.tint : null,
                    borderRadius: BorderRadius.circular(Radii.small),
                  ),
                  child: Icon(
                    choice.icon,
                    size: 24,
                    color: choice.name == selectedIconName
                        ? colors.ink
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
