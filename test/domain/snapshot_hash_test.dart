/// §11.1 family E: canonical-encoding determinism, sensitivity to every
/// material field, insensitivity to identifiers the encoding excludes, and
/// a golden vector pinning the exact 64-hex digest against
/// canonicalization drift.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/forecasting/domain/snapshot.dart';
import 'package:loadout/features/forecasting/domain/snapshot_inputs.dart';

String pad(String seed) => seed.padRight(26, '0');

EvidenceInput evidence({
  String closeoutId = 'CLOSEB1',
  String sourceEventId = 'EVENTB1',
  int exposure = 120,
  int depletionMicros = 30000000,
  bool stockout = true,
  bool approximate = false,
}) => EvidenceInput(
  closeoutId: pad(closeoutId),
  sourceEventId: pad(sourceEventId),
  exposure: exposure,
  depletionMicros: depletionMicros,
  stockout: stockout,
  approximate: approximate,
);

SnapshotLineInput lineA({int onHand = 5000000, int packSize = 1000000}) =>
    SnapshotLineInput(
      itemId: pad('ITEMA'),
      packSizeMicros: packSize,
      onHandMicros: onHand,
      evidence: const [],
    );

SnapshotLineInput lineB({List<EvidenceInput>? evidenceRows}) =>
    SnapshotLineInput(
      itemId: pad('ITEMB'),
      packSizeMicros: 12000000,
      onHandMicros: -2500000,
      evidence:
          evidenceRows ??
          [
            evidence(),
            evidence(
              closeoutId: 'CLOSEB2',
              sourceEventId: 'EVENTB2',
              exposure: 90,
              depletionMicros: 22000000,
              stockout: false,
              approximate: true,
            ),
          ],
    );

SnapshotInputs inputs({
  PlanningPolicy policy = PlanningPolicy.balanced,
  int exposure = 150,
  int window = 12,
  List<SnapshotLineInput>? lines,
}) => SnapshotInputs(
  policy: policy,
  upcomingExposure: exposure,
  historyWindow: window,
  lines: lines ?? [lineB(), lineA()], // deliberately unsorted
);

void main() {
  group('canonical encoding', () {
    test('golden vector: fixed inputs → fixed 64-hex digest', () {
      // Recomputed independently (python hashlib) over the §6.6 encoding.
      expect(
        computeInputsHash(inputs()),
        '3036c390947674f5ece117a25e7b773a04e323fec74b7a65980e69736b140363',
      );
    });

    test('canonical text matches the §6.6 contract exactly', () {
      expect(
        canonicalInputs(inputs()),
        'direct_median|1|balanced|150|12'
        '\n${pad('ITEMA')}|1000000|5000000|0'
        '\n${pad('ITEMB')}|12000000|-2500000|0'
        ';${pad('CLOSEB1')}:120:30000000:1:0'
        ';${pad('CLOSEB2')}:90:22000000:0:1',
      );
    });

    test('line order is normalized by itemId regardless of construction '
        'order', () {
      final forward = inputs(lines: [lineA(), lineB()]);
      final reversed = inputs(lines: [lineB(), lineA()]);
      expect(computeInputsHash(forward), computeInputsHash(reversed));
    });

    test('evidence order is material (label-query order is frozen)', () {
      final swapped = inputs(
        lines: [
          lineA(),
          lineB(
            evidenceRows: [
              evidence(
                closeoutId: 'CLOSEB2',
                sourceEventId: 'EVENTB2',
                exposure: 90,
                depletionMicros: 22000000,
                stockout: false,
                approximate: true,
              ),
              evidence(),
            ],
          ),
        ],
      );
      expect(computeInputsHash(swapped), isNot(computeInputsHash(inputs())));
    });

    test('sensitive to every material field', () {
      final base = computeInputsHash(inputs());
      final variants = <String, SnapshotInputs>{
        'policy': inputs(policy: PlanningPolicy.cautious),
        'exposure': inputs(exposure: 151),
        'window': inputs(window: 11),
        'onHand one micro': inputs(lines: [lineA(onHand: 5000001), lineB()]),
        'packSize': inputs(lines: [lineA(packSize: 1000001), lineB()]),
        'evidence id': inputs(
          lines: [
            lineA(),
            lineB(evidenceRows: [evidence(closeoutId: 'CLOSEX1')]),
          ],
        ),
        'evidence exposure': inputs(
          lines: [
            lineA(),
            lineB(evidenceRows: [evidence(exposure: 121)]),
          ],
        ),
        'evidence depletion': inputs(
          lines: [
            lineA(),
            lineB(evidenceRows: [evidence(depletionMicros: 30000001)]),
          ],
        ),
        'evidence stockout flag': inputs(
          lines: [
            lineA(),
            lineB(evidenceRows: [evidence(stockout: false)]),
          ],
        ),
        'evidence approximate flag': inputs(
          lines: [
            lineA(),
            lineB(evidenceRows: [evidence(approximate: true)]),
          ],
        ),
      };
      for (final entry in variants.entries) {
        expect(
          computeInputsHash(entry.value),
          isNot(base),
          reason: 'hash must be sensitive to ${entry.key}',
        );
      }
    });

    test('insensitive to snapshot/command ids, timestamps, and assumptions '
        'copy', () {
      // The encoding is derived from SnapshotInputs only: two drafts that
      // differ in eventId and assumptionsJson still embed identical inputs.
      final draft1 = ForecastSnapshotDraft(
        eventId: EventId(pad('EVENT1')),
        policy: PlanningPolicy.balanced,
        upcomingExposure: 150,
        historyWindow: 12,
        inputsHash: 'x' * 64,
        assumptionsJson: '{"reserve_percent":10}',
        lines: [
          ForecastSnapshotLineDraft(
            itemId: ItemId(pad('ITEMA')),
            packSizeMicros: 1000000,
            onHandMicros: 5000000,
            evidenceGrade: EvidenceGrade.insufficientData,
          ),
        ],
      );
      final draft2 = ForecastSnapshotDraft(
        eventId: EventId(pad('EVENT2')),
        policy: PlanningPolicy.balanced,
        upcomingExposure: 150,
        historyWindow: 12,
        inputsHash: 'y' * 64,
        assumptionsJson: '{"reserve_percent":10,"history_window":12}',
        lines: [
          ForecastSnapshotLineDraft(
            itemId: ItemId(pad('ITEMA')),
            packSizeMicros: 1000000,
            onHandMicros: 5000000,
            evidenceGrade: EvidenceGrade.insufficientData,
          ),
        ],
      );
      expect(
        computeInputsHash(draft1.inputs),
        computeInputsHash(draft2.inputs),
      );
    });
  });
}
