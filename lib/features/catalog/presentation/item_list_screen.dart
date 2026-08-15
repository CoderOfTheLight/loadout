/// `/items` — the catalog in the owner's packing order (folders proposal
/// §3): folder sections with pinned headers, not a flat alphabet.
///
/// * Sections come from `watchFoldersWithItems`: live folders in the
///   owner's order (empty ones included — she must see where things can
///   go), then "Unfiled" last whenever anything is unfiled, never hidden.
///   "Archived" renders after everything, only via the Show archived
///   toggle.
/// * Rows follow the design-spec §4 anatomy: a 40 dp [FolderChip] leading,
///   the name in `bodyLarge` w600, the count right-aligned in the tabular
///   `titleLarge` row-quantity role. Data rows stay monochrome and
///   motionless — the chip is the only color.
/// * Headers pin while their section scrolls (SliverMainAxisGroup +
///   SliverPersistentHeader — framework only): 24 dp chip, name, count,
///   chevron (`AnimatedRotation`), on opaque `surfaceContainerLow` with a
///   hairline so the pin edge reads in sunlight. Tap to collapse; collapse
///   is remembered for the session ([collapsedSectionsProvider]).
/// * Search and the jump-to-folder chips live in a floating header
///   (`SliverFloatingHeader`): gone scrolling down, back on the first
///   upward flick — mid-scroll pinned chrome is the 52 dp section header
///   alone (spec §4 pinned-chrome budget).
/// * The jump row is the food-delivery-menu pattern: a color dot + name +
///   count per chip, tap scrolls to the section (offsets are exact because
///   every row is a fixed-extent sliver child), and the active chip tracks
///   the scroll position.
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
import '../../../app/widgets/folder_chip.dart';
import '../application/catalog_service.dart';
import '../domain/folder.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'folder_management_screen.dart';

/// Section ids for the two non-folder sections. Folder ids are 26-char
/// ULIDs, so these can never collide.
const String unfiledSectionId = 'unfiled';
const String archivedSectionId = 'archived';

/// The horizontal jump-to-folder row, for tests and tooling.
const Key itemListJumpRowKey = Key('folder-jump-row');

/// Fixed extents keep chip-jump arithmetic exact and scrolling cheap at
/// 150+ items: every header is 52 dp (spec §4), every item row 72 dp.
const double _headerExtent = 52;
const double _itemExtent = 72;

final class _Section {
  const _Section({
    required this.id,
    required this.title,
    required this.items,
    this.folder,
  });

  final String id;
  final String title;
  final List<ItemSummary> items;

  /// Null for the Unfiled and Archived sections — no identity chip there.
  final Folder? folder;
}

class ItemListScreen extends ConsumerStatefulWidget {
  const ItemListScreen({super.key});

  @override
  ConsumerState<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends ConsumerState<ItemListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _floatingHeaderKey = GlobalKey();
  final Map<String, GlobalKey> _chipKeys = {};
  bool _includeArchived = false;
  String _query = '';

  /// The section the scroll position currently sits in — the jump row's
  /// highlighted chip. Null until the list first scrolls or jumps.
  String? _activeSectionId;

  /// The sections currently on screen, in order — the jump chips read this.
  List<_Section> _visibleSections = const [];

