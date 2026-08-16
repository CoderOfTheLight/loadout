/// Unit tests for the Gate 5 OCR text conditioning (pure, no widgets):
/// vulgar-fraction normalization (standalone and mixed numbers, the full
/// table), the U+2044 fraction slash, space collapsing, hands-off
/// everything else — and the prose pre-filter's exact rule (drop ONLY
/// amount-less lines with more than 8 words).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/recipes/presentation/ocr_text_normalizer.dart';

void main() {
  group('normalizeOcrLine', () {
    test('every vulgar fraction maps to its ASCII form', () {
      const table = {
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
      for (final entry in table.entries) {
        expect(
          normalizeOcrLine('${entry.key} cup sugar'),
          '${entry.value} cup sugar',
          reason: entry.key,
        );
      }
    });

    test('standalone fraction becomes a standalone ASCII amount', () {
      expect(normalizeOcrLine('½'), '1/2');
    });

    test('digit immediately before a fraction becomes a mixed number', () {
      expect(normalizeOcrLine('1½ cups flour'), '1 1/2 cups flour');
      expect(normalizeOcrLine('12⅔ oz butter'), '12 2/3 oz butter');
    });

    test('digit-space-fraction is already a mixed number and stays one', () {
      expect(normalizeOcrLine('2 ¾ cups milk'), '2 3/4 cups milk');
    });

    test('U+2044 fraction slash becomes ASCII slash', () {
      expect(normalizeOcrLine('1⁄2 cup broth'), '1/2 cup broth');
      expect(normalizeOcrLine('1 1⁄2 cups stock'), '1 1/2 cups stock');
    });

    test('runs of spaces collapse to one', () {
      expect(normalizeOcrLine('2   lbs    beef'), '2 lbs beef');
    });

    test('spaces created by mixed-number rewriting stay single', () {
      expect(normalizeOcrLine('1 ½ cups flour'), '1 1/2 cups flour');
    });

    test('everything else passes through untouched', () {
      expect(normalizeOcrLine('2 × rolls'), '2 × rolls');
      expect(normalizeOcrLine('Fresh basil, torn'), 'Fresh basil, torn');
      expect(normalizeOcrLine('2-3 onions'), '2-3 onions');
    });
  });

  group('filterOcrIngredientLines', () {
    test('drops an amount-less line with more than 8 words (prose)', () {
      expect(
        filterOcrIngredientLines([
          'Simmer gently until the meat is falling apart and tender',
        ]),
        isEmpty,
      );
    });

    test('keeps an amount-less line of exactly 8 words (boundary)', () {
      const eightWords = 'a generous pinch of good flaky sea salt';
      expect(filterOcrIngredientLines([eightWords]), [eightWords]);
    });

    test('drops at nine amount-less words (boundary)', () {
      const nineWords = 'stir the pot slowly over a very low flame';
      expect(filterOcrIngredientLines([nineWords]), isEmpty);
    });

    test('keeps short amount-less lines — they are real ingredients', () {
      const lines = ['Salt', 'Fresh basil', 'Beef stew'];
      expect(filterOcrIngredientLines(lines), lines);
    });

    test('keeps amount-led lines however long they run', () {
      const line = '2 lbs beef chuck trimmed and cut into small even cubes';
      expect(filterOcrIngredientLines([line]), [line]);
    });

    test('drops blank lines', () {
      expect(filterOcrIngredientLines(['', '   ', 'Salt']), ['Salt']);
    });

    test('preserves order of the kept lines', () {
      expect(
        filterOcrIngredientLines([
          'Beef stew',
          'Cook everything together slowly until it is completely done today',
          '2 lbs beef',
          '1/2 cup flour',
        ]),
        ['Beef stew', '2 lbs beef', '1/2 cup flour'],
      );
    });
  });
}
