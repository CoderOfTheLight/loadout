import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'forecast_engine.dart';
// The method version tags the encoding (see [canonicalInputs]); reading the
// single constant beats keeping a duplicate literal in step with it.
import 'snapshot.dart';

/// One evidence value-copy as the engine saw it, in label-query order
/// (`scheduled_date DESC, event_id DESC`).
final class EvidenceInput {
  const EvidenceInput({
    required this.closeoutId,
    required this.sourceEventId,
    required this.exposure,
    required this.depletionMicros,
    required this.stockout,
    required this.approximate,
  });

  final String closeoutId;
  final String sourceEventId;
  final int exposure;
  final int depletionMicros;
  final bool stockout;
  final bool approximate;
}

/// Per-item frozen inputs. [onHandMicros] is the SIGNED derived on-hand at
/// generation time; the engine consumed `max(0, onHandMicros)`.
final class SnapshotLineInput {
  const SnapshotLineInput({
    required this.itemId,
    required this.packSizeMicros,
    required this.onHandMicros,
    this.confirmedInboundMicros = 0,
    this.servesPerUnitMicros,
    required this.evidence,
  });

  final String itemId;
  final int packSizeMicros;
  final int onHandMicros;
  final int confirmedInboundMicros;

  /// The item's "1 serves N" at generation time. Material to the outputs
  /// (it drives the no-history baseline), so it is hashed — see
  /// [canonicalInputs].
  final int? servesPerUnitMicros;

  /// Label-query order — NOT re-sorted by the encoding.
  final List<EvidenceInput> evidence;
}

/// Everything material to a snapshot's outputs (design §6.6). Timestamps and
/// snapshot/command ids are deliberately absent: same hash ⇒ byte-identical
/// outputs.
final class SnapshotInputs {
  const SnapshotInputs({
    required this.policy,
    required this.upcomingExposure,
    required this.historyWindow,
    required this.lines,
  });

  final PlanningPolicy policy;
  final int upcomingExposure;
  final int historyWindow;
  final List<SnapshotLineInput> lines;
}

/// The normative canonical input encoding (design §6.6, verbatim contract).
/// Lines are ordered by itemId bytewise ascending regardless of construction
/// order; evidence keeps label-query order.
///
/// Schema-v2 extension: an item's serves-per-unit changes the no-history
/// baseline, so it is material and must be hashed. It is appended as
/// `|s=<micros>` ONLY when non-null, which leaves the encoding byte-identical
/// for every item that has no serves-per-unit.
///
/// The leading `direct_median|<n>` is the METHOD version, and it is what makes
/// the contract below ("same hash ⇒ byte-identical outputs") true rather than
/// merely usually true. Method v2 handles sell-out days as lower bounds
/// (§6.6), so identical inputs produce different outputs than v1 did and the
/// tag moves with it. The deliberate consequence: every snapshot stored by v1
/// now recomputes to a different hash and reads as out of date, which is
/// exactly what it is. The forecast screen names the reason rather than
/// blaming an input change.
String canonicalInputs(SnapshotInputs s) {
  final lines = s.lines.toList()..sort((a, b) => a.itemId.compareTo(b.itemId));
  final b = StringBuffer()
    ..write(
      'direct_median|$forecastMethodVersion|${s.policy.name}'
      '|${s.upcomingExposure}|${s.historyWindow}',
    );
  for (final line in lines) {
    b.write(
      '\n${line.itemId}|${line.packSizeMicros}'
      '|${line.onHandMicros}|${line.confirmedInboundMicros}',
    );
    if (line.servesPerUnitMicros != null) {
      b.write('|s=${line.servesPerUnitMicros}');
    }
    for (final e in line.evidence) {
      b.write(
        ';${e.closeoutId}:${e.exposure}:${e.depletionMicros}'
        ':${e.stockout ? 1 : 0}:${e.approximate ? 1 : 0}',
      );
    }
  }
  return b.toString();
}

/// SHA-256 lowercase hex over the UTF-8 bytes of [canonicalInputs].
String computeInputsHash(SnapshotInputs inputs) =>
    sha256.convert(utf8.encode(canonicalInputs(inputs))).toString();
