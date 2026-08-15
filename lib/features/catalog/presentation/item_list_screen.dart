/// `/items` — the catalog in the owner's packing order (folders proposal
/// §3): folder sections with pinned headers, not a flat alphabet.
///
/// * Sections come from `watchFoldersWithItems`: live folders in the
///   owner's order (empty ones included — she must see where things can
///   go), then "Unfiled" last whenever anything is unfiled, never hidden.
///   "Archived" renders after everything, only via the Show archived
///   toggle.
/// * Headers pin while their section scrolls (SliverMainAxisGroup +
///   SliverPersistentHeader — framework only), carry the item count in both
///   states, and tap to collapse. Collapse is remembered for the session
///   ([collapsedSectionsProvider]), not across restarts.
/// * The chip row jumps to a folder. Offsets are exact because every row is
///   a fixed-extent sliver child.
/// * Search stays on top and searches everything — every folder, Unfiled,
///   and Archived when shown — ignoring collapse, hiding sections with no
///   matches.
///
/// Read-only: no commands. Folder management is its own screen, reached
/// from the overflow menu.
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
import 'folder_management_screen.dart';

/// Section ids for the two non-folder sections. Folder ids are 26-char
/// ULIDs, so these can never collide.
const String unfiledSectionId = 'unfiled';
const String archivedSectionId = 'archived';

/// Fixed extents keep chip-jump arithmetic exact and scrolling cheap at
/// 150+ items: every header is 48 dp, every item row 72 dp.
const double _headerExtent = 48;
const double _itemExtent = 72;

final class _Section {
  const _Section({required this.id, required this.title, required this.items});

  final String id;
  final String title;
  final List<ItemSummary> items;
}

class ItemListScreen extends ConsumerStatefulWidget {
  const ItemListScreen({super.key});

  @override
  ConsumerState<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends ConsumerState<ItemListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _includeArchived = false;
  String _query = '';

  /// The sections currently on screen, in order — the jump chips read this.
  List<_Section> _visibleSections = const [];

  /// Const-canonicalized so the provider-family key stays identical across
  /// rebuilds (the filter type has no value equality).
  static const _archivedFilter = ItemFilter(includeArchived: true);

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggleSection(String id) {
    final notifier = ref.read(collapsedSectionsProvider.notifier);
    final current = notifier.state;
    notifier.state = current.contains(id)
        ? {
            for (final other in current)
              if (other != id) other,
          }
        : {...current, id};
  }

  /// Scrolls so [sectionId]'s header lands at the top. Exact, not
  /// estimated: headers and rows have fixed extents, and pinned headers
  /// stay inside their own group, so the sum below IS the offset.
  void _jumpToSection(String sectionId) {
    if (!_scroll.hasClients) {
      return;
    }
    final collapsed = ref.read(collapsedSectionsProvider);
    var offset = 0.0;
    for (final section in _visibleSections) {
      if (section.id == sectionId) {
        break;
      }
      offset += _headerExtent;
      if (!collapsed.contains(section.id)) {
        offset += section.items.length * _itemExtent;
      }
    }
    _scroll.animateTo(
      offset.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _openFolderManagement() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const FolderManagementScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectionsAsync = ref.watch(foldersWithItemsProvider);
    final archivedSummaries = _includeArchived
        ? ref.watch(itemListProvider(_archivedFilter)).valueOrNull ??
              const <ItemSummary>[]
        : const <ItemSummary>[];
    final collapsed = ref.watch(collapsedSectionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'archived':
                  setState(() => _includeArchived = !_includeArchived);
                case 'folders':
                  _openFolderManagement();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'archived',
                checked: _includeArchived,
                child: const Text('Show archived'),
              ),
              const PopupMenuItem(
                value: 'folders',
                child: Text('Manage folders'),
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
                  hintText: 'Search all items',
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.search),
                  ),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: (text) => setState(() => _query = text),
                ),
              ),
            ),
          ),
          Expanded(
            child: sectionsAsync.when(
              data: (folderSections) =>
                  _buildSections(folderSections, archivedSummaries, collapsed),
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

  Widget _buildSections(
    List<FolderWithItems> folderSections,
    List<ItemSummary> archivedSummaries,
    Set<String> collapsed,
  ) {
    final query = _query.trim().toLowerCase();
    final searching = query.isNotEmpty;
    final archivedItems = [
      for (final summary in archivedSummaries)
        if (summary.item.isArchived) summary,
    ];

    List<ItemSummary> matching(List<ItemSummary> items) => searching
        ? [
            for (final summary in items)
              if (summary.item.name.toLowerCase().contains(query)) summary,
          ]
        : items;

    final all = <_Section>[
      for (final section in folderSections)
        _Section(
          id: section.folder?.id.value ?? unfiledSectionId,
          title: section.folder?.name ?? 'Unfiled',
          items: matching(section.items),
        ),
      if (archivedItems.isNotEmpty)
        _Section(
          id: archivedSectionId,
          title: 'Archived',
          items: matching(archivedItems),
        ),
    ];

    final totalItems =
        archivedItems.length +
        folderSections.fold(0, (sum, section) => sum + section.items.length);
    if (totalItems == 0 && !searching) {
      _visibleSections = const [];
      // Unchanged from the pre-folders screen: an empty catalog explains
      // what an item is, folders or not.
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

    final visible = searching
        ? [
            for (final section in all)
              if (section.items.isNotEmpty) section,
          ]
        : all;
    _visibleSections = visible;
    if (visible.isEmpty) {
      return const EmptyState(
        message: 'No items match your search.',
        icon: Icons.search_off_outlined,
      );
    }

    return Column(
      children: [
        if (!searching)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final section in visible)
                  if (section.id != archivedSectionId)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(section.title),
                        onPressed: () => _jumpToSection(section.id),
                      ),
                    ),
              ],
            ),
          ),
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              for (final section in visible)
                SliverMainAxisGroup(
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SectionHeaderDelegate(
                        title: section.title,
                        count: section.items.length,
                        collapsed: !searching && collapsed.contains(section.id),
                        onTap: searching
                            ? null
                            : () => _toggleSection(section.id),
                      ),
                    ),
                    if (searching || !collapsed.contains(section.id))
                      SliverFixedExtentList(
                        itemExtent: _itemExtent,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Align(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: contentMaxWidth,
                              ),
                              child: _ItemTile(summary: section.items[index]),
                            ),
                          ),
                          childCount: section.items.length,
                        ),
                      ),
                  ],
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pinned section header: name + count in both states, tap to collapse.
/// Fixed 48 dp so jump offsets stay exact.
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({
    required this.title,
    required this.count,
    required this.collapsed,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  double get minExtent => _headerExtent;

  @override
  double get maxExtent => _headerExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          header: true,
          button: onTap != null,
          label:
              '$title, $count item${count == 1 ? '' : 's'}'
              '${collapsed ? ', collapsed' : ''}',
          excludeSemantics: true,
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Row(
                    children: [
                      Icon(
                        collapsed ? Icons.chevron_right : Icons.expand_more,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '$count',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.count != count ||
      oldDelegate.collapsed != collapsed ||
      (oldDelegate.onTap == null) != (onTap == null);
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
      if (item.perPersonRatio != null)
        perPersonRatioPhrase(item.perPersonRatio!),
      if (item.perEventBaseline != null)
        'Usually bring ${formatMicros(item.perEventBaseline!.micros)}',
      if (item.isArchived) 'Archived',
    ].join(' · ');
    return ListTile(
      minTileHeight: 56,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
