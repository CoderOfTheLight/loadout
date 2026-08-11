import 'dart:convert';

import '../../../core/quantity.dart';

/// Autosaved closeout worksheet draft (design §9 CloseoutScreen). A draft is
/// not a record; it round-trips through `closeout_drafts.payload_json` via
/// [encodeCloseoutFormDraft]/[decodeCloseoutFormDraft] and is deleted on
/// confirm.
final class CloseoutFormDraft {
  const CloseoutFormDraft({
    required this.eventId,
    this.confirmedExposure,
    this.note = '',
    this.lines = const [],
  });

  final String eventId;
  final int? confirmedExposure;
  final String note;
  final List<CloseoutFormLine> lines;
}

/// One worksheet line. All quantities optional while drafting; a skipped
/// line records nothing on confirm.
final class CloseoutFormLine {
  const CloseoutFormLine({
    required this.itemId,
    this.loaded,
    this.returned,
    this.waste,
    this.depletion,
    this.stockout = false,
    this.approximate = false,
    this.skipped = false,
  });

  final String itemId;
  final Quantity? loaded;
  final Quantity? returned;
  final Quantity? waste;
  final Quantity? depletion;
  final bool stockout;
  final bool approximate;
  final bool skipped;
}

/// Draft payload codec, version-tagged for forward compatibility.
String encodeCloseoutFormDraft(CloseoutFormDraft draft) => jsonEncode({
  'v': 1,
  'event_id': draft.eventId,
  'confirmed_exposure': draft.confirmedExposure,
  'note': draft.note,
  'lines': [
    for (final line in draft.lines)
      {
        'item_id': line.itemId,
        'loaded_micros': line.loaded?.micros,
        'returned_micros': line.returned?.micros,
        'waste_micros': line.waste?.micros,
        'depletion_micros': line.depletion?.micros,
        'stockout': line.stockout,
        'approximate': line.approximate,
        'skipped': line.skipped,
      },
  ],
});

CloseoutFormDraft decodeCloseoutFormDraft(String payloadJson) {
  final map = jsonDecode(payloadJson) as Map<String, dynamic>;
  Quantity? quantity(Object? micros) =>
      micros == null ? null : Quantity.fromMicros(micros as int);
  return CloseoutFormDraft(
    eventId: map['event_id'] as String,
    confirmedExposure: map['confirmed_exposure'] as int?,
    note: map['note'] as String? ?? '',
    lines: [
      for (final raw in map['lines'] as List<dynamic>)
        CloseoutFormLine(
          itemId: (raw as Map<String, dynamic>)['item_id'] as String,
          loaded: quantity(raw['loaded_micros']),
          returned: quantity(raw['returned_micros']),
          waste: quantity(raw['waste_micros']),
          depletion: quantity(raw['depletion_micros']),
          stockout: raw['stockout'] as bool? ?? false,
          approximate: raw['approximate'] as bool? ?? false,
          skipped: raw['skipped'] as bool? ?? false,
        ),
    ],
  );
}
