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
}
