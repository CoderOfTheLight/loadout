/// Planned-items picker, rebuilt to the design-spec §6 sheet: a full-height
/// (92%) modal with "Plan items" and the search pinned in its header;
/// folder sections with PINNED §4 headers — 24 dp folder chip, name, live
/// "3 of 12" fraction, and a labeled "Add all (9)" / "Remove all" bulk
/// action (never an icon-only "+", and the count states the consequence
/// before the tap); 56 dp checkbox rows whose selected state is checkbox +
/// folder-tint fill + name at w700 (never the checkbox alone at arm's
/// length); and the docked 72 dp running-tally bar — "12 items · 4 folders"
/// with a scale pulse on change, Done as a real button. Checking a row is
/// a quiet 150 ms tint change — no haptic: that budget belongs to the
/// closeout confirm and the one celebration, not to sixty planning taps.
///
/// Quantity-free on purpose — quantities stay the forecast's job. Returns
/// the new selection (existing order preserved, additions appended in
/// folder-section order), or null when dismissed.
///
/// With an empty catalog the sheet explains what to do and offers the way
/// to `/items/new` — a checklist with nothing on it is a dead end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/folder.dart';
import 'folder_sections.dart';

Future<List<String>?> showPlannedItemsPicker(
  BuildContext context, {
  required List<String> selected,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => PlannedItemsSheet(initialSelection: selected),
);

class PlannedItemsSheet extends ConsumerStatefulWidget {
  const PlannedItemsSheet({super.key, required this.initialSelection});

  final List<String> initialSelection;

  @override
  ConsumerState<PlannedItemsSheet> createState() => _PlannedItemsSheetState();
}

class _PlannedItemsSheetState extends ConsumerState<PlannedItemsSheet> {
  late final Set<String> _selected = {...widget.initialSelection};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Closes the sheet and opens the new-item form. The router is resolved
  /// BEFORE the pop: afterwards this context is defunct.
  void _addItem() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.push('/items/new');
  }

  /// Sections as displayed: search-filtered, empty ones dropped (a folder
  /// with nothing to tick is not a decision).
  List<FolderWithItems> _visibleSections(List<FolderWithItems> sections) {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final section in sections)
        if (_filterItems(section.items, query) case final items
            when items.isNotEmpty)
          FolderWithItems(folder: section.folder, items: items),
    ];
  }

  static List<ItemSummary> _filterItems(
    List<ItemSummary> items,
    String query,
  ) => query.isEmpty
      ? items
      : [
          for (final summary in items)
            if (summary.item.name.toLowerCase().contains(query)) summary,
        ];

  /// The selection in display order: the initial order is preserved,
  /// additions append in folder-section order (event_items.position follows
  /// list order, and the planned list sections itself the same way).
  List<String> _result(List<FolderWithItems> sections) {
    final kept = [
      for (final id in widget.initialSelection)
        if (_selected.contains(id)) id,
    ];
    final keptSet = kept.toSet();
    return [
      ...kept,
      for (final section in sections)
        for (final summary in section.items)
          if (_selected.contains(summary.item.id.value) &&
              !keptSet.contains(summary.item.id.value))
            summary.item.id.value,
    ];
  }

  /// How many folder sections the current selection spans (the tally bar's
  /// second number). Unfiled counts as one — it is a section on every list.
  int _foldersInSelection(List<FolderWithItems> sections) {
    var count = 0;
    for (final section in sections) {
      if (section.items.any(
        (summary) => _selected.contains(summary.item.id.value),
      )) {
        count += 1;
      }
    }
    return count;
  }

  void _toggle(String itemId) {
    setState(() {
      if (_selected.contains(itemId)) {
        _selected.remove(itemId);
      } else {
        // No haptic here, deliberately: planning-selection is not the §4
        // check-off moment. Ticking sixty items would mean sixty buzzes —
        // feedback spam, not feedback. The haptic budget belongs to the
        // closeout confirm and the one celebration.
        _selected.add(itemId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sectionsAsync = ref.watch(eventFoldersWithItemsProvider);
    return SafeArea(
      // 92% of the height: the old 75% wasted reach (spec §6).
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        child: sectionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Items could not be loaded.'),
          ),
          data: (sections) {
            if (sections.every((section) => section.items.isEmpty)) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Plan items', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Flexible(
                      child: EmptyState(
                        title: 'Nothing to plan yet',
                        message:
                            'Add what you will bring — its name and how '
                            'many you have — then pick it here.',
                        actionLabel: 'Add an item',
                        onAction: _addItem,
                      ),
                    ),
                  ],
                ),
              );
            }
            final visible = _visibleSections(sections);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Plan items', style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    height: 48,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search all items',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing matches your search.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : CustomScrollView(
                          slivers: [
                            for (final section in visible)
                              SliverMainAxisGroup(
                                slivers: [
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate: _PickerHeaderDelegate(
                                      folder: section.folder,
                                      itemIds: [
                                        for (final summary in section.items)
                                          summary.item.id.value,
                                      ],
                                      selected: _selected,
                                      onAddAll: _addAll,
                                      onRemoveAll: _removeAll,
                                    ),
                                  ),
                                  SliverList.builder(
                                    itemCount: section.items.length,
                                    itemBuilder: (context, index) {
                                      final summary = section.items[index];
                                      final id = summary.item.id.value;
                                      return _PickerRow(
                                        name: summary.item.name,
                                        folder: section.folder,
                                        selected: _selected.contains(id),
                                        onToggle: () => _toggle(id),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 16),
                            ),
                          ],
                        ),
                ),
                _TallyBar(
                  itemCount: _selected.length,
                  folderCount: _foldersInSelection(sections),
                  onDone: () => Navigator.of(context).pop(_result(sections)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _addAll(List<String> ids) => setState(() => _selected.addAll(ids));

  void _removeAll(List<String> ids) => setState(() => _selected.removeAll(ids));
}

/// Pinned §4 section header inside the sheet: 24 dp chip, folder name,
/// live "3 of 12" fraction, and the labeled bulk action with its count —
/// "Add all (9)" states the consequence before the tap; when the folder is
/// fully picked it flips to "Remove all" (both directions labeled, and undo
/// is the same button while the sheet stays open).
class _PickerHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PickerHeaderDelegate({
    required this.folder,
    required this.itemIds,
    required this.selected,
    required this.onAddAll,
    required this.onRemoveAll,
  });

  static const double _extent = 52;

  final Folder? folder;
  final List<String> itemIds;
  final Set<String> selected;
  final ValueChanged<List<String>> onAddAll;
  final ValueChanged<List<String>> onRemoveAll;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedCount = itemIds.where(selected.contains).length;
    final allSelected = selectedCount == itemIds.length;
    final remaining = itemIds.length - selectedCount;
    return Container(
      // Fill the sliver extent exactly — a shorter child breaks the pinned
      // header's geometry.
      height: _extent,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Row(
        children: [
          if (folder != null) ...[
            FolderChip.forFolder(folder!, size: FolderChipSize.small),
            const SizedBox(width: Space.s + 2),
          ],
          Expanded(
            child: Text(
              folder?.name ?? 'Unfiled',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Text(
            '$selectedCount of ${itemIds.length}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: Numerals.tabular,
            ),
          ),
          const SizedBox(width: Space.s),
          TextButton(
            onPressed: () =>
                allSelected ? onRemoveAll(itemIds) : onAddAll(itemIds),
            child: Text(allSelected ? 'Remove all' : 'Add all ($remaining)'),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_PickerHeaderDelegate oldDelegate) => true;
}

/// One 56 dp checkbox row. Selected = checkbox + folder-tint fill + name to
/// w700 — a checkbox alone is color-only at arm's length (spec §6). The
/// tint change is the §4 check-off moment's 150 ms `AnimatedContainer`.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.name,
    required this.folder,
    required this.selected,
    required this.onToggle,
  });

  final String name;
  final Folder? folder;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Unfiled rows use the scheme's own selected tint; folder rows carry
    // their folder's derived pair.
    final colors = folder == null
        ? null
        : FolderPalette.of(context).pair(folder!.effectiveHue);
    final tint = colors?.tint ?? scheme.secondaryContainer;
    final ink = colors?.ink ?? scheme.onSecondaryContainer;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 56),
          color: selected ? tint : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: Space.s),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Checkbox(value: selected, onChanged: (_) => onToggle()),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? ink : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The docked running tally (spec §6): 72 dp, `surfaceContainerLow`, top
/// hairline — "12 items · 4 folders" updating on every tap (the count does
/// a small scale pulse), Done as a real 56 dp button. The one sanctioned
/// bottom-bar container.
class _TallyBar extends StatelessWidget {
  const _TallyBar({
    required this.itemCount,
    required this.folderCount,
    required this.onDone,
  });

  final int itemCount;
  final int folderCount;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.l,
        vertical: Space.s,
      ),
      child: Row(
        children: [
          Expanded(
            child: _TallyPulse(
              trigger: itemCount,
              child: Text(
                '$itemCount item${itemCount == 1 ? '' : 's'} · '
                '$folderCount folder${folderCount == 1 ? '' : 's'}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: Numerals.tabular,
                ),
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(112, 56)),
            onPressed: onDone,
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

/// The §7 tally pulse: 1.0 → 1.08 → 1.0 over 180 ms total (up 80, back
/// 100), on the count's own change only — never autonomous, and skipped
/// entirely when animations are disabled.
class _TallyPulse extends StatefulWidget {
  const _TallyPulse({required this.trigger, required this.child});

  final Object trigger;
  final Widget child;

  @override
  State<_TallyPulse> createState() => _TallyPulseState();
}

class _TallyPulseState extends State<_TallyPulse> {
  bool _up = false;

  @override
  void didUpdateWidget(_TallyPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger &&
        !MediaQuery.disableAnimationsOf(context)) {
      setState(() => _up = true);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _up ? 1.08 : 1.0,
    alignment: Alignment.centerLeft,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: _up ? 80 : 100),
    curve: Curves.easeOut,
    onEnd: () {
      if (_up && mounted) {
        setState(() => _up = false);
      }
    },
    child: widget.child,
  );
}
