/// Feature-local catalog projections (design §9.1: feature files may add
/// their own providers over the shared application services).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../application/catalog_service.dart';

/// `DISTINCT` live categories via [CatalogService.categorySuggestions]
/// (§12.8: free-text categories, no managed list). Watches the catalog
/// stream so the suggestions refetch whenever items change.
final categorySuggestionsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) {
  ref.watch(itemListProvider(const ItemFilter(includeArchived: true)));
  return ref.watch(catalogServiceProvider).categorySuggestions();
});

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
