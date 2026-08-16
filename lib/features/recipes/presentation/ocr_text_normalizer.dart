/// Gate 5 OCR text conditioning: the two PURE steps between a raw
/// `RecipeOcrCapture` line list and the paste pipeline.
///
/// [normalizeOcrLine] rewrites only what the parser's ASCII amount regex
/// cannot read — unicode vulgar fractions ("½", "1½") and the unicode
/// fraction slash U+2044 — and collapses runs of spaces. Nothing else is
/// touched: `parsePasteLine` owns real parsing, and "×" stays as-is (the
/// parser reads it as a multiplier).
///
/// [filterOcrIngredientLines] drops the lines a recipe PHOTO carries that a
/// pasted list never does — instruction prose — and keeps everything else:
/// short amount-less lines ("Salt", "Fresh basil") are real ingredients. A
/// line is dropped ONLY when it clearly reads as prose: it parses with no
/// leading amount AND has more than [proseWordThreshold] words. Blank lines
/// carry nothing and are dropped too, so an all-noise capture surfaces as
/// "no text found" instead of an empty review.
library;

import 'ingredient_paste.dart';

/// Unicode vulgar fractions → the ASCII forms `parsePasteLine`'s amount
/// regex reads.
const Map<String, String> _vulgarFractions = {
  '¼': '1/4',
  '½': '1/2',
  '¾': '3/4',
  '⅓': '1/3',
  '⅔': '2/3',
  '⅕': '1/5',
  '⅖': '2/5',
  '⅗': '3/5',
  '⅘': '4/5',
  '⅙': '1/6',
  '⅚': '5/6',
  '⅛': '1/8',
  '⅜': '3/8',
  '⅝': '5/8',
  '⅞': '7/8',
};

/// A digit immediately followed by a vulgar fraction is a mixed number
/// ("1½ cups"): the fraction gets a space so it becomes "1 1/2 cups".
final RegExp _digitBeforeVulgarFraction = RegExp('([0-9])([¼½¾⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])');

final RegExp _spaceRuns = RegExp(' {2,}');

/// An amount-less line with more words than this reads as instruction prose.
const int proseWordThreshold = 8;

/// Rewrites one OCR line so the paste parser can read its amounts:
/// "½" → "1/2", "1½ cups" → "1 1/2 cups" (mixed numbers preserved),
/// "1⁄2" (U+2044) → "1/2", and runs of spaces collapsed. Everything else —
/// casing, punctuation, "×" — passes through untouched.
String normalizeOcrLine(String line) {
  var out = line.replaceAllMapped(
    _digitBeforeVulgarFraction,
    (m) => '${m[1]} ${m[2]}',
  );
  for (final entry in _vulgarFractions.entries) {
    out = out.replaceAll(entry.key, entry.value);
  }
  out = out.replaceAll('⁄', '/');
  return out.replaceAll(_spaceRuns, ' ');
}

/// Keeps the lines that could be ingredients; drops instruction prose
/// (no leading amount AND more than [proseWordThreshold] words) and blank
/// lines. Order is preserved. Never throws.
List<String> filterOcrIngredientLines(List<String> lines) => [
  for (final line in lines)
    if (_couldBeIngredient(line)) line,
];

bool _couldBeIngredient(String line) {
  final parsed = parsePasteLine(line);
  if (parsed == null) return false; // blank — nothing to review
  if (parsed.quantityPerBatch != null) return true; // amount-led, keep
  final words = line.trim().split(RegExp(r'\s+')).length;
  return words <= proseWordThreshold;
}
