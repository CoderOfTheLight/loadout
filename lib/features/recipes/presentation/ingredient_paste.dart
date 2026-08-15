/// Paste-an-ingredient-list capture: pure line parsing + catalog matching.
///
/// The proposal's recipe-screen addition ("Paste a whole ingredient list"):
/// multi-line text is split into candidate lines, each line is matched
/// against the live item catalog (case-insensitive, lightly normalised,
/// contains-based), and an unambiguous leading amount — "2x carrots",
/// "3 bags onions" — becomes the per-batch count. Anything unclear (ranges,
/// weights, "dozen") leaves the amount blank rather than guessing: a wrong
/// number typed for the owner is worse than no number.
///
/// GATE 5 SEAM: [PasteCandidateLine] is deliberately producer-agnostic — a
/// raw text line plus its match state. The OCR flow will produce the same
/// raw lines and feed this same parser and the same review sheet
/// (`ingredient_paste_sheet.dart`), so OCR becomes a second producer, not a
/// second reviewer. Nothing here writes anything.
///
/// Sales-table rule: items living in a sales-table folder (see
/// `recipe_catalog_filters.dart`) are never matched as ingredients — a line
/// that would only match one is reported as [PasteLineStatus.excluded] so
/// the reviewer can say why instead of offering to create a duplicate.
library;

import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../catalog/domain/item.dart';

/// What one pasted line resolved to.
enum PasteLineStatus {
  /// Exactly one live, non-sales-table item matched.
  matched,

  /// More than one item matched; the reviewer adds a blank row and the
  /// owner picks on the form. Never auto-resolved.
  ambiguous,

  /// Nothing matched; the reviewer offers "Create «name»".
  unmatched,

  /// The only match lives on the sales table — recipes never use those, so
  /// the line is skipped with the reason said out loud.
  excluded,
}

/// One reviewed line: the raw text as pasted (or, later, as OCR read it),
/// the cleaned-up name, the parsed per-batch amount when it was unambiguous,
/// and what the catalog made of it.
final class PasteCandidateLine {
  const PasteCandidateLine({
    required this.rawText,
    required this.name,
    this.quantityPerBatch,
    required this.status,
    this.match,
    this.nearMatches = const [],
  });

  /// The line exactly as the producer (paste today, OCR later) supplied it.
  final String rawText;

  /// The name after stripping bullets and any amount prefix — original
  /// casing kept, because it becomes the new item's name on create.
  final String name;

  /// Parsed per-batch count, or null when the line carried none or carried
  /// one that cannot be read as a count (a range, a weight, "dozen").
  final Quantity? quantityPerBatch;

  final PasteLineStatus status;

  /// The matched item ([PasteLineStatus.matched]) or the sales-table item
  /// that caused the exclusion ([PasteLineStatus.excluded]).
  final Item? match;

  /// The competing candidates on an [PasteLineStatus.ambiguous] line.
  final List<Item> nearMatches;
}

/// One resolved row handed back to the recipe form after the review is
/// confirmed: a picked/created item (or null for a line left for manual
/// fixing) plus the parsed per-batch amount when there was one.
final class PastedIngredient {
  const PastedIngredient({this.itemId, this.quantityPerBatch});

  final String? itemId;
  final Quantity? quantityPerBatch;
}

/// A parsed-but-unmatched line: the intermediate between raw text and
/// [PasteCandidateLine].
final class ParsedPasteLine {
  const ParsedPasteLine({
    required this.rawText,
    required this.name,
    this.quantityPerBatch,
  });

  final String rawText;
  final String name;
  final Quantity? quantityPerBatch;
}

// -------------------------------------------------------------- parsing

/// Bullets and list numbering ("- ", "* ", "• ", "3) ", "3. ") are dressing,
/// not amounts. A bare "2 carrots" (no dot/bracket) IS an amount and is left
/// for the quantity rules below.
final RegExp _bulletPrefix = RegExp(r'^\s*(?:[-*•·‣▪]+|\d{1,3}[.)])\s+');

/// "2-3 onions", "2 – 3 onions", "2 to 3 onions": a range is not a count.
final RegExp _range = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s*(?:[-–—]|to\b)\s*(\d+(?:[.,]\d+)?)\s+(.+)$',
  caseSensitive: false,
);

/// "2x rolls", "2 × rolls": the plainest multiplier.
final RegExp _multiplier = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s*[x×]\s*(\p{L}.*)$',
  caseSensitive: false,
  unicode: true,
);

/// "500g flour", "1.5 kg mince": a weight or volume is NOT a per-batch
/// count of a counted thing — the amount is left blank on purpose.
final RegExp _measurement = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s*'
  r'(kg|g|mg|ml|cl|dl|l|oz|lbs?|cups?|tbsp|tsp|litres?|liters?|grams?|kilos?)'
  r'\b\.?\s*(?:of\s+)?(.*)$',
  caseSensitive: false,
);

/// "2 dozen eggs": 24, 2, or "a lot"? Ambiguous — left blank.
final RegExp _dozen = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s+dozen\b\s*(?:of\s+)?(.*)$',
  caseSensitive: false,
);

/// "3 bags onions", "2 packs of napkins": the leading number is the count
/// (items are counted things — a bag of onions is one counted unit); the
/// container word is dropped from the name being matched.
final RegExp _container = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s+'
  r'(bags?|boxes?|packs?|packets?|cans?|bottles?|jars?|tins?|trays?|tubs?'
  r'|cases?|crates?|cartons?|punnets?|sacks?|bunch(?:es)?|heads?)'
  r'\b\s*(?:of\s+)?(.+)$',
  caseSensitive: false,
);

