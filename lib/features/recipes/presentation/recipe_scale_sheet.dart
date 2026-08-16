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
import '../../../app/theme.dart';
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
        // The total the whole batches make — the "Serves 240" glance figure
        // of spec §6, computed exactly (batches × yield). '—' would mean
        // the quantity envelope was left; the verdict still tells the story.
        final made = plan.batches == 0
            ? null
            : scaledIngredientTotal(revision.yieldQuantity, plan.batches);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scale header card (spec §6): the multiplier as one prominent
            // chip, the resulting amount as the glance number, and the
            // rounding said out loud. Restraint zone — the numbers are the
            // payload; no hue, no motion.
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (plan.batches > 0) ...[
                      Wrap(
                        spacing: Space.m,
                        runSpacing: Space.s,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(Radii.small),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.m,
                              vertical: Space.xs,
                            ),
                            child: Text(
                              '×${plan.batches} '
                              '${plan.batches == 1 ? 'batch' : 'batches'}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontFeatures: Numerals.tabular,
                              ),
                            ),
                          ),
                          if (made != null && made != '—')
                            Text(
                              'Makes $made',
                              style: Numerals.glance(theme.textTheme),
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.m),
                    ],
                    Text(
                      key: const Key('scale-verdict'),
                      plan.verdict,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      key: const Key('scale-context'),
                      'Packing list: bring ${formatMicros(need)} for '
                      '${snapshot.upcomingExposure} '
                      '${exposureLabelOf(snapshot)}.'
                      '${line.isBaseline ? ' An estimate — nothing confirmed yet.' : ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'One batch makes '
                      '${QuantityCodec.format(revision.yieldQuantity)}'
                      '${label == null || label.isEmpty ? '' : ' — “$label”'}.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (olderMethod || stale) ...[
                      const SizedBox(height: Space.m),
                      Container(
                        decoration: BoxDecoration(
                          color: StatusColors.of(context).warning,
                          borderRadius: BorderRadius.circular(Radii.small),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.m,
                          vertical: Space.s,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_outlined,
                              size: 18,
                              color: StatusColors.of(context).onWarning,
                            ),
                            const SizedBox(width: Space.s),
                            Expanded(
                              child: Text(
                                'The packing list is out of date — refresh '
                                'it on the event\'s forecast screen before '
                                'you cook.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: StatusColors.of(context).onWarning,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.l),
            Text('Ingredients', style: theme.textTheme.titleMedium),
            for (final recipeLine in revision.lines)
              _IngredientRow(
                line: recipeLine,
                itemsById: itemsById,
                batches: plan.batches,
              ),
            const SizedBox(height: Space.m),
          ],
        );
      },
    );
  }
}

/// One ingredient row (spec §6): name left, the scaled total right in the
/// row-quantity numeral role, the per-batch amount directly beneath it as a
/// caption. Plain vertical list — no hue, no motion, no chips (ingredients
/// aren't folders). Both figures exact.
class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.line,
    required this.itemsById,
    required this.batches,
  });

  final RecipeLine line;
  final Map<String, Item> itemsById;
  final int batches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // v5: free (unlinked) lines render under their own name and display-only
    // unit label; linked lines render as their live item.
    final item = switch (line.ingredientItemId) {
      final id? => itemsById[id.value],
      null => null,
    };
    final name = !line.isLinked
        ? line.name
        : item == null
        ? 'Unknown item'
        : item.isArchived
        ? '${item.name} (archived)'
        : item.name;
    final suffix = line.unitLabel != null
        ? ' ${line.unitLabel}'
        : item == null
        ? ''
        : unitSuffix(item.unit);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: Space.m),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${scaledIngredientTotal(line.quantityPerBatch, batches)}'
                '$suffix',
                style: Numerals.rowQuantity(theme.textTheme),
              ),
              Text(
                '${QuantityCodec.format(line.quantityPerBatch)}$suffix '
                'per batch',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
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
