/// Shared display helpers for the inventory screens (Home dashboard,
/// Activity, movement detail/entry/correction): movement-kind icon + label
/// pairs (meaning never color-only), signed quantity formatting over
/// [QuantityCodec] (negatives shown signed, never clamped), day grouping,
/// and the movement list row used by Activity and Home.
library;

import 'package:flutter/material.dart';

import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../application/inventory_service.dart';
import '../domain/movement.dart';

/// Human label per ledger kind (design §5/§9).
String movementKindLabel(MovementKind kind) => switch (kind) {
  MovementKind.receive => 'Purchase',
  MovementKind.consume => 'Event consumption',
  MovementKind.waste => 'Waste',
  MovementKind.adjust => 'Count adjustment',
  MovementKind.reversal => 'Correction',
};

/// Icon per ledger kind — always shown next to the label, never alone.
IconData movementKindIcon(MovementKind kind) => switch (kind) {
  MovementKind.receive => Icons.shopping_bag_outlined,
  MovementKind.consume => Icons.storefront_outlined,
  MovementKind.waste => Icons.delete_outline,
  MovementKind.adjust => Icons.rule,
  MovementKind.reversal => Icons.undo,
};

/// Signed micros -> `"-1.5 kg"` / `"12 each"`. Negative values keep their
/// sign (U+2212); positives carry no sign. Never clamps.
String formatSignedMicros(int micros, ItemUnit unit) {
  final magnitude = QuantityCodec.format(Quantity.fromMicros(micros.abs()));
  final sign = micros < 0 ? '−' : '';
  return '$sign$magnitude ${unit.dbValue}';
}

/// Ledger delta -> `"+12 kg"` / `"−1.5 kg"`: the sign is always
/// explicit so movement rows read as ledger entries.
String formatDeltaMicros(int micros, ItemUnit unit) => micros < 0
    ? formatSignedMicros(micros, unit)
    : '+${formatSignedMicros(micros, unit)}';

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime instantToLocal(Instant instant) => DateTime.fromMicrosecondsSinceEpoch(
  instant.epochMicrosUtc,
  isUtc: true,
).toLocal();

/// Calendar-day label for group headers: Today / Yesterday / `11 Aug 2026`.
String dayLabel(DateTime local, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day = DateTime(local.year, local.month, local.day);
  final startOfToday = DateTime(today.year, today.month, today.day);
  if (day == startOfToday) return 'Today';
  if (day == startOfToday.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// `14:05` from a local time.
String timeLabel(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}';

/// Full timestamp: `11 Aug 2026, 14:05`.
String dateTimeLabel(DateTime local) =>
    '${local.day} ${_months[local.month - 1]} ${local.year}, '
    '${timeLabel(local)}';

/// One movement list row (design §9 ActivityScreen / HomeScreen): kind icon
/// + label, item, signed quantity + unit, optional event tag, time.
/// Reversed rows are struck through with a "Corrected" chip (history is
/// never hidden); reversal rows read "Correction of an earlier entry".
class MovementRow extends StatelessWidget {
  const MovementRow({
    super.key,
    required this.view,
    this.eventName,
    this.onTap,
  });

  final MovementView view;

  /// Resolved event name for the event tag, when the movement is linked.
  final String? eventName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final movement = view.movement;
    final corrected = view.reversedByMovementId != null;
    final isReversal = movement.kind == MovementKind.reversal;
    final struck = corrected
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;

    final kindLabel = isReversal
        ? 'Correction of an earlier entry'
        : movementKindLabel(movement.kind);
    final local = instantToLocal(movement.occurredAt);
    final subtitleParts = [kindLabel, ?eventName, timeLabel(local)];
    final delta = formatDeltaMicros(movement.deltaMicros, view.itemUnit);

    final tile = ListTile(
      minTileHeight: 56,
      onTap: onTap,
      leading: Icon(movementKindIcon(movement.kind)),
      title: Text(
        view.itemName,
        style: struck,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        style: struck,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            delta,
            style: (struck ?? const TextStyle()).merge(
              theme.textTheme.bodyLarge,
            ),
          ),
          if (corrected)
            Text(
              'Corrected',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
    if (!corrected) return tile;
    return Semantics(
      label:
          'Corrected entry: ${movementKindLabel(movement.kind)}, '
          '${view.itemName}, $delta',
      child: tile,
    );
  }
}
