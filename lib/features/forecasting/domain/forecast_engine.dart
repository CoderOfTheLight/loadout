import '../../../core/quantity.dart';

enum PlanningPolicy {
  lean(0),
  balanced(10),
  cautious(20);

  const PlanningPolicy(this.reservePercent);
  final int reservePercent;
}

enum EvidenceGrade { insufficientData, singleEvent, observedRange }

final class ConfirmedObservation {
  const ConfirmedObservation({
    required this.exposure,
    required this.depletion,
    this.stockout = false,
    this.approximate = false,
  });
  final int exposure;
  final Quantity depletion;
  final bool stockout;
  final bool approximate;
}

final class ForecastLine {
  const ForecastLine({
    required this.expectedUse,
    required this.plannedQuantity,
    required this.roundedLoadQuantity,
    required this.acquireQuantity,
    required this.evidenceGrade,
    required this.warnings,
  });
  final Quantity? expectedUse;
  final Quantity? plannedQuantity;
  final Quantity? roundedLoadQuantity;
  final Quantity? acquireQuantity;
  final EvidenceGrade evidenceGrade;
  final List<String> warnings;
}

abstract interface class ForecastEngine {
  ForecastLine forecastDirect({
    required int upcomingExposure,
    required List<ConfirmedObservation> observations,
    required PlanningPolicy policy,
    required Quantity packSize,
    required Quantity usableOnHand,
    Quantity confirmedInbound = Quantity.zero,
  });
}

final class DeterministicForecastEngine implements ForecastEngine {
  const DeterministicForecastEngine();

  @override
  ForecastLine forecastDirect({
    required int upcomingExposure,
    required List<ConfirmedObservation> observations,
    required PlanningPolicy policy,
    required Quantity packSize,
    required Quantity usableOnHand,
    Quantity confirmedInbound = Quantity.zero,
  }) {
    if (upcomingExposure <= 0) throw ArgumentError('exposure must be positive');
    final valid = observations.where((o) => o.exposure > 0).toList();
    if (valid.isEmpty) {
      return const ForecastLine(
        expectedUse: null,
        plannedQuantity: null,
        roundedLoadQuantity: null,
        acquireQuantity: null,
        evidenceGrade: EvidenceGrade.insufficientData,
        warnings: ['No comparable confirmed outcomes. Create a baseline plan.'],
      );
    }
    final rates =
        valid
            .map((o) => (o.depletion.micros * Quantity.scale) ~/ o.exposure)
            .toList()
          ..sort();
    final medianRate = rates.length.isOdd
        ? rates[rates.length ~/ 2]
        : (rates[rates.length ~/ 2 - 1] + rates[rates.length ~/ 2]) ~/ 2;
    final expected = Quantity.fromMicros(
      (medianRate * upcomingExposure + Quantity.scale - 1) ~/ Quantity.scale,
    );
    final planned = expected.multiplyRatio(100 + policy.reservePercent, 100);
    final load = planned.roundUpTo(packSize);
    final available = Quantity.fromMicros(
      usableOnHand.micros + confirmedInbound.micros,
    );
    final warnings = <String>[];
    final exposures = valid.map((o) => o.exposure);
    if (upcomingExposure < exposures.reduce((a, b) => a < b ? a : b) ||
        upcomingExposure > exposures.reduce((a, b) => a > b ? a : b)) {
      warnings.add('Upcoming exposure is outside the observed range.');
    }
    if (valid.any((o) => o.stockout)) {
      warnings.add('History includes lower-bound stockout demand.');
    }
    if (valid.any((o) => o.approximate)) {
      warnings.add('History includes approximate closeouts.');
    }
    return ForecastLine(
      expectedUse: expected,
      plannedQuantity: planned,
      roundedLoadQuantity: load,
      acquireQuantity: load.subtractFloor(available),
      evidenceGrade: valid.length == 1
          ? EvidenceGrade.singleEvent
          : EvidenceGrade.observedRange,
      warnings: List.unmodifiable(warnings),
    );
  }
}
