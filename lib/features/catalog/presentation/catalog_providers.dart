/// Feature-local catalog projections (design §9.1: feature files may add
/// their own providers over the shared application services).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../application/catalog_service.dart';
import '../domain/folder.dart';

/// `DISTINCT` live categories via [CatalogService.categorySuggestions]
/// (§12.8: free-text categories, no managed list). Watches the catalog
/// stream so the suggestions refetch whenever items change.
final categorySuggestionsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) {
  ref.watch(itemListProvider(const ItemFilter(includeArchived: true)));
  return ref.watch(catalogServiceProvider).categorySuggestions();
});

/// Live folders in the owner's order — the folder picker and the management
/// screen read this.
final folderListProvider = StreamProvider.autoDispose<List<Folder>>(
  (ref) => ref.watch(catalogServiceProvider).watchFolders(),
);

/// The sectioned catalog: live folders in the owner's order, each with its
/// live items, then Unfiled (only when occupied — unfiled items are never
/// hidden). Empty folders are included so the owner sees where things can
/// go.
final foldersWithItemsProvider =
    StreamProvider.autoDispose<List<FolderWithItems>>(
      (ref) => ref.watch(catalogServiceProvider).watchFoldersWithItems(),
    );

/// Which item-list sections are collapsed, by section id (a folder id, or
/// the `unfiled` / `archived` sentinels). Deliberately NOT autoDispose:
/// collapse is remembered for the session — leaving the list and coming
/// back keeps it — and forgotten on restart.
final collapsedSectionsProvider = StateProvider<Set<String>>(
  (_) => const <String>{},
);

/// Lowercased live item name → item id, for the ItemEditScreen's live
/// unique-among-live check (§9: the partial index `uidx_items_name_live`
/// stays authoritative; this is the instant inline mirror of it).
final liveItemNameIndexProvider = Provider.autoDispose<Map<String, String>>((
  ref,
) {
  final summaries =
      ref.watch(itemListProvider(const ItemFilter())).valueOrNull ??
      const <ItemSummary>[];
  return {
    for (final summary in summaries)
      summary.item.name.trim().toLowerCase(): summary.item.id.value,
  };
});
