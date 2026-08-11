import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';

void main() {
  const engine = DeterministicForecastEngine();

  test('zero history is unknown rather than zero', () {
    final result = engine.forecastDirect(
      upcomingExposure: 100,
      observations: [],
      policy: PlanningPolicy.balanced,
      packSize: Quantity.whole(24),
      usableOnHand: Quantity.zero,
    );
    expect(result.evidenceGrade, EvidenceGrade.insufficientData);
    expect(result.expectedUse, isNull);
  });

  test('scales outcome, reserves, rounds packs, and subtracts stock', () {
    final result = engine.forecastDirect(
      upcomingExposure: 150,
      observations: [
        ConfirmedObservation(exposure: 100, depletion: Quantity.whole(20)),
      ],
      policy: PlanningPolicy.balanced,
      packSize: Quantity.whole(12),
      usableOnHand: Quantity.whole(10),
      confirmedInbound: Quantity.whole(2),
    );
    expect(result.expectedUse, Quantity.whole(30));
    expect(result.plannedQuantity, Quantity.whole(33));
    expect(result.roundedLoadQuantity, Quantity.whole(36));
    expect(result.acquireQuantity, Quantity.whole(24));
    expect(result.warnings, isNotEmpty);
  });

  test('uses median normalized rate and surfaces trust warnings', () {
    final result = engine.forecastDirect(
      upcomingExposure: 100,
      observations: [
        ConfirmedObservation(exposure: 100, depletion: Quantity.whole(10)),
        ConfirmedObservation(
          exposure: 100,
          depletion: Quantity.whole(30),
          stockout: true,
        ),
        ConfirmedObservation(
          exposure: 100,
          depletion: Quantity.whole(20),
          approximate: true,
        ),
      ],
      policy: PlanningPolicy.lean,
      packSize: Quantity.whole(1),
      usableOnHand: Quantity.zero,
    );
    expect(result.expectedUse, Quantity.whole(20));
    expect(result.warnings, hasLength(2));
  });
}
