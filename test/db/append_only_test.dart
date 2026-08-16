/// §11.2 Tier 1: append-only triggers reject UPDATE and DELETE on all nine
/// protected tables, and the commands trigger permits exactly
/// staged -> applied|rejected.
library;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/data/db/schema_sql.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'fixtures.dart';

void main() {
  late AppDatabase db;

  /// One valid row in every append-only table, foreign keys ON.
  Future<void> seedGraph() async {
    await insertCommand(db, tid('C1'));
    await insertItem(db, tid('I1'));
    await insertEvent(db, tid('E1'), status: 'closed', closedAtMicros: 10);
    await insertMovement(
      db,
      tid('M1'),
      itemId: tid('I1'),
      kind: 'receive',
      deltaMicros: 5000000,
      sourceCommandId: tid('C1'),
    );
    await insertCloseout(
      db,
      tid('H1'),
      eventId: tid('E1'),
      revision: 1,
      confirmedExposure: 100,
      sourceCommandId: tid('C1'),
    );
    await insertCloseoutLine(
      db,
      closeoutId: tid('H1'),
      itemId: tid('I1'),
      depletionMicros: 1000000,
    );
    await insertRecipe(db, tid('R1'), outputItemId: tid('I1'));
    await insertRecipeRevision(db, tid('RV1'), recipeId: tid('R1'));
    await insertRecipeLine(
      db,
      revisionId: tid('RV1'),
      ingredientItemId: tid('I1'),
    );
    await insertSnapshot(
      db,
      tid('S1'),
      eventId: tid('E1'),
      sourceCommandId: tid('C1'),
    );
    await insertForecastLine(
      db,
      snapshotId: tid('S1'),
      itemId: tid('I1'),
      expectedUseMicros: 1,
      evidenceGrade: 'single_event',
    );
    await insertEvidence(
      db,
      snapshotId: tid('S1'),
      itemId: tid('I1'),
      closeoutId: tid('H1'),
      sourceEventId: tid('E1'),
    );
    await insertOverride(
      db,
      tid('O1'),
      snapshotId: tid('S1'),
      itemId: tid('I1'),
    );
  }

  setUp(() async {
    db = openTestDb();
    await seedGraph();
  });

  tearDown(() => db.close());

  final appendOnly = throwsA(
    isA<SqliteException>().having(
      (e) => e.message,
      'message',
      contains('append-only'),
    ),
  );

  group('append-only triggers', () {
    // One benign UPDATE per protected table; every one must be rejected.
    final updates = <String, String>{
      'inventory_movements': "UPDATE inventory_movements SET note = 'x'",
      'event_closeouts': "UPDATE event_closeouts SET note = 'x'",
      'closeout_lines': 'UPDATE closeout_lines SET depletion_micros = 2',
      'recipe_revisions': "UPDATE recipe_revisions SET note = 'x'",
      'recipe_lines': 'UPDATE recipe_lines SET quantity_per_batch_micros = 2',
      'forecast_snapshots':
          "UPDATE forecast_snapshots SET assumptions_json = '{}'",
      'forecast_lines': 'UPDATE forecast_lines SET on_hand_micros = 9',
      'forecast_evidence': 'UPDATE forecast_evidence SET exposure = 9',
      'forecast_overrides': "UPDATE forecast_overrides SET reason = 'edited'",
    };

    test('the protected table list matches the design', () {
      expect(appendOnlyTables, updates.keys);
    });

    for (final table in updates.keys) {
      test('$table rejects UPDATE', () async {
        await expectLater(db.customStatement(updates[table]!), appendOnly);
      });

      test('$table rejects DELETE', () async {
        await expectLater(db.customStatement('DELETE FROM $table'), appendOnly);
      });
    }
  });

  group('recipe_lines_v2 trigger (v5)', () {
    // Content is append-only exactly like the legacy table; the catalog
    // LINK alone is mutable metadata (the commands-table limited-update
    // pattern). See schemaV5RecipeLinesV2Triggers.
    final linkOnly = throwsA(
      isA<SqliteException>().having(
        (e) => e.message,
        'message',
        contains('only the item link may change'),
      ),
    );

    setUp(
      () => insertRecipeLineV2(
        db,
        revisionId: tid('RV1'),
        lineIndex: 1,
        ingredientName: 'Cumin',
        unitLabel: 'tsp',
      ),
    );

    test('DELETE is rejected', () async {
      await expectLater(
        db.customStatement('DELETE FROM recipe_lines_v2'),
        appendOnly,
      );
    });

    for (final mutation in const [
      "ingredient_name = 'Coriander'",
      "unit_label = 'tbsp'",
      'unit_label = NULL',
      'quantity_per_batch_micros = 2',
      'line_index = 9',
    ]) {
      test('UPDATE of anything but the link is rejected ($mutation)', () async {
        await expectLater(
          db.customStatement('UPDATE recipe_lines_v2 SET $mutation'),
          linkOnly,
        );
      });
    }

    test('the link alone may be set and cleared', () async {
      await db.customStatement(
        'UPDATE recipe_lines_v2 SET ingredient_item_id = ? '
        'WHERE line_index = 1',
        [tid('I1')],
      );
      var row = await db
          .customSelect(
            'SELECT ingredient_item_id FROM recipe_lines_v2 '
            'WHERE line_index = 1',
          )
          .getSingle();
      expect(row.read<String?>('ingredient_item_id'), tid('I1'));
      await db.customStatement(
        'UPDATE recipe_lines_v2 SET ingredient_item_id = NULL '
        'WHERE line_index = 1',
      );
      row = await db
          .customSelect(
            'SELECT ingredient_item_id FROM recipe_lines_v2 '
            'WHERE line_index = 1',
          )
          .getSingle();
      expect(row.read<String?>('ingredient_item_id'), isNull);
      // The frozen columns rode through both link writes untouched.
      final frozen = await db
          .customSelect(
            'SELECT ingredient_name, unit_label, quantity_per_batch_micros '
            'FROM recipe_lines_v2 WHERE line_index = 1',
          )
          .getSingle();
      expect(frozen.read<String>('ingredient_name'), 'Cumin');
      expect(frozen.read<String?>('unit_label'), 'tsp');
      expect(frozen.read<int>('quantity_per_batch_micros'), 1000000);
    });
  });

  group('commands trigger', () {
    final illegal = throwsA(
      isA<SqliteException>().having(
        (e) => e.message,
        'message',
        contains('illegal transition'),
      ),
    );

    Future<String> statusOf(String id) async {
      final row = await db
          .customSelect(
            'SELECT status FROM commands WHERE id = ?',
            variables: [Variable<String>(id)],
          )
          .getSingle();
      return row.read<String>('status');
    }

    test('staged -> applied is permitted', () async {
      await insertCommand(db, tid('C2'), status: 'staged');
      await db.customStatement(
        "UPDATE commands SET status = 'applied', applied_at_micros = 9 "
        'WHERE id = ?',
        [tid('C2')],
      );
      expect(await statusOf(tid('C2')), 'applied');
    });

    test('staged -> rejected is permitted', () async {
      await insertCommand(db, tid('C3'), status: 'staged');
      await db.customStatement(
        "UPDATE commands SET status = 'rejected', rejected_reason = 'nope' "
        'WHERE id = ?',
        [tid('C3')],
      );
      expect(await statusOf(tid('C3')), 'rejected');
    });

    test('terminal rows are frozen', () async {
      // C1 was inserted as applied.
      await expectLater(
        db.customStatement(
          "UPDATE commands SET status = 'rejected' WHERE id = ?",
          [tid('C1')],
        ),
        illegal,
      );
      await expectLater(
        db.customStatement(
          "UPDATE commands SET applied_at_micros = 42 WHERE id = ?",
          [tid('C1')],
        ),
        illegal,
      );
    });

    test('staged -> staged is not a transition', () async {
      await insertCommand(db, tid('C4'), status: 'staged');
      await expectLater(
        db.customStatement(
          "UPDATE commands SET payload_json = '{\"x\":1}' WHERE id = ?",
          [tid('C4')],
        ),
        illegal,
      );
    });

    test('immutable columns cannot ride along on a legal transition', () async {
      await insertCommand(db, tid('C5'), status: 'staged');
      for (final mutation in [
        "payload_json = '{\"x\":1}'",
        "kind = 'Other'",
        "origin = 'agent'",
        'created_at_micros = 99',
        "id = '${tid('C5X')}'",
      ]) {
        await expectLater(
          db.customStatement(
            "UPDATE commands SET status = 'applied', $mutation WHERE id = ?",
            [tid('C5')],
          ),
          illegal,
        );
      }
      // The row is still staged and still transitions cleanly afterwards.
      await db.customStatement(
        "UPDATE commands SET status = 'applied', applied_at_micros = 9 "
        'WHERE id = ?',
        [tid('C5')],
      );
      expect(await statusOf(tid('C5')), 'applied');
    });

    test('DELETE is always rejected', () async {
      await insertCommand(db, tid('C6'), status: 'staged');
      final appendOnlyCommands = throwsA(
        isA<SqliteException>().having(
          (e) => e.message,
          'message',
          contains('append-only'),
        ),
      );
      await expectLater(
        db.customStatement('DELETE FROM commands WHERE id = ?', [tid('C6')]),
        appendOnlyCommands,
      );
      await expectLater(
        db.customStatement('DELETE FROM commands WHERE id = ?', [tid('C1')]),
        appendOnlyCommands,
      );
    });
  });
}
