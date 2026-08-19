/// `/items/:itemId` (design §9 ItemDetailScreen): derived truth for one
/// item.
///
/// Header (name, the folder it lives in — chip + name, spec §3: identity is
/// always chip AND name — and optional group / "one serves N people");
/// **You have** stat from `stockPositionProvider` (signed, warning badge
/// when negative, display unit label after the amount); ONE primary action,
/// "Count" → `/movements/new?kind=count&itemId=…`; day-grouped movement
/// history preview with reversed rows struck-through and labeled
/// "Corrected" (history never hidden); menu: Edit, "Something arrived"
/// (`?kind=receive`), "Something was thrown out" (`?kind=waste`), the
/// first-class "Move to folder…" (picker → `MoveItemToFolder`),
/// Archive/Unarchive via `CatalogService.setArchived`, and "Delete item…"
/// behind the shared confirmation (delete_dialogs.dart) — on success the
/// screen pops back to the items list before the snackbar shows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_display.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../../core/money_codec.dart';
import '../../../core/result.dart';
import '../../inventory/application/inventory_service.dart';
import '../domain/folder.dart';
import '../domain/item.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'delete_dialogs.dart';
import 'folder_picker_sheet.dart';
import 'unfiled_chip.dart';

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

  /// The first-class "Move to folder…" (owner's feedback): the folder
  /// picker over the live folders, then the single `MoveItemToFolder`
  /// command — works no matter how many items share the current folder.
  Future<void> _moveToFolder(Item item) async {
    final pick = await showFolderPickerSheet(
      context,
      selectedFolderId: item.folderId?.value,
    );
    if (pick == null || !mounted || pick.folderId == item.folderId?.value) {
      return;
    }
    final result = await ref
        .read(catalogServiceProvider)
        .moveItemToFolder(itemId: widget.itemId, folderId: pick.folderId);
    if (!mounted) {
      return;
    }
    if (result case Err()) {
      // Content-free by design (§9): no names or quantities in errors.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't move this item. Try again.")),
      );
    }
  }

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

  /// "Delete item…" from the menu: the shared confirmation, then the single
  /// `DeleteItem` command. On success the screen pops back to the items
  /// list FIRST — the item is gone from every list, so there is nothing
  /// left to stand on — and the snackbar shows over the list.
  Future<void> _deleteItem(Item item) async {
    final name = item.name;
    final confirmed = await confirmDeleteItem(context, itemName: name);
    if (!confirmed || !mounted) {
      return;
    }
    // The app-level messenger outlives this screen's pop.
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(catalogServiceProvider)
        .deleteItem(itemId: widget.itemId);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        context.pop();
        messenger.showSnackBar(SnackBar(content: Text('Deleted "$name"')));
      case Err():
        // Content-free by design (§9): no names or quantities in errors.
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Couldn't delete this item. Try again."),
          ),
        );
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
    Folder? folder;
    for (final candidate
        in ref.watch(folderListProvider).valueOrNull ?? const <Folder>[]) {
      if (candidate.id.value == item.folderId?.value) {
        folder = candidate;
      }
    }
    final headerCaption = [
      if (item.category != null) item.category!,
      if (item.servesPerUnit != null)
        'One serves ${formatMicros(item.servesPerUnit!.micros)} people',
      // v7: the owner's CURRENT price, only when one is set — a closed
      // event's cost reads its closeout snapshot, never this.
      if (item.unitPrice case final price?)
        'Price each · ${MoneyCodec.format(price)}',
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
                case 'receive':
                  context.push(
                    '/movements/new?kind=receive&itemId=${widget.itemId}',
                  );
                case 'waste':
                  context.push(
                    '/movements/new?kind=waste&itemId=${widget.itemId}',
                  );
                case 'move':
                  _moveToFolder(item);
                case 'archive':
                  _setArchived(!item.isArchived);
                case 'delete':
                  _deleteItem(item);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              // The other two ledger entries, each named for what happened
              // rather than for the record it writes.
              PopupMenuItem(
                value: 'receive',
                enabled: !item.isArchived,
                child: const Text('Something arrived'),
              ),
              PopupMenuItem(
                value: 'waste',
                enabled: !item.isArchived,
                child: const Text('Something was thrown out'),
              ),
              PopupMenuItem(
                value: 'move',
                // The command refuses archived items; the menu says so by
                // being disabled rather than failing after the tap.
                enabled: !item.isArchived,
                child: const Text('Move to folder…'),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Text(item.isArchived ? 'Unarchive' : 'Archive'),
              ),
              // Deleting an archived item is allowed (a delete may archive
              // under the hood, but never the other way blocked).
              const PopupMenuItem(value: 'delete', child: Text('Delete item…')),
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
                // Where it lives (spec §3: identity is chip AND name).
                Row(
                  children: [
                    if (folder != null)
                      FolderChip.forFolder(folder, size: FolderChipSize.small)
                    else
                      const UnfiledChip(size: FolderChipSize.small),
                    const SizedBox(width: Space.s + 2),
                    Expanded(
                      child: Text(
                        folder?.name ?? 'Unfiled',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                // ONE primary action. Counting is what the owner comes here
                // to do; everything else that writes to the ledger sits in
                // the overflow, each on its own plain-words screen.
                FilledButton(
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
              'You have '
              '${formatAmount(onHandMicros, item.unit, item.unitLabel)}'
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
                  // the 22 pt touchscreen-glance figure, with the display
                  // label after the amount ("12 packages").
                  Text(
                    formatAmount(onHandMicros, item.unit, item.unitLabel),
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
