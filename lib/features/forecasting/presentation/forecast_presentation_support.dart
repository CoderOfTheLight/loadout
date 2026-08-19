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
import '../../../core/quantity_codec.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/demand_basis.dart';
import '../../catalog/domain/item.dart';
import '../../events/presentation/event_ui.dart';
import '../application/baseline_estimator.dart';
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

/// Signed micros → the decimal string the owner reads (`-2.5`, `60`,
/// `14.3`). Display only, and ROUNDED: every figure on these screens is a
/// median times an attendance times a reserve, which lands on values like
/// 14.272728 — six decimals of arithmetic residue on a card that counts
/// trays. [QuantityCodec.formatDisplay] caps it at the tenth; the stored
/// micros and every engine computation are untouched.
String formatMicros(int micros) => micros < 0
    ? '-${QuantityCodec.formatDisplayMicros(-micros)}'
    : QuantityCodec.formatDisplayMicros(micros);

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
///
/// The blank state splits on the evidence for the same reason: a line whose
/// confirmed history was too large to scale is stored as `insufficient_data`
/// WITH its closeouts, and badging those "No history" would deny records the
/// owner can see listed one tap away.
String evidenceBadgeLabel(ForecastLineView line) => switch (line.basis) {
  ForecastBasis.insufficientData =>
    line.evidence.isEmpty
        ? 'No history'
        : '${line.evidence.length} '
              'event${line.evidence.length == 1 ? '' : 's'}',
  ForecastBasis.servesBaseline => 'Estimate',
  ForecastBasis.perEventBaseline => 'Estimate',
  ForecastBasis.singleEvent => '1 event',
  ForecastBasis.observedRange => '${line.evidence.length} events',
};

// ------------------------------------------------- one line, in one sentence

/// The one short line that stands in for the stacked cold-start warnings.
///
/// A line with no confirmed history used to carry TWO amber banners saying
/// the same thing twice in the engine's vocabulary — "No comparable confirmed
/// outcomes. Create a baseline plan." and "Estimate only: worked out from
/// '1 serves 4', not from confirmed outcomes…". Both mean "this is a guess",
/// and a volunteer reading a packing list needs that once, in her own words.
const String coldStartNote = 'A guess — no past events to learn from yet.';

/// The same note for a line that has NO number at all.
///
/// [coldStartNote] replaces two banners on a line that produced a starting
/// figure from "1 serves N" (or the ratio, or the usual amount) — that figure
/// really is a guess. A line with nothing to guess from produced no figure,
/// carried only the engine's own banner, and calling it "a guess" would name
/// something that does not exist. One short line either way.
String coldStartNoteFor(ForecastLineView line) =>
    line.effectiveLoadMicros == null
    ? 'No past events to learn from yet.'
    : coldStartNote;

/// True for the stored warnings [coldStartNote] speaks for. Every other
/// warning — the exposure range, the sell-out lift, the supplies jump, the
/// out-of-envelope refusal — still renders verbatim, because each says
/// something [coldStartNote] does not.
bool isColdStartWarning(String warning) =>
    warning == 'No comparable confirmed outcomes. Create a baseline plan.' ||
    warning.startsWith('Estimate only:');

/// True when this line rests on NO confirmed outcome at all — a cold-start
/// estimate, or nothing whatever.
///
/// The evidence check is not redundant: a line whose confirmed history is too
/// large to scale is stored as `insufficient_data` WITH its evidence, and
/// calling that "no past events to learn from" would be a lie.
bool isColdStartLine(ForecastLineView line) =>
    line.evidence.isEmpty &&
    line.basis != ForecastBasis.singleEvent &&
    line.basis != ForecastBasis.observedRange;

/// The whole of one forecast line as one sentence a human can check:
/// what to bring, what that rests on, and what is already on the shelf.
///
/// Every clause is read off the SAME stored fields the old assumptions table
/// printed — nothing is recomputed, and nothing here can be true of one case
/// and false of another: no history, one event, a cold-start guess, an
/// override in force and an empty shelf each get their own words.
String forecastLineSentence(
  ForecastLineView line, {
  required int upcomingExposure,
  required String exposureLabel,
  ItemUnit? unit,
}) {
  final explanation = forecastLineExplanation(
    line,
    upcomingExposure: upcomingExposure,
    exposureLabel: exposureLabel,
    unit: unit,
  );
  return '${forecastLineInstruction(line, unit: unit)} $explanation';
}

/// The instruction half — the only thing on the screen that is an action.
String forecastLineInstruction(ForecastLineView line, {ItemUnit? unit}) =>
    line.effectiveLoadMicros == null
    ? 'No number yet.'
    : 'Bring ${formatQuantity(line.effectiveLoadMicros, unit)}.';

/// The evidence half: who set the number, what it came from, what you have.
String forecastLineExplanation(
  ForecastLineView line, {
  required int upcomingExposure,
  required String exposureLabel,
  ItemUnit? unit,
}) {
  final clauses = <String>[];
  if (line.isOverridden) clauses.add(_overrideClause(line, unit));
  final why = _basisClause(
    line,
    upcomingExposure: upcomingExposure,
    exposureLabel: exposureLabel,
    unit: unit,
  );
  if (why != null) clauses.add(why);
  clauses.add(_onHandClause(line, unit));
  return clauses.join(' ');
}

