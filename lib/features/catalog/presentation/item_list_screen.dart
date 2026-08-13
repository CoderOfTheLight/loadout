/// `/items` (design §9 ItemListScreen): catalog + on-hand at a glance.
///
/// Search bar, group `FilterChip` row from `categorySuggestions`, tiles
/// showing how many you have (negatives shown signed with a warning icon
/// and label, never clamped) over an optional group / "one serves N"
/// caption, archived toggle in the overflow menu, FAB → `/items/new`.
/// Read-only: no commands.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../application/catalog_service.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';

class ItemListScreen extends ConsumerStatefulWidget {
  const ItemListScreen({super.key});

  @override
  ConsumerState<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends ConsumerState<ItemListScreen> {
  final _search = TextEditingController();
  String? _category;
  bool _includeArchived = false;

  /// Kept in state so the [itemListProvider] family key stays identical
  /// across rebuilds (the filter type has no value equality).
  ItemFilter _filter = const ItemFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _updateFilter() {
    final search = _search.text.trim();
    setState(() {
      _filter = ItemFilter(
        search: search.isEmpty ? null : search,
        category: _category,
        includeArchived: _includeArchived,
      );
    });
  }

  bool get _isFiltered => _filter.search != null || _filter.category != null;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemListProvider(_filter));
    final categories =
        ref.watch(categorySuggestionsProvider).valueOrNull ?? const <String>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'archived') {
                _includeArchived = !_includeArchived;
                _updateFilter();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'archived',
                checked: _includeArchived,
                child: const Text('Show archived'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Shell branches stay mounted together, so every FAB needs its own
        // hero tag.
        heroTag: 'fab-items',
        tooltip: 'Add item',
        onPressed: () => context.push('/items/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: contentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  controller: _search,
                  hintText: 'Search items',
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.search),
                  ),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: (_) => _updateFilter(),
                ),
              ),
            ),
          ),
          if (categories.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (selected) {
                          _category = selected ? category : null;
                          _updateFilter();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: itemsAsync.when(
              data: _buildList,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const EmptyState(
                message: "Items couldn't be loaded.",
                icon: Icons.error_outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<ItemSummary> summaries) {
    if (summaries.isEmpty) {
      if (_isFiltered) {
        return const EmptyState(
          message: 'No items match your search.',
          icon: Icons.search_off_outlined,
        );
      }
      return EmptyState(
        title: 'Nothing in your list yet',
        message:
            'Items are the things you bring and sell — burgers, buns, cups. '
            'Add one with its name and how many you have, and Loadout keeps '
            'count from there.',
        actionLabel: 'Add your first item',
        onAction: () => context.push('/items/new'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: summaries.length,
      itemBuilder: (context, index) => Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: _ItemTile(summary: summaries[index]),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.summary});

  final ItemSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = summary.item;
    final onHandText = formatCount(summary.onHandMicros, item.unit);
    final subtitle = [
      if (item.category != null) item.category!,
      if (item.servesPerUnit != null)
        'One serves ${formatMicros(item.servesPerUnit!.micros)}',
      if (item.isArchived) 'Archived',
    ].join(' · ');
    return ListTile(
      minTileHeight: 56,
      title: Text(item.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Semantics(
        label:
            'You have $onHandText'
            '${summary.isNegative ? ', negative' : ''}',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (summary.isNegative) ...[
              Icon(Icons.warning_amber_outlined, color: scheme.error),
              const SizedBox(width: 6),
            ],
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  onHandText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: summary.isNegative ? scheme.error : null,
                  ),
                ),
                if (summary.isNegative)
                  Text(
                    'Negative',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: scheme.error),
                  ),
              ],
            ),
          ],
        ),
      ),
      onTap: () => context.push('/items/${item.id.value}'),
    );
  }
}
