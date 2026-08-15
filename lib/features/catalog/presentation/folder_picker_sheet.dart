/// The item form's folder picker (folders proposal §3): the owner's folders
/// in her order, "Unfiled" after them, and "New folder…" at the bottom —
/// creating through the command path and filing straight into the result.
///
/// A pick-list, never free text: typed folder names are how "Drinks",
/// "drinks" and "Beverages" become three folders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/folder_chip.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'folder_dialogs.dart';

/// A resolved pick. Wrapped so "picked Unfiled" ([folderId] null) is
/// distinguishable from "cancelled" (the sheet resolving to null).
final class FolderPick {
  const FolderPick(this.folderId);

  /// Null = Unfiled.
  final String? folderId;
}

/// Opens the picker over the owner's live folders. Resolves to a
/// [FolderPick], or null when dismissed without choosing.
Future<FolderPick?> showFolderPickerSheet(
  BuildContext context, {
  String? selectedFolderId,
}) => showModalBottomSheet<FolderPick>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _FolderPickerSheet(selectedFolderId: selectedFolderId),
);

class _FolderPickerSheet extends ConsumerWidget {
  const _FolderPickerSheet({this.selectedFolderId});

  final String? selectedFolderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folders = ref.watch(folderListProvider).valueOrNull ?? const [];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.xl,
                Space.xl,
                Space.s,
              ),
              child: Text('Choose a folder', style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: Space.s),
                children: [
                  for (final folder in folders)
                    ListTile(
                      leading: FolderChip.forFolder(folder),
                      title: Text(folder.name),
                      subtitle: Text(demandBasisLabel(folder.demandBasis)),
                      trailing: folder.id.value == selectedFolderId
                          ? const Icon(Icons.check)
                          : null,
                      selected: folder.id.value == selectedFolderId,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(FolderPick(folder.id.value)),
                    ),
                  ListTile(
                    leading: const Icon(Icons.inbox_outlined),
                    title: const Text('Unfiled'),
                    subtitle: const Text(
                      'No folder — shown at the end of every list.',
                    ),
                    trailing: selectedFolderId == null
                        ? const Icon(Icons.check)
                        : null,
                    selected: selectedFolderId == null,
                    onTap: () =>
                        Navigator.of(context).pop(const FolderPick(null)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: const Text('New folder…'),
                    onTap: () async {
                      final navigator = Navigator.of(context);
                      final createdId = await showCreateFolderDialog(context);
                      if (createdId != null) {
                        navigator.pop(FolderPick(createdId));
                      }
                    },
                  ),
                  const SizedBox(height: Space.s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
