/// Planned-items picker, rebuilt as a full-height sheet (proposal §3):
/// search pinned at the top and searching everything regardless of folders;
/// folder sections, each header carrying its running count and an "Add all"
/// ("Cleaning & setup · 0 of 9 · Add all"); a running tally pinned at the
/// bottom ("23 items picked · Done"). Sixty items across six folders is six
/// decisions plus a handful of exceptions.
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
import '../../catalog/application/catalog_service.dart';
import 'folder_sections.dart';

Future<List<String>?> showPlannedItemsPicker(
  BuildContext context, {
  required List<String> selected,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
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

  Widget _sectionHeader(ThemeData theme, FolderWithItems section) {
    final ids = [for (final summary in section.items) summary.item.id.value];
    final selectedCount = ids.where(_selected.contains).length;
    final allSelected = selectedCount == ids.length;
    final name = section.folder?.name ?? 'Unfiled';
    return Row(
      children: [
        Expanded(
          child: Text(
            '$name · $selectedCount of ${ids.length}',
            style: theme.textTheme.titleSmall,
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            if (allSelected) {
              _selected.removeAll(ids);
            } else {
              _selected.addAll(ids);
            }
          }),
          child: Text(allSelected ? 'Remove all' : 'Add all'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sectionsAsync = ref.watch(eventFoldersWithItemsProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: sectionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Items could not be loaded.'),
            ),
            data: (sections) {
              if (sections.every((section) => section.items.isEmpty)) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Planned items', style: theme.textTheme.titleMedium),
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
                );
              }
              final visible = _visibleSections(sections);
              final tally = _selected.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Planned items', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search all items',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Text(
                              'Nothing matches your search.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          )
                        : ListView(
                            children: [
                              for (final section in visible) ...[
                                _sectionHeader(theme, section),
                                for (final summary in section.items)
                                  CheckboxListTile(
                                    dense: true,
                                    value: _selected.contains(
                                      summary.item.id.value,
                                    ),
                                    title: Text(summary.item.name),
                                    onChanged: (checked) => setState(() {
                                      final id = summary.item.id.value;
                                      if (checked ?? false) {
                                        _selected.add(id);
                                      } else {
                                        _selected.remove(id);
                                      }
                                    }),
                                  ),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                    ),
                    onPressed: () =>
                        Navigator.of(context).pop(_result(sections)),
                    child: Text(
                      '$tally item${tally == 1 ? '' : 's'} picked · Done',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
