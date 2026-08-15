/// Pure tests for the paste-ingredients parser + matcher
/// (`lib/features/recipes/presentation/ingredient_paste.dart`): quantity
/// prefixes parsed only where unambiguous, exact-beats-contains matching,
/// ambiguity never auto-resolved, sales-table items excluded.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/time.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/recipes/presentation/ingredient_paste.dart';

Item _item(String id, String name, {String? folderId}) => Item(
  id: ItemId(id),
  name: name,
  folderId: folderId == null ? null : FolderId(folderId),
  createdAt: const Instant(0),
  updatedAt: const Instant(0),
);

void main() {
  group('parsePasteLine quantity prefixes', () {
    test('"2x carrots" parses count 2 and name carrots', () {
      final line = parsePasteLine('2x carrots')!;
      expect(line.quantityPerBatch, Quantity.whole(2));
      expect(line.name, 'carrots');
    });

    test('"2 × Carrots" keeps the original casing of the name', () {
      final line = parsePasteLine('2 × Carrots')!;
      expect(line.quantityPerBatch, Quantity.whole(2));
      expect(line.name, 'Carrots');
    });

    test('"3 bags onions" parses count 3, container word dropped', () {
      final line = parsePasteLine('3 bags onions')!;
      expect(line.quantityPerBatch, Quantity.whole(3));
      expect(line.name, 'onions');
    });

    test('"2 packs of napkins" honours the optional "of"', () {
      final line = parsePasteLine('2 packs of napkins')!;
      expect(line.quantityPerBatch, Quantity.whole(2));
      expect(line.name, 'napkins');
    });

    test('"1.5 tomato puree" parses an exact decimal count', () {
      final line = parsePasteLine('1.5 tomato puree')!;
      expect(line.quantityPerBatch!.micros, 1500000);
      expect(line.name, 'tomato puree');
    });

    test('"500g flour" leaves the amount blank — a weight is not a count', () {
      final line = parsePasteLine('500g flour')!;
      expect(line.quantityPerBatch, isNull);
      expect(line.name, 'flour');
    });

    test('"2-3 onions" leaves the amount blank — a range is ambiguous', () {
      final line = parsePasteLine('2-3 onions')!;
      expect(line.quantityPerBatch, isNull);
      expect(line.name, 'onions');
    });

    test('"2 dozen eggs" leaves the amount blank', () {
      final line = parsePasteLine('2 dozen eggs')!;
      expect(line.quantityPerBatch, isNull);
      expect(line.name, 'eggs');
    });

    test('bullets and list numbering are stripped, not read as amounts', () {
      expect(parsePasteLine('- rolls')!.name, 'rolls');
      expect(parsePasteLine('- rolls')!.quantityPerBatch, isNull);
      expect(parsePasteLine('• 2 lemons')!.name, 'lemons');
      expect(parsePasteLine('• 2 lemons')!.quantityPerBatch, Quantity.whole(2));
      expect(parsePasteLine('3) rolls')!.name, 'rolls');
      expect(parsePasteLine('3) rolls')!.quantityPerBatch, isNull);
    });

    test('blank lines come back null', () {
      expect(parsePasteLine(''), isNull);
      expect(parsePasteLine('   '), isNull);
    });
  });

  group('parseIngredientPaste matching', () {
    final catalog = [
      _item('i1', 'Carrots'),
      _item('i2', 'Chopped tomatoes'),
      _item('i3', 'Tomato puree'),
      _item('i4', 'Album CD', folderId: 'f-sales'),
    ];
    const sales = {'f-sales'};

    List<PasteCandidateLine> parse(String text) => parseIngredientPaste(
      text,
      catalog: catalog,
      salesTableFolderIds: sales,
    );

    test('exact (case- and plural-insensitive) match wins over contains', () {
      // "chopped tomatoes" contains-matches "Tomato puree" too, but the
      // exact name match must not be diluted into an ambiguity.
      final line = parse('chopped tomatoes').single;
      expect(line.status, PasteLineStatus.matched);
      expect(line.match!.name, 'Chopped tomatoes');
    });

    test('singular query matches plural item name', () {
      final line = parse('carrot').single;
      expect(line.status, PasteLineStatus.matched);
      expect(line.match!.name, 'Carrots');
    });

    test('two contains-matches are ambiguous, never auto-resolved', () {
      final line = parse('tomato').single;
      expect(line.status, PasteLineStatus.ambiguous);
      expect(line.match, isNull);
      expect([
        for (final item in line.nearMatches) item.name,
      ], containsAll(['Chopped tomatoes', 'Tomato puree']));
    });

    test('no match at all is unmatched (the "Create «…»" case)', () {
      final line = parse('rolls').single;
      expect(line.status, PasteLineStatus.unmatched);
      expect(line.match, isNull);
    });

    test('a line matching only a sales-table item is excluded', () {
      final line = parse('album cd').single;
      expect(line.status, PasteLineStatus.excluded);
      expect(line.match!.name, 'Album CD');
    });

    test('archived items never match', () {
      final withArchived = [
        ...catalog,
        Item(
          id: const ItemId('i5'),
          name: 'Rolls',
          archivedAt: const Instant(1),
          createdAt: const Instant(0),
          updatedAt: const Instant(0),
        ),
      ];
      final line = parseIngredientPaste(
        'rolls',
        catalog: withArchived,
        salesTableFolderIds: sales,
      ).single;
      expect(line.status, PasteLineStatus.unmatched);
    });

    test('a six-line paste keeps order and per-line quantities', () {
      final lines = parse(
        '2x carrots\n'
        '\n'
        'chopped tomatoes\n'
        'tomato\n'
        'rolls\n',
      );
      expect(lines, hasLength(4)); // blank line dropped
      expect(lines[0].status, PasteLineStatus.matched);
      expect(lines[0].quantityPerBatch, Quantity.whole(2));
      expect(lines[1].status, PasteLineStatus.matched);
      expect(lines[1].quantityPerBatch, isNull);
      expect(lines[2].status, PasteLineStatus.ambiguous);
      expect(lines[3].status, PasteLineStatus.unmatched);
    });
  });
}
