/// §11.1: the sell-out adjustment applied to observations on the way INTO
/// the frozen engine. A day that ran out is a lower bound on demand, so it
/// may raise the estimate and must never lower it. Exact integer arithmetic
/// throughout; the monotonicity claim is proven as a property over a seeded
/// deterministic RNG rather than asserted in prose.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/forecasting/application/stockout_adjustment.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';

void main() {
  /// One confirmed outcome: [attendance] people, [units] whole things gone.
  ConfirmedObservation day(
    int attendance,
    int units, {
    bool ranOut = false,
    bool approximate = false,
  }) => ConfirmedObservation(
    exposure: attendance,
    depletion: Quantity.whole(units),
    stockout: ranOut,
    approximate: approximate,
  );

  List<int> depletions(StockoutAdjustment a) => [
    for (final o in a.observations) o.depletion.micros,
  ];

  group('nothing to fix', () {
    test('no sell-out days leaves every observation exactly as it was', () {
      final raw = [day(100, 60), day(90, 50), day(120, 70)];
      final adjustment = adjustForSellouts(raw);
      expect(adjustment.kind, StockoutAdjustmentKind.none);
      expect(adjustment.adjusted, isFalse);
      expect(adjustment.warning, isNull);
      expect(adjustment.selloutCount, 0);
      expect(depletions(adjustment), [60000000, 50000000, 70000000]);
    });

    test('an empty history is left alone', () {
      final adjustment = adjustForSellouts(const []);
      expect(adjustment.kind, StockoutAdjustmentKind.none);
      expect(adjustment.observations, isEmpty);
      expect(adjustment.observationCount, 0);
    });

    test('observations the engine ignores are not counted or touched', () {
      // The engine drops exposure <= 0 before it does any arithmetic.
      final raw = [day(0, 99, ranOut: true), day(100, 50)];
      final adjustment = adjustForSellouts(raw);
      expect(adjustment.observationCount, 1);
      expect(adjustment.kind, StockoutAdjustmentKind.none);
      expect(depletions(adjustment), [99000000, 50000000]);
    });
  });

  group('a sell-out can only raise the estimate', () {
    // 100 people and 60 sold; 100 people and 50 sold; 100 people, 40 sold and
    // ran out. The median of the two full days is 55 per 100, so the sell-out
    // day is treated as at least 55 — not the 40 that was all we could see.
    final scenario = [day(100, 60), day(100, 50), day(100, 40, ranOut: true)];

    test('a sell-out below the typical rate is raised to it', () {
      final adjustment = adjustForSellouts(scenario);
      expect(adjustment.kind, StockoutAdjustmentKind.liftedToTypical);
      expect(adjustment.selloutCount, 1);
      expect(depletions(adjustment), [60000000, 50000000, 55000000]);
    });

    test('the days that did not sell out are never touched', () {
      final adjustment = adjustForSellouts(scenario);
      expect(adjustment.observations[0].depletion, Quantity.whole(60));
      expect(adjustment.observations[1].depletion, Quantity.whole(50));
      // Flags survive the lift, so the stored reason stays legible.
      expect(adjustment.observations[2].stockout, isTrue);
    });

    test('a sell-out that already beat the typical rate keeps its own '
        'bigger number', () {
      final adjustment = adjustForSellouts([
        day(100, 60),
        day(100, 50),
        day(100, 80, ranOut: true),
      ]);
      expect(depletions(adjustment).last, 80000000, reason: 'never lowered');
    });

    test('the lift is scaled to each day’s own attendance', () {
      // Typical rate is 55 per 100 people; the sell-out day only had 40
      // people, so it is credited with ceil(55 × 40 ÷ 100) = 22.
      final adjustment = adjustForSellouts([
        day(100, 60),
        day(100, 50),
        day(40, 5, ranOut: true),
      ]);
      expect(depletions(adjustment).last, 22000000);
    });

    test('the whole point: the forecast goes UP, not down', () {
      const engine = DeterministicForecastEngine();
      ForecastLine run(List<ConfirmedObservation> observations) =>
          engine.forecastDirect(
            upcomingExposure: 100,
            observations: observations,
            policy: PlanningPolicy.lean,
            packSize: Quantity.one,
            usableOnHand: Quantity.zero,
          );
      expect(run(scenario).expectedUse, Quantity.whole(50));
      expect(
        run(adjustForSellouts(scenario).observations).expectedUse,
        Quantity.whole(55),
      );
    });
  });

  group('every day sold out', () {
    test('the busiest day is used for all of them', () {
      final adjustment = adjustForSellouts([
        day(100, 40, ranOut: true),
        day(100, 30, ranOut: true),
        day(100, 20, ranOut: true),
      ]);
      expect(adjustment.kind, StockoutAdjustmentKind.everyDaySoldOut);
      expect(adjustment.selloutCount, 3);
      expect(depletions(adjustment), [40000000, 40000000, 40000000]);
    });

    test('the estimate lands on the largest observed rate', () {
      const engine = DeterministicForecastEngine();
      final raw = [
        day(100, 40, ranOut: true),
        day(50, 25, ranOut: true), // the busiest: 50 per 100 people
        day(100, 20, ranOut: true),
      ];
      final line = engine.forecastDirect(
        upcomingExposure: 100,
        observations: adjustForSellouts(raw).observations,
        policy: PlanningPolicy.lean,
        packSize: Quantity.one,
        usableOnHand: Quantity.zero,
      );
      expect(line.expectedUse, Quantity.whole(50));
    });

    test('one sell-out day and nothing else invents no number — it only '
        'says so', () {
      final adjustment = adjustForSellouts([day(100, 40, ranOut: true)]);
      expect(adjustment.kind, StockoutAdjustmentKind.everyDaySoldOut);
      expect(depletions(adjustment), [
        40000000,
      ], reason: 'there is nothing to raise it to');
      expect(adjustment.warning, contains('probably higher'));
    });
  });

  group('what the owner is told', () {
    test('names the days that ran out, in plain language', () {
      final warning = adjustForSellouts([
        day(100, 60),
        day(100, 40, ranOut: true),
        day(100, 30, ranOut: true),
      ]).warning!;
      expect(
        warning,
        'You ran out on 2 of these days, so demand was probably higher '
        'than recorded — this allows for that.',
      );
    });

    test('says outright that the number is unknown when nothing was ever '
        'seen through to the end', () {
      final warning = adjustForSellouts([
        day(100, 40, ranOut: true),
        day(100, 30, ranOut: true),
      ]).warning!;
      expect(warning, contains('ran out every time'));
      expect(warning, contains('unknown and probably higher'));
    });

    test('no jargon reaches the owner', () {
      for (final kind in StockoutAdjustmentKind.values) {
        final warning = selloutWarning(kind, selloutCount: 2) ?? '';
        for (final jargon in const [
          'censor',
          'quantile',
          'median',
          'bound',
          'estimator',
          'bias',
        ]) {
          expect(
            warning.toLowerCase(),
            isNot(contains(jargon)),
            reason: '"$jargon" in: $warning',
          );
        }
      }
    });

    test('the stored rule note explains the arithmetic for later', () {
      expect(selloutRuleTag, 'sellouts_raise_never_lower');
      expect(selloutRuleNote, contains('never'));
      expect(selloutRuleNote, contains('busiest day'));
    });
  });

  group('property: the adjustment is monotone (seeded RNG)', () {
    const engine = DeterministicForecastEngine();
    const policies = PlanningPolicy.values;

    test('an adjusted forecast is never below the unadjusted one', () {
      final rng = Random(20260812);
      var raised = 0;
      for (var trial = 0; trial < 2000; trial++) {
        final count = 1 + rng.nextInt(7);
        final raw = [
          for (var i = 0; i < count; i++)
            ConfirmedObservation(
              exposure: 1 + rng.nextInt(600),
              depletion: Quantity.fromMicros(
                rng.nextInt(300) * Quantity.scale + rng.nextInt(Quantity.scale),
              ),
              stockout: rng.nextBool(),
            ),
        ];
        final upcoming = 1 + rng.nextInt(600);
        final policy = policies[rng.nextInt(policies.length)];
        final packSize = Quantity.whole(1 + rng.nextInt(12));
        ForecastLine run(List<ConfirmedObservation> observations) =>
            engine.forecastDirect(
              upcomingExposure: upcoming,
              observations: observations,
              policy: policy,
              packSize: packSize,
              usableOnHand: Quantity.zero,
            );

        final before = run(raw);
        final adjustment = adjustForSellouts(raw);
        final after = run(adjustment.observations);

        expect(
          after.expectedUse!.micros,
          greaterThanOrEqualTo(before.expectedUse!.micros),
          reason: 'trial $trial lowered the estimate',
        );
        expect(
          after.roundedLoadQuantity!.micros,
          greaterThanOrEqualTo(before.roundedLoadQuantity!.micros),
          reason: 'trial $trial lowered the load',
        );
        expect(after.evidenceGrade, before.evidenceGrade);
        if (after.expectedUse!.micros > before.expectedUse!.micros) raised++;
      }
      expect(
        raised,
        greaterThan(100),
        reason: 'a run where nothing is ever raised proves nothing',
      );
    });

    test('every observation only ever grows, and full days never move', () {
      final rng = Random(4242);
      for (var trial = 0; trial < 2000; trial++) {
        final count = 1 + rng.nextInt(7);
        final raw = [
          for (var i = 0; i < count; i++)
            ConfirmedObservation(
              exposure: 1 + rng.nextInt(600),
              depletion: Quantity.fromMicros(
                rng.nextInt(300) * Quantity.scale + rng.nextInt(Quantity.scale),
              ),
              stockout: rng.nextBool(),
              approximate: rng.nextBool(),
            ),
        ];
        final adjusted = adjustForSellouts(raw).observations;
        expect(adjusted, hasLength(raw.length));
        for (var i = 0; i < raw.length; i++) {
          expect(
            adjusted[i].depletion.micros,
            greaterThanOrEqualTo(raw[i].depletion.micros),
            reason: 'trial $trial observation $i shrank',
          );
          expect(adjusted[i].exposure, raw[i].exposure);
          expect(adjusted[i].stockout, raw[i].stockout);
          expect(adjusted[i].approximate, raw[i].approximate);
          if (!raw[i].stockout) {
            expect(
              adjusted[i].depletion.micros,
              raw[i].depletion.micros,
              reason: 'trial $trial moved a day that did not sell out',
            );
          }
        }
      }
    });

    test('no sell-out day is left below the typical rate', () {
      final rng = Random(777);
      for (var trial = 0; trial < 2000; trial++) {
        final count = 1 + rng.nextInt(7);
        final raw = [
          for (var i = 0; i < count; i++)
            ConfirmedObservation(
              exposure: 1 + rng.nextInt(600),
              depletion: Quantity.fromMicros(
                rng.nextInt(300) * Quantity.scale + rng.nextInt(Quantity.scale),
              ),
              stockout: rng.nextBool(),
            ),
        ];
        final adjustment = adjustForSellouts(raw);
        final floor = adjustment.floorRateMicros;
        if (floor == null) continue;
        for (final o in adjustment.observations) {
          if (!o.stockout) continue;
          expect(
            rateOf(o),
            greaterThanOrEqualTo(floor),
            reason: 'trial $trial left a sell-out below the floor rate',
          );
        }
      }
    });
  });
}
