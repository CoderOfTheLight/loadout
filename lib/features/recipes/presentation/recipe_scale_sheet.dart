/// "Scale to event" bottom sheet (proposal §3, recipe screen): pick an
/// upcoming event and see the CURRENT revision as whole batches — batches
/// needed = ceil(need ÷ yield) with the rounding said out loud, and every
/// ingredient in two columns (per batch, for all batches).
///
/// The NEED is read from the event's latest PERSISTED forecast snapshot —
/// the same number the packing list shows (effective load: override wins,
/// cold-start baseline fills in) — never a live recompute, so this sheet
/// can never disagree with the packing list. Staleness is said out loud,
/// exactly as the review screen says it. This is a view: the saved recipe
/// never changes, and nothing here writes anything.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/unit_display.dart';
import '../../../core/quantity_codec.dart';
import '../../catalog/domain/item.dart';
import '../../events/application/event_service.dart';
import '../../forecasting/domain/snapshot.dart';
import '../../forecasting/presentation/forecast_presentation_support.dart';
import '../domain/recipe.dart';
import 'recipe_scale_math.dart';

/// Opens the sheet over the recipe's CURRENT revision. Read-only.
Future<void> showRecipeScaleSheet(
  BuildContext context, {
  required String outputItemId,
  required String outputItemName,
  required RecipeRevisionView revision,
  required Map<String, Item> itemsById,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => RecipeScaleSheet(
    outputItemId: outputItemId,
    outputItemName: outputItemName,
    revision: revision,
    itemsById: itemsById,
  ),
);

class RecipeScaleSheet extends ConsumerStatefulWidget {
  const RecipeScaleSheet({
    super.key,
    required this.outputItemId,
    required this.outputItemName,
    required this.revision,
    required this.itemsById,
  });

  final String outputItemId;
  final String outputItemName;

  /// The recipe's CURRENT (latest) revision — scaling always cooks today's
  /// method, whatever revision the detail screen happens to be viewing.
  final RecipeRevisionView revision;
  final Map<String, Item> itemsById;

  @override
  ConsumerState<RecipeScaleSheet> createState() => _RecipeScaleSheetState();
}

class _RecipeScaleSheetState extends ConsumerState<RecipeScaleSheet> {
  String? _eventId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = ref.watch(eventListProvider(EventStatusFilter.upcoming));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Scale to event', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Using revision ${widget.revision.revision} (current). '
                'A view only — the saved recipe never changes.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: events.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Events could not be loaded.'),
                  ),
                  data: (upcoming) => upcoming.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No upcoming events. Plan one and generate its '
                            'packing list, then scale from here.',
                            style: theme.textTheme.bodyLarge,
                          ),
                        )
                      : _buildPicked(theme, upcoming),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPicked(ThemeData theme, List<EventSummary> upcoming) {
    final selected = upcoming.firstWhere(
      (event) => event.id == _eventId,
      orElse: () => upcoming.first,
    );
    // Non-lazy on purpose: the ingredient table is short and must be
    // walkable (and testable) as one column.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('scale-event-picker'),
            initialValue: selected.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Event',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final event in upcoming)
                DropdownMenuItem(
                  value: event.id,
                  child: Text(
                    '${event.name} · ${event.scheduledDate}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _eventId = value),
          ),
          const SizedBox(height: 12),
          _ScaleBody(
            eventId: selected.id,
            outputItemId: widget.outputItemId,
            outputItemName: widget.outputItemName,
            revision: widget.revision,
            itemsById: widget.itemsById,
          ),
        ],
      ),
    );
  }
}

class _ScaleBody extends ConsumerWidget {
  const _ScaleBody({
    required this.eventId,
    required this.outputItemId,
    required this.outputItemName,
    required this.revision,
    required this.itemsById,
  });

  final String eventId;
  final String outputItemId;
  final String outputItemName;
  final RecipeRevisionView revision;
  final Map<String, Item> itemsById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snapshotAsync = ref.watch(latestSnapshotProvider(eventId));
    return snapshotAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _Message('The packing list could not be loaded.'),
      data: (snapshot) {
        if (snapshot == null) {
          return _Message(
            'No packing list for this event yet — open the event and '
            'generate its forecast first.',
          );
        }
        ForecastLineView? line;
        for (final candidate in snapshot.lines) {
          if (candidate.itemId.value == outputItemId) {
            line = candidate;
            break;
          }
        }
        if (line == null) {
          return _Message(
            '«$outputItemName» is not on this event\'s packing list, so '
            'there is nothing to scale from. Add it to the event and '
            'regenerate the forecast.',
          );
        }
        final need = line.effectiveLoadMicros;
        if (need == null) {
          return _Message(
            'Loadout has no amount for «$outputItemName» at this event '
            'yet — set a baseline from its forecast line first.',
          );
        }
        final stale =
            ref.watch(forecastStalenessProvider(eventId)).valueOrNull ?? false;
        final olderMethod = snapshot.methodVersion != forecastMethodVersion;
        final plan = RecipeBatchPlan(
          needMicros: need,
          yieldMicros: revision.yieldQuantity.micros,
        );
        final label = revision.yieldLabel;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key: const Key('scale-context'),
              'Packing list: bring ${formatMicros(need)} for '
              '${snapshot.upcomingExposure} ${exposureLabelOf(snapshot)}.'
              '${line.isBaseline ? ' An estimate — nothing confirmed yet.' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            if (olderMethod || stale) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 18,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The packing list is out of date — refresh it on the '
                      'event\'s forecast screen before you cook.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'One batch makes '
              '${QuantityCodec.format(revision.yieldQuantity)}'
              '${label == null || label.isEmpty ? '' : ' — “$label”'}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              key: const Key('scale-verdict'),
              plan.verdict,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _IngredientTable(
              revision: revision,
              itemsById: itemsById,
              batches: plan.batches,
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

/// Two columns per ingredient: per batch, and for all batches — both exact.
class _IngredientTable extends StatelessWidget {
  const _IngredientTable({
    required this.revision,
    required this.itemsById,
    required this.batches,
  });

  final RecipeRevisionView revision;
  final Map<String, Item> itemsById;
  final int batches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Ingredient', style: headerStyle)),
            SizedBox(
              width: 84,
              child: Text(
                'Per batch',
                style: headerStyle,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                batches == 1 ? 'For 1 batch' : 'For $batches batches',
                style: headerStyle,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const Divider(),
        for (final line in revision.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildLine(theme, line),
          ),
      ],
    );
  }

  Widget _buildLine(ThemeData theme, RecipeLine line) {
    final item = itemsById[line.ingredientItemId.value];
    final name = item == null
        ? 'Unknown item'
        : item.isArchived
        ? '${item.name} (archived)'
        : item.name;
    final suffix = item == null ? '' : unitSuffix(item.unit);
    return Row(
      children: [
        Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
        SizedBox(
          width: 84,
          child: Text(
            '${QuantityCodec.format(line.quantityPerBatch)}$suffix',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.right,
          ),
        ),
        SizedBox(
          width: 110,
          child: Text(
            '${scaledIngredientTotal(line.quantityPerBatch, batches)}$suffix',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
  );
}
