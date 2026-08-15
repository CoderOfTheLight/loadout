/// §11.1: the no-history "1 serves N" baseline. Pure integer arithmetic that
/// borrows the frozen engine's SHAPE (reserve percent, pack rounding,
/// acquire subtraction) without touching the engine or its history.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/forecasting/application/baseline_estimator.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';

void main() {
  BaselineEstimate? estimate({
    int attendance = 100,
    int? servesMicros = 4000000,
    PlanningPolicy policy = PlanningPolicy.balanced,
    int packSizeMicros = 1000000,
    int onHandMicros = 0,
    int inboundMicros = 0,
  }) => estimateFromServesPerUnit(
    expectedAttendance: attendance,
    servesPerUnitMicros: servesMicros,
    policy: policy,
    packSizeMicros: packSizeMicros,
    usableOnHandMicros: onHandMicros,
    confirmedInboundMicros: inboundMicros,
  );

  group('units needed', () {
    test('100 people, 1 serves 4 → 25 units, +10% reserve → 28', () {
      final result = estimate()!;
      expect(result.expectedUseMicros, 25000000);
      expect(result.plannedMicros, 27500000);
      expect(result.loadMicros, 28000000, reason: 'rounded up to whole things');
      expect(result.acquireMicros, 28000000);
    });

    test('a part serving rounds UP to a whole thing', () {
      // 101 ÷ 4 = 25.25 people-worth: you cannot bring a quarter pizza.
      expect(estimate(attendance: 101)!.expectedUseMicros, 26000000);
      expect(estimate(attendance: 99)!.expectedUseMicros, 25000000);
      expect(estimate(attendance: 1)!.expectedUseMicros, 1000000);
    });

    test('fractional serves-per-unit stays exact (2.5 people per unit)', () {
      final result = estimate(attendance: 100, servesMicros: 2500000)!;
      expect(result.expectedUseMicros, 40000000);
      expect(result.servesPerUnitMicros, 2500000);
    });
  });

  group('policy reserve — the engine percentages, unchanged', () {
    test('lean adds nothing, cautious adds 20%', () {
      expect(estimate(policy: PlanningPolicy.lean)!.plannedMicros, 25000000);
      expect(
        estimate(policy: PlanningPolicy.balanced)!.plannedMicros,
        27500000,
      );
      expect(
        estimate(policy: PlanningPolicy.cautious)!.plannedMicros,
        30000000,
      );
    });
  });

  group('pack rounding', () {
    test('rounds the planned quantity up to the pack size', () {
      // Legacy items may still carry a pack size other than one unit.
      final result = estimate(packSizeMicros: 12000000)!;
      expect(result.plannedMicros, 27500000);
      expect(result.loadMicros, 36000000, reason: '3 packs of 12');
    });
  });

  group('acquire', () {
    test('subtracts on-hand and confirmed inbound, floored at zero', () {
      expect(estimate(onHandMicros: 10000000)!.acquireMicros, 18000000);
      expect(
        estimate(onHandMicros: 20000000, inboundMicros: 5000000)!.acquireMicros,
        3000000,
      );
      expect(estimate(onHandMicros: 99000000)!.acquireMicros, 0);
    });

    test('a negative derived on-hand counts as zero, never as credit', () {
      expect(estimate(onHandMicros: -5000000)!.acquireMicros, 28000000);
    });
  });

  group('refuses to guess', () {
    test('no serves-per-unit means no baseline', () {
      expect(estimate(servesMicros: null), isNull);
    });

    test('nonsense inputs produce nothing rather than a number', () {
      expect(estimate(servesMicros: 0), isNull);
      expect(estimate(servesMicros: -1), isNull);
      expect(estimate(attendance: 0), isNull);
      expect(estimate(attendance: -3), isNull);
      expect(estimate(packSizeMicros: 0), isNull);
    });

    test('outside the exact-integer envelope it returns null, not a wrap', () {
      // One micro-person per unit against a full stadium needs 1e12 units —
      // past Quantity.maxMicros once scaled.
      expect(estimate(attendance: 1000000, servesMicros: 1), isNull);
      // Just inside the envelope still works and stays exact.
      final ok = estimate(attendance: 1000000, servesMicros: 1000000)!;
      expect(ok.expectedUseMicros, 1000000 * Quantity.scale);
    });
  });

  group('warning', () {
    test('names the assumption and denies it is a confirmed outcome', () {
      final warning = estimate()!.warning;
      expect(warning, contains('1 serves 4'));
      expect(warning, contains('Estimate only'));
      expect(warning, contains('not from confirmed outcomes'));
    });

    test('formats fractional serves without floating point', () {
      expect(formatServesPerUnit(4000000), '4');
      expect(formatServesPerUnit(2500000), '2.5');
      expect(formatServesPerUnit(1250000), '1.25');
      expect(formatServesPerUnit(1), '0.000001');
    });
  });

  // ------------------------------------------------- v3: "N per person"

  BaselineEstimate? ratioEstimate({
    int attendance = 200,
    int? numerator = 3,
    int? denominator = 1,
    PlanningPolicy policy = PlanningPolicy.lean,
    int packSizeMicros = 1000000,
    int onHandMicros = 0,
  }) => estimateFromPerPersonRatio(
    expectedAttendance: attendance,
    numerator: numerator,
    denominator: denominator,
    policy: policy,
    packSizeMicros: packSizeMicros,
    usableOnHandMicros: onHandMicros,
  );

  group('the flipped "N per person" ratio (v3)', () {
    test('200 people × 3 per person is EXACTLY 600 — never the reciprocal\'s '
        '601', () {
      final result = ratioEstimate()!;
      expect(result.expectedUseMicros, 600000000);
      expect(result.perPersonNumerator, 3);
      expect(result.perPersonDenominator, 1);
      expect(result.servesPerUnitMicros, isNull);
      expect(result.perEventMicros, isNull);
    });

    test('1 per 2 people rounds part-units up to whole things', () {
      // 101 people × 1/2 = 50.5 → 51 whole units.
      expect(
        ratioEstimate(
          attendance: 101,
          numerator: 1,
          denominator: 2,
        )!.expectedUseMicros,
        51000000,
      );
    });

    test('borrows the engine shape: reserve, pack rounding, acquire', () {
      final result = ratioEstimate(
        policy: PlanningPolicy.balanced,
        packSizeMicros: 12000000,
        onHandMicros: 40000000,
      )!;
      expect(result.plannedMicros, 660000000); // 600 +10 %
      expect(result.loadMicros, 660000000); // 55 packs of 12 exactly
      expect(result.acquireMicros, 620000000);
    });

    test('refuses to guess: missing or nonsense parts', () {
      expect(ratioEstimate(numerator: null), isNull);
      expect(ratioEstimate(denominator: null), isNull);
      expect(ratioEstimate(attendance: 0), isNull);
      expect(ratioEstimate(packSizeMicros: 0), isNull);
    });

    test('warning speaks the owner\'s phrasing', () {
      expect(ratioEstimate()!.warning, contains('3 per person'));
      expect(
        ratioEstimate(numerator: 1, denominator: 2)!.warning,
        contains('1 per 2 people'),
      );
      expect(formatPerPersonRatio(3, 4), '3 per 4 people');
    });
  });

  // ------------------------------------------------- v3: per-event

  group('the per-event "how many do you usually bring" (v3)', () {
    BaselineEstimate? perEvent({
      int? usualMicros = 2000000,
      PlanningPolicy policy = PlanningPolicy.balanced,
      int packSizeMicros = 1000000,
      int onHandMicros = 0,
    }) => estimateFromPerEventBaseline(
      perEventBaselineMicros: usualMicros,
      policy: policy,
      packSizeMicros: packSizeMicros,
      usableOnHandMicros: onHandMicros,
    );

    test('attendance plays no part: the usual amount plus the reserve', () {
      final result = perEvent()!;
      expect(result.perEventMicros, 2000000);
      expect(result.expectedUseMicros, 2000000);
      expect(result.plannedMicros, 2200000);
      expect(result.loadMicros, 3000000, reason: 'whole things');
      expect(result.acquireMicros, 3000000);
      expect(result.servesPerUnitMicros, isNull);
      expect(result.perPersonNumerator, isNull);
    });

    test('subtracts what is on hand', () {
      expect(perEvent(onHandMicros: 2000000)!.acquireMicros, 1000000);
    });

    test('refuses to guess without an answer', () {
      expect(perEvent(usualMicros: null), isNull);
      expect(perEvent(usualMicros: 0), isNull);
      expect(perEvent(packSizeMicros: 0), isNull);
    });

    test('warning names the usual amount and denies it is confirmed', () {
      final warning = perEvent()!.warning;
      expect(warning, contains('usual 2 per event'));
      expect(warning, contains('Estimate only'));
    });
  });
}
