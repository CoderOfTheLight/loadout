/// Searchable item picker bottom sheet (design §9 MovementEntryScreen:
/// "item picker (searchable sheet, on-hand inline)"). Returns the chosen
/// [ItemSummary], or null when dismissed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../catalog/application/catalog_service.dart';
import 'movement_display.dart';

Future<ItemSummary?> showItemPickerSheet(BuildContext context) =>
    showModalBottomSheet<ItemSummary>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ItemPickerSheet(),
    );

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
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                        trailing: Text(
                          formatSignedMicros(
                            summary.onHandMicros,
                            summary.item.unit,
                          ),
                          style: Theme.of(context).textTheme.bodyMedium,
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
