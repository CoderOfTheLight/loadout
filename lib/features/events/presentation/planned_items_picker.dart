/// Planned-items multi-select bottom sheet (design §9 EventEditScreen:
/// "planned items (multi-select bottom sheet over catalog, chips inline)").
/// Reads the LIVE catalog via [itemListProvider]; returns the new selection
/// (existing order preserved, additions appended in catalog order), or null
/// when dismissed.
///
/// With an empty catalog the sheet explains what to do and offers the way
/// to `/items/new` — a checklist with nothing on it is a dead end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../catalog/application/catalog_service.dart';

Future<List<String>?> showPlannedItemsPicker(
  BuildContext context, {
  required List<String> selected,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
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

  /// Closes the sheet and opens the new-item form. The router is resolved
  /// BEFORE the pop: afterwards this context is defunct.
  void _addItem() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.push('/items/new');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(itemListProvider(const ItemFilter()));
    final catalogIsEmpty = items.valueOrNull?.isEmpty ?? false;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Planned items', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Flexible(
                child: items.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Items could not be loaded.'),
                  ),
                  data: (summaries) => summaries.isEmpty
                      ? EmptyState(
                          title: 'Nothing to plan yet',
                          message:
                              'Add what you will bring — its name and how '
                              'many you have — then pick it here.',
                          actionLabel: 'Add an item',
                          onAction: _addItem,
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final summary in summaries)
                              CheckboxListTile(
                                value: _selected.contains(
                                  summary.item.id as String,
                                ),
                                title: Text(summary.item.name),
                                subtitle: summary.item.category == null
                                    ? null
                                    : Text(summary.item.category!),
                                onChanged: (checked) => setState(() {
                                  final id = summary.item.id as String;
                                  if (checked ?? false) {
                                    _selected.add(id);
                                  } else {
                                    _selected.remove(id);
                                  }
                                }),
                              ),
                          ],
                        ),
                ),
              ),
              if (!catalogIsEmpty) ...[
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: primaryButtonMinSize,
                  ),
                  onPressed: () {
                    // Preserve the existing order; append additions in
                    // catalog order (event_items.position follows list
                    // order).
                    final kept = [
                      for (final id in widget.initialSelection)
                        if (_selected.contains(id)) id,
                    ];
                    final added = [
                      for (final summary
                          in items.valueOrNull ?? const <ItemSummary>[])
                        if (_selected.contains(summary.item.id as String) &&
                            !kept.contains(summary.item.id as String))
                          summary.item.id as String,
                    ];
                    Navigator.of(context).pop([...kept, ...added]);
                  },
                  child: const Text('Done'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
