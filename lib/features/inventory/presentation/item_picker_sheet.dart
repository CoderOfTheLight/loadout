/// Searchable item picker bottom sheet (design §9 MovementEntryScreen:
/// "item picker (searchable sheet, how many you have inline)"). Returns the
/// chosen [ItemSummary], or null when dismissed.
///
/// An empty catalog is never presented as an empty list: the sheet explains
/// what an item is and offers the way to add one, because a picker with
/// nothing in it is a dead end, not an answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../catalog/application/catalog_service.dart';
import 'movement_display.dart';

Future<ItemSummary?> showItemPickerSheet(BuildContext context) =>
    showModalBottomSheet<ItemSummary>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ItemPickerSheet(),
    );

/// Closes [context]'s sheet and opens the new-item form. The router is
/// resolved BEFORE the pop: afterwards this context is defunct.
void _closeSheetAndAddItem(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  Navigator.of(context).pop();
  router?.push('/items/new');
}

class _ItemPickerSheet extends ConsumerStatefulWidget {
  const _ItemPickerSheet();

  @override
  ConsumerState<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends ConsumerState<_ItemPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemListProvider(const ItemFilter()));
    final catalogIsEmpty = items.valueOrNull?.isEmpty ?? false;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!catalogIsEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search items',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (text) =>
                      setState(() => _query = text.trim().toLowerCase()),
                ),
              ),
            Expanded(
              child: items.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    const Center(child: Text("Couldn't load items.")),
                data: (all) {
                  if (all.isEmpty) {
                    return EmptyState(
                      title: 'No items yet',
                      message:
                          'Add the thing you bought or used — its name and '
                          'how many — and it will be here.',
                      actionLabel: 'Add an item',
                      onAction: () => _closeSheetAndAddItem(context),
                    );
                  }
                  final matches = [
                    for (final summary in all)
                      if (_query.isEmpty ||
                          summary.item.name.toLowerCase().contains(_query))
                        summary,
                  ];
                  if (matches.isEmpty) {
                    return const Center(child: Text('No matching items.'));
                  }
                  return ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final summary = matches[index];
                      return ListTile(
                        minTileHeight: 56,
                        title: Text(summary.item.name),
                        subtitle: summary.item.category == null
                            ? null
                            : Text(summary.item.category!),
                        // Row-quantity role (spec §4): tabular titleLarge.
                        trailing: Text(
                          formatSignedMicros(
                            summary.onHandMicros,
                            summary.item.unit,
                          ),
                          style: Numerals.rowQuantity(
                            Theme.of(context).textTheme,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(summary),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
