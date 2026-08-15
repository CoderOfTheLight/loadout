/// `/items/:itemId` (design §9 ItemDetailScreen): derived truth for one
/// item.
///
/// Header (name, optional group and "one serves N people"); **You have**
/// stat from `stockPositionProvider` (signed, warning badge when negative); quick
/// actions "Record movement" → `/movements/new?itemId=…` and "Count" →
/// `?kind=count`; day-grouped movement history preview with reversed rows
/// struck-through and labeled "Corrected" (history never hidden); menu:
/// Edit, Archive/Unarchive via `CatalogService.setArchived`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_display.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../../core/result.dart';
import '../../inventory/application/inventory_service.dart';
import '../domain/item.dart';
import 'catalog_format.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  /// Stable instance so the [movementLogProvider] family key never churns
  /// (the filter type has no value equality).
  late final MovementFilter _historyFilter = MovementFilter(
    itemId: widget.itemId,
    limit: 30,
  );

  Future<void> _setArchived(bool archived) async {
    final result = await ref
        .read(catalogServiceProvider)
        .setArchived(itemId: widget.itemId, archived: archived);
    if (!mounted) {
      return;
    }
    if (result case Err(:final error)) {
      final message = error.message.contains('name already exists')
          ? 'A live item with this name already exists — rename it before '
                'unarchiving.'
          : "Couldn't save this change. Try again.";
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(itemDetailProvider(widget.itemId));
    final detail = detailAsync.valueOrNull;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Item')),
        body: detailAsync.hasError
            ? const EmptyState(
                message: 'This item is not available.',
                icon: Icons.error_outline,
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final item = detail.item;
    final position = ref.watch(stockPositionProvider(widget.itemId));
    final onHandMicros =
        position.valueOrNull?.onHandMicros ?? detail.onHandMicros;
    final movements =
        ref.watch(movementLogProvider(_historyFilter)).valueOrNull ??
        const <MovementView>[];
    final theme = Theme.of(context);
    final headerCaption = [
      if (item.category != null) item.category!,
      if (item.servesPerUnit != null)
        'One serves ${formatMicros(item.servesPerUnit!.micros)} people',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  context.push('/items/${widget.itemId}/edit');
                case 'archive':
                  _setArchived(!item.isArchived);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'archive',
                child: Text(item.isArchived ? 'Unarchive' : 'Archive'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (headerCaption.isNotEmpty) ...[
                  Text(headerCaption, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                ],
                if (item.isArchived) ...[
                  WarningBanner(
                    message:
                        'This item is archived. It stays out of new plans '
                        'until you unarchive it.',
                    actionLabel: 'Unarchive',
                    onAction: () => _setArchived(false),
                  ),
                  const SizedBox(height: 16),
                ],
                _OnHandCard(onHandMicros: onHandMicros, item: item),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: primaryButtonMinSize,
                        ),
                        onPressed: item.isArchived
                            ? null
                            : () => context.push(
                                '/movements/new?itemId=${widget.itemId}',
                              ),
                        child: const Text('Record movement'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: primaryButtonMinSize,
                        ),
                        onPressed: item.isArchived
                            ? null
                            : () => context.push(
                                '/movements/new?kind=count'
                                '&itemId=${widget.itemId}',
                              ),
                        child: const Text('Count'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('History', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (movements.isEmpty)
                  const EmptyState(
                    message:
                        'No movements yet. Record a purchase or a count to '
                        'establish on-hand.',
                    icon: Icons.receipt_long_outlined,
                  )
                else
                  for (final group in _groupByDay(movements)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        group.day,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final view in group.rows) _MovementRow(view: view),
                  ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnHandCard extends StatelessWidget {
  const _OnHandCard({required this.onHandMicros, required this.item});

  final int onHandMicros;
  final Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final negative = onHandMicros < 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          label:
              'You have ${formatCount(onHandMicros, item.unit)}'
              '${negative ? ', negative' : ''}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You have', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (negative) ...[
                    Icon(Icons.warning_amber_outlined, color: scheme.error),
                    const SizedBox(width: 8),
                  ],
                  // Glance-number role (spec §5): tabular headlineSmall —
                  // the 22 pt touchscreen-glance figure.
                  Text(
                    formatCount(onHandMicros, item.unit),
                    style: Numerals.glance(
                      theme.textTheme,
                    )?.copyWith(color: negative ? scheme.error : null),
                  ),
                ],
              ),
              if (negative) ...[
                const SizedBox(height: 4),
                Text(
                  'Negative — record a count to fix it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.view});

  final MovementView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final movement = view.movement;
    final corrected = view.reversedByMovementId != null;
    final quantity =
        '${formatSignedMicros(movement.deltaMicros)}'
        '${unitSuffix(view.itemUnit)}';
    final label = movementKindLabel(movement.kind);
    final struck = corrected
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    return Semantics(
      label: corrected
          ? 'Corrected entry: $label $quantity'
          : '$label $quantity',
      excludeSemantics: true,
      child: ListTile(
        minTileHeight: 56,
        contentPadding: EdgeInsets.zero,
        leading: Icon(movementKindIcon(movement.kind)),
        title: Text(label, style: struck),
        subtitle: Text(formatTime(movement.occurredAt)),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Row-quantity role (spec §4): tabular titleLarge.
            Text(
              quantity,
              style: Numerals.rowQuantity(theme.textTheme)?.merge(struck),
            ),
            if (corrected)
              Text(
                'Corrected',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
          ],
        ),
        onTap: () => context.push('/movements/${movement.id.value}'),
      ),
    );
  }
}

final class _DayGroup {
  _DayGroup(this.day);

  final String day;
  final List<MovementView> rows = [];
}

/// Groups consecutive rows (already newest-first) by local occurred-at day.
List<_DayGroup> _groupByDay(List<MovementView> movements) {
  final groups = <_DayGroup>[];
  for (final view in movements) {
    final day = formatDay(view.movement.occurredAt);
    if (groups.isEmpty || groups.last.day != day) {
      groups.add(_DayGroup(day));
    }
    groups.last.rows.add(view);
  }
  return groups;
}
