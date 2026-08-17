/// Pure tests for the paste-ingredients parser + matcher
/// (`lib/features/recipes/presentation/ingredient_paste.dart`): quantity
/// prefixes parsed only where unambiguous, measure words kept as display-
/// only unit labels (v5 — never converted), fractions read exactly,
/// exact-beats-contains matching, ambiguity never auto-resolved,
/// sales-table items excluded.
///
/// Deliberately superseded pins (v5 unit-label ruling): "500g flour" and
/// "2 dozen eggs" used to leave the amount blank because a weight or a
/// dozen was not a count; with unit labels the amount is kept and the
/// measure word becomes the label, displayed verbatim.
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

    test('"3 bags onions": amount 3, label "bags", container out of name', () {
      final line = parsePasteLine('3 bags onions')!;
      expect(line.quantityPerBatch, Quantity.whole(3));
      expect(line.unitLabel, 'bags');
      expect(line.name, 'onions');
    });

    test('"2 packs of napkins" honours the optional "of"', () {
      final line = parsePasteLine('2 packs of napkins')!;
      expect(line.quantityPerBatch, Quantity.whole(2));
      expect(line.unitLabel, 'packs');
      expect(line.name, 'napkins');
    });

    test('"1.5 tomato puree" parses an exact decimal count', () {
      final line = parsePasteLine('1.5 tomato puree')!;
      expect(line.quantityPerBatch!.micros, 1500000);
      expect(line.unitLabel, isNull);
      expect(line.name, 'tomato puree');
    });

    test('"500g flour": amount 500, label "g" — never converted', () {
      final line = parsePasteLine('500g flour')!;
      expect(line.quantityPerBatch, Quantity.whole(500));
      expect(line.unitLabel, 'g');
      expect(line.name, 'flour');
    });

    test('"1 1/2 cups sugar": exact mixed fraction with its label', () {
      final line = parsePasteLine('1 1/2 cups sugar')!;
      expect(line.quantityPerBatch!.micros, 1500000);
      expect(line.unitLabel, 'cups');
      expect(line.name, 'sugar');
    });

    test('"1/2 lemon": a bare fraction is a plain amount', () {
      final line = parsePasteLine('1/2 lemon')!;
      expect(line.quantityPerBatch!.micros, 500000);
      expect(line.unitLabel, isNull);
      expect(line.name, 'lemon');
    });

    test('"2-3 onions" leaves the amount blank — a range is ambiguous', () {
      final line = parsePasteLine('2-3 onions')!;
      expect(line.quantityPerBatch, isNull);
      expect(line.name, 'onions');
    });

    test('"2 dozen eggs": amount 2 with the label "dozen", never 24', () {
      final line = parsePasteLine('2 dozen eggs')!;
      expect(line.quantityPerBatch, Quantity.whole(2));
      expect(line.unitLabel, 'dozen');
      expect(line.name, 'eggs');
    });

    test('a bare measurement with no name stays one un-parsed name', () {
      final line = parsePasteLine('500g')!;
      expect(line.quantityPerBatch, isNull);
      expect(line.unitLabel, isNull);
      expect(line.name, '500g');
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

  group('parsePasteLine kitchen abbreviations', () {
    // (input, amount micros, expected label, expected name). Cryptic
    // abbreviations expand to readable labels; readable ones stay verbatim.
    const table = <(String, int, String, String)>[
      ('1 c flour', 1000000, 'cup', 'flour'),
      ('1 c. flour', 1000000, 'cup', 'flour'),
      ('1 C flour', 1000000, 'cup', 'flour'),
      ('1 1/2 c sugar', 1500000, 'cup', 'sugar'),
      ('1 t salt', 1000000, 'tsp', 'salt'),
      ('1 T butter', 1000000, 'tbsp', 'butter'),
      ('2 T oil', 2000000, 'tbsp', 'oil'),
      ('1 tbs sugar', 1000000, 'tbsp', 'sugar'),
      ('1 qt stock', 1000000, 'qt', 'stock'),
      ('2 qts stock', 2000000, 'qts', 'stock'),
      ('2 quarts stock', 2000000, 'quarts', 'stock'),
      ('2 pts cream', 2000000, 'pts', 'cream'),
      ('1 pt cream', 1000000, 'pt', 'cream'),
      ('2 pints cream', 2000000, 'pints', 'cream'),
      ('1 gal milk', 1000000, 'gal', 'milk'),
      ('2 gallons milk', 2000000, 'gallons', 'milk'),
      ('4 fl oz cream', 4000000, 'fl oz', 'cream'),
      ('4 fl. oz. cream', 4000000, 'fl oz', 'cream'),
      ('4 floz cream', 4000000, 'fl oz', 'cream'),
      ('2 sticks butter', 2000000, 'sticks', 'butter'),
      ('1 stick of butter', 1000000, 'stick', 'butter'),
    ];

    for (final (input, micros, label, name) in table) {
      test('"$input" → $micros micros, label "$label", name "$name"', () {
        final line = parsePasteLine(input)!;
        expect(line.quantityPerBatch!.micros, micros);
        expect(line.unitLabel, label);
        expect(line.name, name);
      });
    }

    test('single letters never swallow words that start with them', () {
      final carrots = parsePasteLine('2 carrots')!;
      expect(carrots.quantityPerBatch, Quantity.whole(2));
      expect(carrots.unitLabel, isNull);
      expect(carrots.name, 'carrots');

      final tomatoes = parsePasteLine('2 tomatoes')!;
      expect(tomatoes.quantityPerBatch, Quantity.whole(2));
      expect(tomatoes.unitLabel, isNull);
      expect(tomatoes.name, 'tomatoes');
    });

    test('"1 To taste" is not a tablespoon — the letter must stand alone', () {
      final line = parsePasteLine('1 To taste')!;
      expect(line.quantityPerBatch, Quantity.whole(1));
      expect(line.unitLabel, isNull);
      expect(line.name, 'To taste');
    });

    test('"2 T-bone steaks" is a plain count, not 2 tbsp of "-bone"', () {
      final line = parsePasteLine('2 T-bone steaks')!;
      expect(line.quantityPerBatch, Quantity.whole(2));
      expect(line.unitLabel, isNull);
      expect(line.name, 'T-bone steaks');
    });

    test('already-working labels stay verbatim — no canonicalising', () {
      final cups = parsePasteLine('2 cups sugar')!;
      expect(cups.quantityPerBatch, Quantity.whole(2));
      expect(cups.unitLabel, 'cups');
      expect(cups.name, 'sugar');

      final tbsp = parsePasteLine('1 tbsp oil')!;
      expect(tbsp.quantityPerBatch, Quantity.whole(1));
      expect(tbsp.unitLabel, 'tbsp');
      expect(tbsp.name, 'oil');

      final bags = parsePasteLine('3 bags onions')!;
      expect(bags.quantityPerBatch, Quantity.whole(3));
      expect(bags.unitLabel, 'bags');
      expect(bags.name, 'onions');
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
