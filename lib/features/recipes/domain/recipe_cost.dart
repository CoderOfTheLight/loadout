/// What a recipe costs to make — pure arithmetic over one revision's lines
/// (v7 price design; the money type is [Money], integer cents throughout).
///
/// The rule the whole app holds: an unpriced thing contributes NOTHING and
/// is COUNTED, so every surface can say so out loud. A recipe line can be
/// unpriced two ways — it is not linked to a catalog item at all, or it is
/// linked to an item the owner never priced — and both land in
/// [RecipeBatchCost.unpricedLineCount]. Neither is worth $0: a $0 standing
/// in for "I don't know" would make a recipe look cheaper than it is.
///
/// The figure is LIVE, never a snapshot. It reads the CURRENT revision's
/// lines at TODAY's item prices, so repricing flour moves every recipe that
/// uses it. (Revisions themselves are immutable, but they record method and
/// amounts — never money. An old revision priced at today's prices would be
/// a hybrid of two moments, so surfaces cost the current revision only.)
library;

import '../../../core/money.dart';
import '../../../core/quantity.dart';

/// One ingredient line reduced to what pricing needs: how much of it one
/// batch takes, and what one unit of it costs today (null = no price, which
/// covers both an unlinked line and a linked-but-unpriced one).
typedef RecipeCostLine = ({int quantityMicros, Money? unitPrice});

/// What one batch of a recipe costs at today's prices.
final class RecipeBatchCost {
  const RecipeBatchCost({
    required this.total,
    required this.pricedLineCount,
    required this.unpricedLineCount,
  });

  /// Σ (per-batch quantity × the linked item's current unit price) over the
  /// lines that carry a price.
  final Money total;

  /// How many ingredient lines drove [total].
  final int pricedLineCount;

  /// How many ingredient lines were left OUT of [total] — unlinked, or
  /// linked to an item with no price. Said out loud wherever [total] is.
  final int unpricedLineCount;

  /// True when NO line is priced: show no figure at all, never a $0.
  bool get isEmpty => pricedLineCount == 0;

  /// True when the figure is real but incomplete — the batch costs at least
  /// this much, and surfaces say so.
  bool get isPartial => pricedLineCount > 0 && unpricedLineCount > 0;

  /// What one of whatever the batch makes costs, or null when dividing is
  /// not honest arithmetic.
  ///
  /// A yield is a [Quantity], not a headcount, so it only divides when it is
  /// a whole number of things: "makes 24" divides into 24 portions, "makes
  /// 2.5" does not divide into anything the owner can hand over. A yield of
  /// one is refused too — "$12 a batch · $12 each" says the same thing
  /// twice.
  ///
  /// Rounded half-up ONCE, at the cent, exactly like the per-person spend on
  /// the event page; the batch total itself is never rounded.
  Money? perYieldUnit(Quantity yieldQuantity) {
    if (yieldQuantity.micros % Quantity.scale != 0) {
      return null;
    }
    final whole = yieldQuantity.micros ~/ Quantity.scale;
    if (whole < 2) {
      return null;
    }
    return Money.fromCents((total.cents * 2 + whole) ~/ (whole * 2));
  }
}

/// Prices one batch of [lines]. Exact: each line is
/// `price × quantity micros` through [Money.timesQuantityMicros] (BigInt
/// inside, truncating at the cent), and the line amounts are summed as
/// integers — no floating point anywhere on the path.
RecipeBatchCost recipeBatchCost(Iterable<RecipeCostLine> lines) {
  var total = Money.zero;
  var priced = 0;
  var unpriced = 0;
  for (final line in lines) {
    final price = line.unitPrice;
    if (price == null) {
      unpriced++;
      continue;
    }
    priced++;
    total = total.plus(price.timesQuantityMicros(line.quantityMicros));
  }
  return RecipeBatchCost(
    total: total,
    pricedLineCount: priced,
    unpricedLineCount: unpriced,
  );
}
