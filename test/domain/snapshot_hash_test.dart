/// §11.1 family E: canonical-encoding determinism, sensitivity to every
/// material field, insensitivity to identifiers the encoding excludes, and
/// a golden vector pinning the exact 64-hex digest against
/// canonicalization drift.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
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
      // Moved with the method version: v2 treats sell-out days as a lower
      // bound, v3 forecasts per_event items from per-event usage — each
      // change produces different outputs from the same inputs and the hash
      // has to say so.
      expect(
        computeInputsHash(inputs()),
        '33b72f6caa68d613a5ab49b0ec2dfc11b1c2af88bc63183ed3211ede67a4ea48',
      );
    });

    test('the encoding is tagged with the current method version', () {
      // v3: per_event items are forecast from the median of per-event usage.
      expect(forecastMethodVersion, 3);
      expect(canonicalInputs(inputs()), startsWith('direct_median|3|'));
    });

    test('canonical text matches the §6.6 contract exactly', () {
      expect(
        canonicalInputs(inputs()),
        'direct_median|3|balanced|150|12'
        '\n${pad('ITEMA')}|1000000|5000000|0'
        '\n${pad('ITEMB')}|12000000|-2500000|0'
        ';${pad('CLOSEB1')}:120:30000000:1:0'
        ';${pad('CLOSEB2')}:90:22000000:0:1',
      );
    });

    test('v3 fields are appended only when material, in fixed order', () {
      final line = SnapshotLineInput(
        itemId: pad('ITEMA'),
        packSizeMicros: 1000000,
        onHandMicros: 0,
        demandBasis: DemandBasis.perEvent,
        perEventBaselineMicros: 2000000,
        evidence: const [],
      );
      expect(
        canonicalInputs(inputs(lines: [line])),
        'direct_median|3|balanced|150|12'
        '\n${pad('ITEMA')}|1000000|0|0|b=per_event|pe=2000000',
      );
      final ratioLine = SnapshotLineInput(
        itemId: pad('ITEMA'),
        packSizeMicros: 1000000,
        onHandMicros: 0,
        perPersonNumerator: 3,
        perPersonDenominator: 1,
        evidence: const [],
      );
      expect(
        canonicalInputs(inputs(lines: [ratioLine])),
        'direct_median|3|balanced|150|12'
        '\n${pad('ITEMA')}|1000000|0|0|r=3/1',
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
        'demand basis (v3)': inputs(
          lines: [
            SnapshotLineInput(
              itemId: pad('ITEMA'),
              packSizeMicros: 1000000,
              onHandMicros: 5000000,
              demandBasis: DemandBasis.perEvent,
              evidence: const [],
            ),
            lineB(),
          ],
        ),
        'per-event baseline (v3)': inputs(
          lines: [
            SnapshotLineInput(
              itemId: pad('ITEMA'),
              packSizeMicros: 1000000,
              onHandMicros: 5000000,
              demandBasis: DemandBasis.perEvent,
              perEventBaselineMicros: 2000000,
              evidence: const [],
            ),
            lineB(),
          ],
        ),
        'per-person ratio (v3)': inputs(
          lines: [
            SnapshotLineInput(
              itemId: pad('ITEMA'),
              packSizeMicros: 1000000,
              onHandMicros: 5000000,
              perPersonNumerator: 3,
              perPersonDenominator: 1,
              evidence: const [],
            ),
            lineB(),
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