/// "2 carrots", "1.5 tomato puree": plain leading count.
final RegExp _plainCount = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s+(\p{L}.*)$',
  unicode: true,
);

/// Parses one raw line, or returns null for a blank one. Never throws.
ParsedPasteLine? parsePasteLine(String raw) {
  final rawText = raw.trim();
  if (rawText.isEmpty) return null;
  final line = rawText.replaceFirst(_bulletPrefix, '').trim();
  if (line.isEmpty) return null;

  if (_range.firstMatch(line) case final m?) {
    return ParsedPasteLine(rawText: rawText, name: m.group(3)!.trim());
  }
  if (_multiplier.firstMatch(line) case final m?) {
    return ParsedPasteLine(
      rawText: rawText,
      name: m.group(2)!.trim(),
      quantityPerBatch: _parseCount(m.group(1)!),
    );
  }
  if (_measurement.firstMatch(line) case final m?) {
    final rest = m.group(3)!.trim();
    return ParsedPasteLine(rawText: rawText, name: rest.isEmpty ? line : rest);
  }
  if (_dozen.firstMatch(line) case final m?) {
    final rest = m.group(2)!.trim();
    return ParsedPasteLine(rawText: rawText, name: rest.isEmpty ? line : rest);
  }
  if (_container.firstMatch(line) case final m?) {
    return ParsedPasteLine(
      rawText: rawText,
      name: m.group(3)!.trim(),
      quantityPerBatch: _parseCount(m.group(1)!),
    );
  }
  if (_plainCount.firstMatch(line) case final m?) {
    return ParsedPasteLine(
      rawText: rawText,
      name: m.group(2)!.trim(),
      quantityPerBatch: _parseCount(m.group(1)!),
    );
  }
  return ParsedPasteLine(rawText: rawText, name: line);
}

/// Lenient exact-decimal parse; zero and unparseable both come back null —
/// a zero per-batch amount is never what a pasted list meant.
Quantity? _parseCount(String text) {
  try {
    final value = QuantityCodec.parse(text);
    return value.micros == 0 ? null : value;
  } on Exception {
    return null;
  } on Error {
    return null;
  }
}

// ------------------------------------------------------------- matching

/// Lowercase, punctuation to spaces, whitespace collapsed — "Chopped
/// tomatoes!" and "chopped  Tomatoes" read the same.
String normalizeIngredientName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// Cheap singular: "carrots" == "carrot". Never touches short words or
/// "-ss" words (grass).
String _singular(String name) =>
    name.length > 3 && name.endsWith('s') && !name.endsWith('ss')
    ? name.substring(0, name.length - 1)
    : name;

bool _containsEitherWay(String a, String b) =>
    (b.length >= 3 && a.contains(b)) || (a.length >= 3 && b.contains(a));

/// Splits [text] into lines and matches each against [catalog].
///
/// [catalog] is the LIVE item list (archived items cannot be picked, so
/// they are dropped here as well); [salesTableFolderIds] marks the folders
/// whose items are never ingredients.
List<PasteCandidateLine> parseIngredientPaste(
  String text, {
  required List<Item> catalog,
  required Set<String> salesTableFolderIds,
}) {
  final eligible = <Item>[];
  final salesTable = <Item>[];
  for (final item in catalog) {
    if (item.isArchived) continue;
    if (salesTableFolderIds.contains(item.folderId?.value)) {
      salesTable.add(item);
    } else {
      eligible.add(item);
    }
  }
  return [
    for (final raw in text.split('\n'))
      if (parsePasteLine(raw) case final line?)
        _matchLine(line, eligible: eligible, salesTable: salesTable),
  ];
}

PasteCandidateLine _matchLine(
  ParsedPasteLine line, {
  required List<Item> eligible,
  required List<Item> salesTable,
}) {
  final query = normalizeIngredientName(line.name);
  if (query.isEmpty) {
    return PasteCandidateLine(
      rawText: line.rawText,
      name: line.name,
      quantityPerBatch: line.quantityPerBatch,
      status: PasteLineStatus.unmatched,
    );
  }

  List<Item> exactIn(List<Item> pool) => [
    for (final item in pool)
      if (_singular(normalizeIngredientName(item.name)) == _singular(query))
        item,
  ];
  List<Item> nearIn(List<Item> pool) => [
    for (final item in pool)
      if (_containsEitherWay(normalizeIngredientName(item.name), query)) item,
  ];

  // Exact (singular-insensitive) beats contains: "chopped tomatoes" hits
  // the item of that name even though "Tomato puree" also contains-matches.
  final hits = switch (exactIn(eligible)) {
    [] => nearIn(eligible),
    final exacts => exacts,
  };
  if (hits.length == 1) {
    return PasteCandidateLine(
      rawText: line.rawText,
      name: line.name,
      quantityPerBatch: line.quantityPerBatch,
      status: PasteLineStatus.matched,
      match: hits.single,
    );
  }
  if (hits.length > 1) {
    return PasteCandidateLine(
      rawText: line.rawText,
      name: line.name,
      quantityPerBatch: line.quantityPerBatch,
      status: PasteLineStatus.ambiguous,
      nearMatches: hits,
    );
  }
  final salesHits = switch (exactIn(salesTable)) {
    [] => nearIn(salesTable),
    final exacts => exacts,
  };
  if (salesHits.isNotEmpty) {
    return PasteCandidateLine(
      rawText: line.rawText,
      name: line.name,
      quantityPerBatch: line.quantityPerBatch,
      status: PasteLineStatus.excluded,
      match: salesHits.first,
    );
  }
  return PasteCandidateLine(
    rawText: line.rawText,
    name: line.name,
    quantityPerBatch: line.quantityPerBatch,
    status: PasteLineStatus.unmatched,
  );
}
