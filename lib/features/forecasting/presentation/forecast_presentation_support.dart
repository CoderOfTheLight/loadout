/// Feature-local presentation support for the forecast screens: item index,
/// append-only override history, and pure formatting helpers shared by the
/// review and line-detail screens.
///
/// The override-history provider reads the forecast DAO directly (read-only)
/// because the frozen `ForecastService` surface exposes only the LATEST
/// override per line, while §9 requires the full append-only log. No write
/// path exists here; every mutation still goes through the command path.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/unit_display.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/item.dart';
import '../domain/forecast_engine.dart';
import '../domain/snapshot.dart';

// ------------------------------------------------------------- providers

/// itemId → [Item] over the whole catalog, archived included: snapshot
/// lines are frozen history and may reference archived items.
final forecastItemIndexProvider = StreamProvider.autoDispose<Map<String, Item>>(
  (ref) => ref
      .watch(catalogServiceProvider)
      .watchItems(const ItemFilter(includeArchived: true))
      .map(
        (summaries) => {
          for (final summary in summaries)
            summary.item.id as String: summary.item,
        },
      ),
);

/// Family key for [overrideHistoryProvider].
typedef OverrideHistoryKey = ({
  String eventId,
  String snapshotId,
  String itemId,
});

/// The append-only override log for one (snapshot, item), newest first.
/// Recomputes whenever [latestSnapshotProvider] emits (it re-emits on any
/// `forecast_overrides` write).
final overrideHistoryProvider = FutureProvider.autoDispose
    .family<List<OverrideView>, OverrideHistoryKey>((ref, key) async {
      ref.watch(latestSnapshotProvider(key.eventId));
      final rows = await ref
          .read(appDatabaseProvider)
          .forecastDao
          .overridesForSnapshot(key.snapshotId);
      return [
        for (final row in rows.reversed)
          if (row.itemId == key.itemId)
            OverrideView(
              id: row.id,
              overrideLoadMicros: row.overrideLoadMicros,
              reason: row.reason,
              createdAt: Instant(row.createdAtMicros),
            ),
      ];
    });

// ------------------------------------------------------------ formatting

/// Signed micros → minimal decimal string (`-2.5`, `60`). Display only.
String formatMicros(int micros) => micros < 0
    ? '-${QuantityCodec.format(Quantity.fromMicros(-micros))}'
    : QuantityCodec.format(Quantity.fromMicros(micros));

/// `45`, `1.5 kg`, or `—` for null.
///
/// A counted item reads as a bare number — units left the product surface in
/// schema v2 (see [unitSuffix]). A legacy measured row keeps its real unit,
/// because its stored number genuinely means kilograms or litres. A null
/// unit (item missing from the index) is treated as counted.
String formatQuantity(int? micros, ItemUnit? unit) => micros == null
    ? '—'
    : '${formatMicros(micros)}${unitSuffix(unit ?? ItemUnit.each)}';

/// Policy chip label (§9: `Balanced +10 %`).
String policyChipLabel(PlanningPolicy policy) {
  final name = policy.name[0].toUpperCase() + policy.name.substring(1);
  return '$name +${policy.reservePercent} %';
}

/// The `exposure_label` recorded in the snapshot's assumptions JSON; the
/// seed default when the stored JSON carries none.
String exposureLabelOf(ForecastSnapshotView snapshot) {
  try {
    final decoded = jsonDecode(snapshot.assumptionsJson);
    if (decoded is Map<String, dynamic>) {
      final label = decoded['exposure_label'];
      if (label is String && label.trim().isNotEmpty) return label.trim();
    }
  } on FormatException {
    // Fall through to the default.
  }
  return 'attendance';
}

