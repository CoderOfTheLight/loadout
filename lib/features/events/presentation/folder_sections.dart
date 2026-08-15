/// Folder sectioning shared by the events + closeout screens (proposal §3):
/// every event-scoped list reads in the owner's folder order with a header
/// per folder ("Disposables · 12"), Unfiled last, never hidden. A workspace
/// with no folders at all (migrated, tidy-up not run yet) renders flat —
/// exactly as it always did, so upgrade day changes no screen uninvited.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/folder.dart';

/// Live folders in the owner's order (position ascending).
final eventFoldersProvider = StreamProvider.autoDispose<List<Folder>>(
  (ref) => ref.watch(catalogServiceProvider).watchFolders(),
);

/// The sectioned live catalog (folders in order, Unfiled last) behind the
/// planned-items picker and the always-planned preview.
final eventFoldersWithItemsProvider =
    StreamProvider.autoDispose<List<FolderWithItems>>(
      (ref) => ref.watch(catalogServiceProvider).watchFoldersWithItems(),
    );

/// One rendered section of an event-scoped list. [folder] is null for the
/// Unfiled section — and for every entry while no folders exist at all.
final class FolderSection<T> {
  const FolderSection({this.folder, required this.entries});

  final Folder? folder;
  final List<T> entries;
}

/// Groups [entries] into sections in folder order, Unfiled last. Entry order
/// within a section is preserved from [entries]; an entry whose folder is
/// unknown here (archived, or the item itself is gone from the catalog)
/// falls into Unfiled rather than vanishing. Only occupied sections return.
List<FolderSection<T>> sectionEntriesByFolder<T>({
  required List<T> entries,
  required List<Folder> folders,
  required String? Function(T entry) folderIdOf,
}) {
  final live = {for (final folder in folders) folder.id.value};
  final byFolder = <String?, List<T>>{};
  for (final entry in entries) {
    final folderId = folderIdOf(entry);
    byFolder
        .putIfAbsent(live.contains(folderId) ? folderId : null, () => [])
        .add(entry);
  }
  return [
    for (final folder in folders)
      if (byFolder[folder.id.value] case final sectionEntries?)
        FolderSection(folder: folder, entries: sectionEntries),
    if (byFolder[null] case final unfiled?)
      FolderSection(folder: null, entries: unfiled),
  ];
}

/// The section header every folder-ordered list shows: "Disposables · 12".
String folderSectionLabel(Folder? folder, int count) =>
    '${folder?.name ?? 'Unfiled'} · $count';