/// An override is the owner's own number, so the sentence says whose it is
/// and what the app would have said instead — never silently.
String _overrideClause(ForecastLineView line, ItemUnit? unit) {
  final reason = line.override!.reason.trim().replaceAll(
    RegExp(r'[.\s]+$'),
    '',
  );
  final suggested = line.suggestedLoadMicros;
  if (suggested == null) {
    return 'You set that yourself: $reason. Loadout had no number of its own.';
  }
  return 'You set that yourself: $reason. '
      'Loadout worked out ${formatQuantity(suggested, unit)}.';
}

/// What the number rests on, in the two most recent confirmed outcomes —
/// the rows below list every one of them. Null when there is nothing to say.
String? _basisClause(
  ForecastLineView line, {
  required int upcomingExposure,
  required String exposureLabel,
  ItemUnit? unit,
}) {
  switch (line.basis) {
    case ForecastBasis.singleEvent || ForecastBasis.observedRange:
      final history = line.evidence;
      if (history.isEmpty) return null;
      // Attendance is deliberately absent on a per-event item: ignoring
      // headcount is exactly what that basis means, so quoting one would
      // suggest the number moves with it.
      final perEvent = line.demandBasis == DemandBasis.perEvent;
      final first = formatQuantity(history.first.depletionMicros, unit);
      final firstFor = perEvent
          ? first
          : '$first for ${history.first.exposure} $exposureLabel';
      if (history.length == 1) return 'Last time you used $firstFor.';
      final second = formatQuantity(history[1].depletionMicros, unit);
      final secondFor = perEvent
          ? second
          : '$second for ${history[1].exposure}';
      return 'Last time you used $firstFor; before that, $secondFor.';
    case ForecastBasis.servesBaseline:
      if (line.baselineServesPerUnitMicros case final serves?) {
        return '$coldStartNote One serves ${formatServesPerUnit(serves)}, '
            'and you are expecting $upcomingExposure $exposureLabel.';
      }
      if ((line.baselinePerPersonNumerator, line.baselinePerPersonDenominator)
          case (final numerator?, final denominator?)) {
        return '$coldStartNote You said '
            '${formatPerPersonRatio(numerator, denominator)}, and you are '
            'expecting $upcomingExposure $exposureLabel.';
      }
      return coldStartNote;
    case ForecastBasis.perEventBaseline:
      if (line.baselinePerEventMicros case final usual?) {
        return '$coldStartNote You said you usually bring '
            '${formatQuantity(usual, unit)}.';
      }
      return coldStartNote;
    case ForecastBasis.insufficientData:
      // Two very different silences. One has no history; the other has
      // history the arithmetic could not carry — and saying "no past
      // events" over real closeouts would be a lie.
      return line.evidence.isEmpty
          ? 'No past events to learn from yet, and nothing saved for this '
                'item to guess from.'
          : 'Loadout could not work out a number from your past events.';
  }
}

/// What was on the shelf when this was worked out — the figure the acquire
/// number was subtracted with. "None" is said in words, never as a 0.
String _onHandClause(ForecastLineView line, ItemUnit? unit) {
  final usable = line.onHandMicros < 0 ? 0 : line.onHandMicros;
  final available = usable + line.confirmedInboundMicros;
  return available > 0
      ? 'You have ${formatQuantity(available, unit)}.'
      : 'You have none.';
}

/// `2026-08-07` → `Aug 7`, and `Aug 7 2025` when the year is not
/// [contextYear] — a bare "Aug 7" three years on would be ambiguous.
String shortEventDate(String ymd, {required int contextYear}) {
  final day = parseYmd(ymd);
  if (day == null) return ymd;
  const months = [
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
  final label = '${months[day.month - 1]} ${day.day}';
  return day.year == contextYear ? label : '$label ${day.year}';
}

/// How many DISTINCT past events this snapshot's numbers actually rest on.
///
/// Evidence is stored per line (each line carries the closeouts it was
/// medianed over), so the snapshot's own count is the union of the source
/// events across every line — the honest answer to "what is this built
/// from?", and 0 for a first estimate with nothing confirmed behind it.
int snapshotEvidenceEventCount(ForecastSnapshotView snapshot) => {
  for (final line in snapshot.lines)
    for (final evidence in line.evidence) evidence.sourceEventId as String,
}.length;

/// The provenance line at the top of a forecast, in the owner's words.
///
/// It used to read `Method: direct_median v3 · computed just now`. The
/// method identifier is an internal algorithm name: it tells a volunteer
/// kitchen coordinator nothing she can act on, and reads as a leaked
/// debugging string. What she needs is the same honesty in her own terms —
/// how much real history this rests on, and how fresh it is. The identifier
/// is still stored on every snapshot row; no screen prints it any more.
String snapshotProvenanceLabel(ForecastSnapshotView snapshot, {DateTime? now}) {
  final events = snapshotEvidenceEventCount(snapshot);
  final updated = relativeTimeLabel(snapshot.createdAt, now: now);
  if (events == 0) {
    return 'First estimate — no past events yet · updated $updated';
  }
  final window = events == 1 ? 'your last event' : 'your last $events events';
  return 'From $window · updated $updated';
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

/// The local calendar year an [Instant] fell in — what a bare `Aug 7` on an
/// evidence row is read against (see [shortEventDate]).
int instantYear(Instant instant) => DateTime.fromMicrosecondsSinceEpoch(
  instant.epochMicrosUtc,
  isUtc: true,
).toLocal().year;

/// Absolute local timestamp (`2026-08-11 14:32`) for the override log.
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
