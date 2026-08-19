/// What the stock on hand is worth — the items list's one summary figure
/// (v7 price design; money is [Money], integer cents throughout).
///
/// Σ (on-hand amount × price each) over LIVE items. Three honesty rules,
/// each of which the figure would be a lie without:
///
///  * An item with NO PRICE contributes nothing and is counted
///    ([unpricedItemCount]) — never a $0 standing in for "I don't know".
///  * An item counted BELOW ZERO contributes nothing and is counted
///    separately ([negativeItemCount]). The ledger allows negative on-hand
///    and the list surfaces it, but a negative amount is a counting error,
///    not stock in the van: letting it subtract would quietly shrink a
///    total that is supposed to say what is on the shelves, and [Money] has
///    no negative value to subtract into anyway. It is said out loud
///    instead, exactly like an unpriced item.
///  * With NOTHING priced there is no figure at all ([isEmpty]).
///
/// A priced item with zero on hand is different from all three: it
/// contributes exactly $0 because zero of it really is worth nothing, and
/// it counts as priced. A catalog that is fully priced and fully empty
/// therefore reads "$0" — a true answer, not a stand-in for an unknown one.
library;

import '../../../core/money.dart';
import '../application/catalog_service.dart';

/// The items list's summary figure and the counts behind it.
final class StockValue {
  const StockValue({
    required this.total,
    required this.pricedItemCount,
    required this.unpricedItemCount,
    required this.negativeItemCount,
  });

  /// Σ (on-hand amount × unit price) over priced items with a nonnegative
  /// count.
  final Money total;

  /// How many items drove [total].
  final int pricedItemCount;

  /// How many items have no price yet — left out of [total], said out loud.
  final int unpricedItemCount;

  /// How many priced items are counted below zero — left out of [total],
  /// said out loud on their own line (the rows already flag them
  /// "Negative"). An unpriced negative item counts as unpriced, not here:
  /// the missing price is the first thing wrong with it.
  final int negativeItemCount;

  /// True when nothing at all is priced: show no total UI.
  bool get isEmpty => pricedItemCount == 0;

  /// True when the total is real but incomplete.
  bool get isPartial =>
      pricedItemCount > 0 && (unpricedItemCount > 0 || negativeItemCount > 0);
}

/// Prices [items] at their current unit prices. Exact: every line is
/// `price × on-hand micros` through [Money.timesQuantityMicros] (BigInt
/// inside, truncating at the cent) and the lines are summed as integers.
StockValue stockValueOf(Iterable<ItemSummary> items) {
  var total = Money.zero;
  var priced = 0;
  var unpriced = 0;
  var negative = 0;
  for (final summary in items) {
    final price = summary.item.unitPrice;
    if (price == null) {
      unpriced++;
      continue;
    }
    if (summary.onHandMicros < 0) {
      negative++;
      continue;
    }
    priced++;
    total = total.plus(price.timesQuantityMicros(summary.onHandMicros));
  }
  return StockValue(
    total: total,
    pricedItemCount: priced,
    unpricedItemCount: unpriced,
    negativeItemCount: negative,
  );
}