/// Evidence badge text (§9: `No history` / `1 event` / `N events`), plus the
/// fourth state the frozen engine cannot express.
///
/// Switches on [ForecastLineView.basis], never on `evidenceGrade`: a line
/// with no closeouts but a "1 serves N" estimate carries a real number, and
/// badging it `No history` beside that number reads as a bug.
String evidenceBadgeLabel(ForecastLineView line) => switch (line.basis) {
  ForecastBasis.insufficientData => 'No history',
  ForecastBasis.servesBaseline => 'Estimate',
  ForecastBasis.singleEvent => '1 event',
  ForecastBasis.observedRange => '${line.evidence.length} events',
};

/// How this line's sell-out days were treated, or null when none sold out.
///
/// Derived from the STORED evidence — the real confirmed flags — so it says
/// the same thing whether it is read now or in a year. Only lines the engine
/// actually forecast carry an adjustment; a blank line had no arithmetic to
/// adjust.
///
/// [methodVersion] is the SNAPSHOT's stored version, not the app's. A
/// snapshot older than [selloutAwareMethodVersion] was computed before the
/// correction existed, so it says the days ran out and that this forecast did
/// not allow for them. Claiming otherwise over frozen history would be a lie
/// the owner has no way to check — and a closed event shows no "older method"
/// banner to correct it, because there is nothing left to regenerate.
String? selloutHandlingNote(
  ForecastLineView line, {
  required int methodVersion,
}) {
  if (line.basis != ForecastBasis.singleEvent &&
      line.basis != ForecastBasis.observedRange) {
    return null;
  }
  final sellouts = line.evidence.where((e) => e.stockout).length;
  if (sellouts == 0) return null;
  final of = '$sellouts of ${line.evidence.length}';
  if (methodVersion < selloutAwareMethodVersion) {
    return '$of — this forecast did not allow for them';
  }
  return sellouts == line.evidence.length
      ? '$of — busiest day used for all'
      : '$of — raised to your typical rate';
}

/// `computed <relative time>` source (`just now`, `5 min ago`, `3 h ago`,
/// else the local calendar date).
String relativeTimeLabel(Instant instant, {DateTime? now}) {
  final at = DateTime.fromMicrosecondsSinceEpoch(
    instant.epochMicrosUtc,
    isUtc: true,
  );
  final difference = ((now ?? DateTime.now()).toUtc()).difference(at);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} h ago';
  final local = at.toLocal();
  return '${local.year}-${_pad(local.month)}-${_pad(local.day)}';
}

/// Absolute local timestamp (`2026-08-11 14:32`) for assumption rows.
String absoluteTimeLabel(Instant instant) {
  final local = DateTime.fromMicrosecondsSinceEpoch(
    instant.epochMicrosUtc,
    isUtc: true,
  ).toLocal();
  return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
      '${_pad(local.hour)}:${_pad(local.minute)}';
}

String _pad(int value) => value.toString().padLeft(2, '0');

/// Integer variance percent (`variance / expected`, truncated), or null
/// when either side is missing or expected is zero. Integer arithmetic only.
int? variancePercent({
  required int? varianceMicros,
  required int? expectedUseMicros,
}) {
  if (varianceMicros == null ||
      expectedUseMicros == null ||
      expectedUseMicros == 0) {
    return null;
  }
  return (varianceMicros * 100) ~/ expectedUseMicros;
}

/// Accuracy delta caption (§9: `forecast 36, actual 31, -14 %`).
String accuracyCaption({
  required int? expectedUseMicros,
  required int? actualDepletionMicros,
  required int? varianceMicros,
}) {
  if (actualDepletionMicros == null) {
    return 'No confirmed actual for this item.';
  }
  if (expectedUseMicros == null) {
    return 'No forecast figure to compare against.';
  }
  final percent = variancePercent(
    varianceMicros: varianceMicros,
    expectedUseMicros: expectedUseMicros,
  );
  final buffer = StringBuffer(
    'forecast ${formatMicros(expectedUseMicros)}, '
    'actual ${formatMicros(actualDepletionMicros)}',
  );
  if (percent != null) {
    buffer.write(', ${percent >= 0 ? '+' : ''}$percent %');
  }
  return buffer.toString();
}
