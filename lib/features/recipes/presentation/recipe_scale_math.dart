/// "Scale to event" arithmetic — pure, exact, integer micros only.
///
/// Batches needed = ceil(need ÷ yield), where NEED is the amount the
/// event's stored packing list says to bring for the recipe's output item
/// (the effective load: override wins, baseline fills in) and YIELD is the
/// current revision's per-batch yield. The answer is one plain sentence —
/// "Make 3 batches. That's 30 — you need 22." — because the person doing
/// this math at 6 a.m. should not have to check it on a phone calculator,
/// and because a fractional batch count ("needs about 2.2 batches") is a
/// number nobody can cook. The instruction comes first; the two figures
/// that justify it follow in the same breath.
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

  /// What the whole batches make in total: `batches × yield`. Bounded by
  /// `need + yield`, so it stays inside the quantity envelope.
  int get madeMicros => batches * yieldMicros;

  /// The whole answer in one sentence: the instruction, then the two
  /// figures behind it. "Make 3 batches. That's 30 — you need 22."
  ///
  /// Both figures are display-rounded (§ counted goods): `need` came off a
  /// forecast and carries the engine's micros residue, so "22" beats
  /// "21.999999" on a screen that counts trays. The spare is deliberately
  /// not spelled out — "That's 30 — you need 22" already says it, in the
  /// two numbers the cook actually acts on.
  String get verdict {
    if (needMicros == 0) {
      return 'The packing list says none are needed. Make no batches.';
    }
    final word = batches == 1 ? 'batch' : 'batches';
    final made = QuantityCodec.formatDisplayMicros(madeMicros);
    final need = QuantityCodec.formatDisplayMicros(needMicros);
    return "Make $batches $word. That's $made — you need $need.";
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