  /// Const-canonicalized so the provider-family key stays identical across
  /// rebuilds (the filter type has no value equality).
  static const _archivedFilter = ItemFilter(includeArchived: true);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackActiveSection);
  }

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

  /// The floating search+chips header's current height — part of the exact
  /// jump offset. Zero before the first layout.
  double get _floatingHeaderHeight =>
      _floatingHeaderKey.currentContext?.size?.height ?? 0;

  /// The exact scroll offset where [section]'s header rests, given the
  /// fixed extents and the collapse state.
  double _sectionOffset(String sectionId, Set<String> collapsed) {
    var offset = _floatingHeaderHeight;
    for (final section in _visibleSections) {
      if (section.id == sectionId) {
        break;
      }
      offset += _headerExtent;
      if (!collapsed.contains(section.id)) {
        offset += section.items.length * _itemExtent;
      }
    }
    return offset;
  }

  /// Scrolls so [sectionId]'s header lands at the top. Exact, not
  /// estimated: headers and rows have fixed extents, and pinned headers
  /// stay inside their own group, so the sum below IS the offset.
  void _jumpToSection(String sectionId) {
    if (!_scroll.hasClients) {
      return;
    }
    final collapsed = ref.read(collapsedSectionsProvider);
    setState(() => _activeSectionId = sectionId);
    _scroll.animateTo(
      _sectionOffset(
        sectionId,
        collapsed,
      ).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Keeps the highlighted jump chip in step with the scroll position
  /// (spec §4: the active chip tracks scroll and scrolls itself into view).
  void _trackActiveSection() {
    if (!_scroll.hasClients || _visibleSections.isEmpty) {
      return;
    }
    final collapsed = ref.read(collapsedSectionsProvider);
    final position = _scroll.offset + 1;
    String active = _visibleSections.first.id;
    for (final section in _visibleSections) {
      if (_sectionOffset(section.id, collapsed) <= position) {
        active = section.id;
      } else {
        break;
      }
    }
    if (active == _activeSectionId) {
      return;
    }
    final wasTracking = _activeSectionId != null;
    setState(() => _activeSectionId = active);
    // Auto-scroll the active chip into view only once tracking is already
    // under way: the first activation (list barely moved) must not yank a
    // hand-scrolled chip row back to the start.
    if (!wasTracking) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[active]?.currentContext;
      final renderObject = chipContext?.findRenderObject();
      if (chipContext == null || renderObject == null || !mounted) {
        return;
      }
      // ONLY the horizontal chip row scrolls — Scrollable.ensureVisible
      // would climb into the vertical list too and fight the user's scroll.
      Scrollable.of(chipContext).position.ensureVisible(
        renderObject,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
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
      // Words on every FAB (spec §2: no icon-only actions).
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay mounted together, so every FAB needs its own
        // hero tag.
        heroTag: 'fab-items',
        onPressed: () => context.push('/items/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: sectionsAsync.when(
        data: (folderSections) =>
            _buildSections(folderSections, archivedSummaries, collapsed),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          message: "Items couldn't be loaded.",
          icon: Icons.error_outline,
        ),
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
          folder: section.folder,
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
    _chipKeys.removeWhere(
      (id, _) => !visible.any((section) => section.id == id),
    );
    for (final section in visible) {
      _chipKeys.putIfAbsent(section.id, GlobalKey.new);
    }

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        // Search + jump chips float: gone scrolling down, back on the
        // first upward flick (spec §4 pinned-chrome budget — mid-scroll
        // pinned chrome is the section header alone).
        SliverFloatingHeader(child: _floatingHeader(searching)),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              message: 'No items match your search.',
              icon: Icons.search_off_outlined,
            ),
          )
        else ...[
          for (final section in visible)
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SectionHeaderDelegate(
                    title: section.title,
                    folder: section.folder,
                    count: section.items.length,
                    collapsed: !searching && collapsed.contains(section.id),
                    onTap: searching ? null : () => _toggleSection(section.id),
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
                          child: _ItemTile(
                            summary: section.items[index],
                            folder: section.folder,
                          ),
                        ),
                      ),
                      childCount: section.items.length,
                    ),
                  ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ],
    );
  }

  /// The floating search + jump-chips region. Opaque on `surface` so it
  /// never ghosts over rows while snapping back in.
  Widget _floatingHeader(bool searching) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: _floatingHeaderKey,
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          if (!searching)
            SizedBox(
              height: 48,
              child: SingleChildScrollView(
                key: itemListJumpRowKey,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final section in _visibleSections)
                      if (section.id != archivedSectionId)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _JumpChip(
                            key: _chipKeys[section.id],
                            title: section.title,
                            count: section.items.length,
                            folder: section.folder,
                            active: section.id == _activeSectionId,
                            onTap: () => _jumpToSection(section.id),
                          ),
                        ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One jump-to-folder chip (spec §4): 8 dp color dot, name, count. The
/// active chip fills with the folder tint and inks its text; identity is
/// never the dot alone — the name is always beside it.
class _JumpChip extends StatelessWidget {
  const _JumpChip({
    super.key,
    required this.title,
    required this.count,
    required this.folder,
    required this.active,
    required this.onTap,
  });

  final String title;
  final int count;
  final Folder? folder;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = folder == null
        ? null
        : FolderPalette.of(context).pair(folder!.effectiveHue);
    final dotColor = folder == null
        ? scheme.outline
        : folderHueSeeds[folder!.effectiveHue]!;
    final fill = active
        ? (colors?.tint ?? scheme.surfaceContainerHigh)
        : Colors.transparent;
    final ink = active ? (colors?.ink ?? scheme.onSurface) : scheme.onSurface;
    return Semantics(
      button: true,
      selected: active,
      label: 'Jump to $title, $count item${count == 1 ? '' : 's'}',
      child: ExcludeSemantics(
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.small),
            side: active
                ? BorderSide.none
                : BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.small),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(color: ink),
                  ),
                  const SizedBox(width: Space.xs + 2),
                  Text(
                    '$count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: active ? ink : scheme.onSurfaceVariant,
                      fontFeatures: Numerals.tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned section header (spec §4): 24 dp chip, name, count, chevron, on
/// opaque `surfaceContainerLow` with a bottom hairline. Whole row tappable
/// to collapse/expand. Fixed 52 dp so jump offsets stay exact.
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({
    required this.title,
    required this.folder,
    required this.count,
    required this.collapsed,
    required this.onTap,
  });

  final String title;
  final Folder? folder;
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
      color: scheme.surfaceContainerLow,
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
                      if (folder != null) ...[
                        FolderChip.forFolder(
                          folder!,
                          size: FolderChipSize.small,
                        ),
                        const SizedBox(width: Space.s + 2),
                      ],
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
                          fontFeatures: Numerals.tabular,
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: Space.s),
                        AnimatedRotation(
                          turns: collapsed ? -0.25 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.expand_more,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
      oldDelegate.folder != folder ||
      (oldDelegate.onTap == null) != (onTap == null);
}

/// One item row (spec §4): 40 dp folder chip, name, caption, and the count
/// in the tabular `titleLarge` row-quantity role — 16 pt numerals fail the
/// arm's-length glance. Monochrome and motionless beyond the chip.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.summary, required this.folder});

  final ItemSummary summary;
  final Folder? folder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
      leading: folder == null ? null : FolderChip.forFolder(folder!),
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
                  style: Numerals.rowQuantity(
                    theme.textTheme,
                  )?.copyWith(color: summary.isNegative ? scheme.error : null),
                ),
                if (summary.isNegative)
                  Text(
                    'Negative',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
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
