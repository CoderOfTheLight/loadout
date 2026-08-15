/// The per-event seam (v3): mapping confirmed observations to exposure 1
/// makes the FROZEN engine's median-of-rates the median of per-event
/// depletions — no engine arithmetic changes — and the int64 headroom that
/// makes exposure 1 safe is pinned here with the exact envelope numbers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/forecasting/application/per_event_basis.dart';
import 'package:loadout/features/forecasting/application/stockout_adjustment.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';

ConfirmedObservation obs(
  int exposure,
  int depletionMicros, {
  bool stockout = false,
}) => ConfirmedObservation(
  exposure: exposure,
  depletion: Quantity.fromMicros(depletionMicros),
  stockout: stockout,
);

void main() {
  const engine = DeterministicForecastEngine();

  group('perEventObservations', () {
    test(
      'maps every usable observation to exposure 1, depletion untouched',
      () {
        final mapped = perEventObservations([
          obs(200, 2000000),
          obs(350, 3000000, stockout: true),
        ]);
        expect([for (final o in mapped) o.exposure], [1, 1]);
        expect(
          [for (final o in mapped) o.depletion.micros],
          [2000000, 3000000],
        );
        expect([for (final o in mapped) o.stockout], [false, true]);
      },
    );

    test('passes non-positive exposures through for the engine to ignore', () {
      final mapped = perEventObservations([obs(0, 5000000)]);
      expect(mapped.single.exposure, 0);
    });
  });

  group('median-of-depletions falls out of the frozen median-of-rates', () {
    test('attendance differences change nothing: 2, 2, 3 used → median 2', () {
      final line = engine.forecastDirect(
        upcomingExposure: perEventEngineExposure,
        observations: perEventObservations([
          obs(150, 2000000),
          obs(200, 2000000),
          obs(900, 3000000),
        ]),
        policy: PlanningPolicy.lean,
        packSize: Quantity.one,
        usableOnHand: Quantity.zero,
      );
      expect(line.expectedUse!.micros, 2000000);
      expect(line.evidenceGrade, EvidenceGrade.observedRange);
      expect(
        line.warnings,
        isEmpty,
        reason: 'exposure 1 vs observed 1s: never "outside the range"',
      );
    });

    test('even count: floored mean of the two middle depletions', () {
      final line = engine.forecastDirect(
        upcomingExposure: perEventEngineExposure,
        observations: perEventObservations([
          obs(100, 1000000),
          obs(700, 3000001),
        ]),
        policy: PlanningPolicy.lean,
        packSize: Quantity.one,
        usableOnHand: Quantity.zero,
      );
      // Rates are depletion × 1e6; their floored mean back through ÷ 1e6
      // (ceil) is exactly the engine's own paired median.
      expect(line.expectedUse!.micros, 2000001);
    });

    test('a ran-out day is lifted to the median PER-EVENT usage, not to an '
        'attendance-relative rate', () {
      // Mapped first, adjusted second: the sell-out day (only 1 used — ran
      // out early) rises to the median of the steady days' depletions (2).
      final adjustment = adjustForSellouts(
        perEventObservations([
          obs(200, 2000000),
          obs(220, 2000000),
          obs(1000, 1000000, stockout: true),
        ]),
      );
      expect(adjustment.adjusted, isTrue);
      expect(
        [for (final o in adjustment.observations) o.depletion.micros],
        [2000000, 2000000, 2000000],
      );
    });
  });

  group('int64 headroom at exposure 1 — the envelope numbers, exactly', () {
    test(
      'rate of the largest legal depletion is exactly 1e18 and survives',
      () {
        // Depletion is schema-capped at 1e12 micros; at exposure 1 the
        // engine's rate is depletion × 1e6 ÷ 1 = 1e18 < 2^63−1 ≈ 9.22e18.
        const maxDepletionMicros = 1000000000000; // 1e12, the schema cap
        expect(rateOf(obs(1, maxDepletionMicros)), 1000000000000000000); // 1e18

        final line = engine.forecastDirect(
          upcomingExposure: perEventEngineExposure,
          observations: perEventObservations([obs(999999, maxDepletionMicros)]),
          policy: PlanningPolicy.lean,
          packSize: Quantity.one,
          usableOnHand: Quantity.zero,
        );
        expect(
          line.expectedUse!.micros,
          maxDepletionMicros,
          reason: 'median rate × 1 ÷ 1e6 hands the depletion straight back',
        );
      },
    );

    test('the even-count paired median sums two 1e18 rates: 2e18, no wrap', () {
      const maxDepletionMicros = 1000000000000;
      final sorted = [
        rateOf(obs(1, maxDepletionMicros)),
        rateOf(obs(1, maxDepletionMicros)),
      ];
      expect(sorted[0] + sorted[1], 2000000000000000000); // 2e18 — no wrap
      expect(medianOfSortedRates(sorted), 1000000000000000000);

      final line = engine.forecastDirect(
        upcomingExposure: perEventEngineExposure,
        observations: perEventObservations([
          obs(1, maxDepletionMicros),
          obs(1000000, maxDepletionMicros),
        ]),
        policy: PlanningPolicy.lean,
        packSize: Quantity.one,
        usableOnHand: Quantity.zero,
      );
      expect(line.expectedUse!.micros, maxDepletionMicros);
    });
  });

  group('the supplies-jump rule — warning only, never arithmetic', () {
    test('fires strictly above 2× the largest observed exposure', () {
      expect(
        perEventSuppliesJump(
          upcomingExposure: 500,
          observedExposures: const [100, 100, 100],
        ),
        isTrue,
        reason: 'the literal owner-approved case: learned at 100, event 500',
      );
      expect(
        perEventSuppliesJump(
          upcomingExposure: 200,
          observedExposures: const [100],
        ),
        isFalse,
        reason: 'exactly 2× is still the learned range',
      );
      expect(
        perEventSuppliesJump(
          upcomingExposure: 201,
          observedExposures: const [100],
        ),
        isTrue,
      );
      expect(
        perEventSuppliesJump(
          upcomingExposure: 500,
          observedExposures: const [100, 300],
        ),
        isFalse,
        reason: 'the LARGEST observed exposure sets the range',
      );
    });

    test('no evidence means no learned range — never fires', () {
      expect(
        perEventSuppliesJump(
          upcomingExposure: 500,
          observedExposures: const [],
        ),
        isFalse,
      );
    });

    test('the stored copy is the owner-approved sentence', () {
      expect(
        perEventSuppliesJumpWarning,
        'This estimate comes from much smaller events — bring more than '
        'usual and count what you use.',
      );
    });
  });

  test('the assumptions tag and note exist for stored snapshots', () {
    expect(perEventRuleTag, 'per_event_median_exposure_1');
    expect(perEventRuleNote, contains('attendance is ignored'));
  });
}
