/// §9 `/recipes` — RecipeListScreen.
///
/// Live recipes (output item, yield caption, ingredient count, "rev N"),
/// an archived filter, FAB → `/recipes/new`. Commands: none.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../application/recipe_service.dart';

class RecipeListScreen extends ConsumerStatefulWidget {
  const RecipeListScreen({super.key});

  @override
  ConsumerState<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends ConsumerState<RecipeListScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipeListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay mounted together, so every FAB needs its own
        // hero tag.
        heroTag: 'fab-recipes',
        onPressed: () => context.push('/recipes/new'),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
      body: recipes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text("Couldn't load recipes.")),
        data: _buildLoaded,
      ),
    );
  }

  Widget _buildLoaded(List<RecipeSummary> all) {
    if (all.isEmpty) {
      // Empty-state tone (design-spec §2): warm first line in the owner's
      // register, instructive second line, same tinted-disc skeleton.
      return EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Nothing on the menu yet',
        message:
            'Recipes let Loadout plan production later. '
            'Enter one by hand — takes a minute.',
        actionLabel: 'New recipe',
        onAction: () => context.push('/recipes/new'),
      );
    }
    final archivedCount = all.where((r) => r.archivedAt != null).length;
    // DAO order: live first, then archived, names case-insensitive.
    final visible = _showArchived
        ? all
        : all.where((r) => r.archivedAt == null).toList();
    return ContentColumn(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (archivedCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FilterChip(
                label: Text('Show archived ($archivedCount)'),
                selected: _showArchived,
                onSelected: (selected) =>
                    setState(() => _showArchived = selected),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? const EmptyState(
                    icon: Icons.menu_book_outlined,
                    message:
                        'No live recipes. Turn on "Show archived" to see '
                        'archived ones, or enter a new recipe.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        _RecipeTile(summary: visible[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecipeTile extends StatelessWidget {
  const _RecipeTile({required this.summary});

  final RecipeSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final archived = summary.archivedAt != null;
    return ListTile(
      leading: Icon(
        archived ? Icons.inventory_2_outlined : Icons.menu_book_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(summary.name),
      subtitle: Text(_subtitle),
      trailing: Text(
        'rev ${summary.latestRevision}',
        style: theme.textTheme.labelLarge,
      ),
      onTap: () => context.push('/recipes/${summary.id}'),
    );
  }

  String get _subtitle {
    final parts = <String>[
      if (summary.archivedAt != null) 'Archived',
      summary.outputItemName,
      _yieldCaption,
      '${summary.ingredientCount} '
          '${summary.ingredientCount == 1 ? 'ingredient' : 'ingredients'}',
    ];
    return parts.where((part) => part.isNotEmpty).join(' · ');
  }

  String get _yieldCaption {
    final micros = summary.yieldMicros;
    if (micros == null) return '';
    final amount = QuantityCodec.format(Quantity.fromMicros(micros));
    final label = summary.yieldLabel;
    return label == null || label.isEmpty
        ? 'Makes $amount'
        : 'Makes $amount ($label)';
  }
}
