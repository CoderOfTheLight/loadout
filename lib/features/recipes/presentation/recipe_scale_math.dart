/// "Scale to event" arithmetic — pure, exact, integer micros only.
///
/// Batches needed = ceil(need ÷ yield), where NEED is the amount the
/// event's stored packing list says to bring for the recipe's output item
/// (the effective load: override wins, baseline fills in) and YIELD is the
/// current revision's per-batch yield. The rounding is said out loud —
/// "Needs 2.2 batches → make 3 — about 8 spare portions" — exactly as the
/// proposal promised, because the person doing this math at 6 a.m. should
/// not have to check it on a phone calculator.
library;

import '../../../core/errors.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../../core/unit_ratio.dart';

/// The whole-batch plan for one (need, yield) pair. All fields exact.
final class RecipeBatchPlan {
  RecipeBatchPlan({required this.needMicros, required this.yieldMicros})
    : assert(needMicros >= 0, 'need must be nonnegative'),
      assert(yieldMicros > 0, 'yield must be positive'),
      batches = needMicros == 0
          ? 0
          : (needMicros + yieldMicros - 1) ~/ yieldMicros;

  /// Micros of the output item the packing list says to bring.
  final int needMicros;

  /// Micros one batch makes (the revision's yield; > 0 by form validation).
  final int yieldMicros;

  /// Whole batches to make: `ceil(need / yield)`, 0 when nothing is needed.
  final int batches;

  /// What the whole batches make beyond the need. `batches × yield − need`;
  /// bounded by `yield`, so no overflow is reachable inside the quantity
  /// envelope.
  int get spareMicros => batches * yieldMicros - needMicros;

  /// The rounding, said out loud. Exact-decimal batch counts print as-is
  /// ("Needs 2.2 batches"); anything beyond one decimal is honestly
  /// "about". Spare is always "about" — the need itself is a forecast.
  String get verdict {
    if (needMicros == 0) {
      return 'The packing list says none are needed — no batches.';
    }
    if (needMicros % yieldMicros == 0) {
      final word = batches == 1 ? 'batch' : 'batches';
      return 'Needs $batches $word → make $batches — nothing spare';
    }
    // One-decimal batch count by integer math: need ≤ 1e15 micros, so
    // need × 10 stays far inside int64.
    final tenths = (needMicros * 10) ~/ yieldMicros;
    final exact = (needMicros * 10) % yieldMicros == 0;
    final decimal = '${tenths ~/ 10}.${tenths % 10}';
    // Spare is `batches × yield − need`, and `need` came off a forecast —
    // so it carries the engine's micros residue. Display-rounded (§ counted
    // goods): "about 0.3 spare portions", never "about 0.299999".
    final spare = QuantityCodec.formatDisplayMicros(spareMicros);
    return 'Needs ${exact ? decimal : 'about $decimal'} batches '
        '→ make $batches — about $spare spare portions';
  }
}

/// Per-ingredient total for [batches] whole batches: `perBatch × batches`,
/// exact (BigInt-checked); `'—'` if the total would leave the quantity
/// envelope — an honest dash beats a wrapped number.
String scaledIngredientTotal(Quantity perBatch, int batches) {
  if (batches == 0) return '0';
  try {
    return QuantityCodec.format(UnitRatio(batches, 1).applyCeil(perBatch));
  } on QuantityOverflowError {
    return '—';
  }
}
