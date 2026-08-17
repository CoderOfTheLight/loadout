/// Schema v5 (unit labels + recipe decoupling), in the pattern of the
/// earlier migration tests: the owner has live data on her phone, so the
/// contract under test is not just "the new shapes exist" but:
///
///  * every v4 row survives byte for byte — items gain a NULL unit_label
///    and display nothing new until she types one;
///  * `recipe_lines` (trigger-enforced append-only) is NEVER rewritten: its
///    rows remain untouched, and every one is COPIED into `recipe_lines_v2`
///    keeping its link AND gaining `ingredient_name` backfilled from the
///    linked item's name;
///  * `recipes.output_item_id` survives the widening copy-rewrite exactly,
///    NULL ("not added to items yet") becomes representable, and the
///    recreated partial unique index still enforces one live recipe per
///    output item while never colliding NULLs;
///  * stored forecasts read exactly as they were computed.
library;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/data/db/app_database.dart';

import '../generated/migrations/schema.dart';
import 'fixtures.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v4 → v5 produces exactly the declared v5 schema', () async {
    final connection = await verifier.startAt(4);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 5);
  });

  test('v1 → v5 climbs the whole staircase to the declared schema', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 5);
  });

  test('v4 data survives untouched; every legacy recipe line keeps its link '
      'AND gains its backfilled name in recipe_lines_v2; the legacy table is '
      'never rewritten', () async {
    final schema = await verifier.schemaAt(4);
    // Seed through the v4 schema exactly as the phone would have it: a
    // recipe (Bread) over two revisions with linked ingredient lines, and a
    // stored forecast line.
    schema.rawDatabase.execute(
      'INSERT INTO commands '
      '(id, origin, kind, payload_json, status, created_at_micros) '
      "VALUES ('${tid('C1')}', 'form', 'CreateRecipe', '{}', 'applied', 1)",
    );
    for (final (id, name) in [
      (tid('I1'), 'Flour'),
      (tid('I2'), 'Salt'),
      (tid('I3'), 'Bread'),
    ]) {
      schema.rawDatabase.execute(
        'INSERT INTO items '
        '(id, name, unit, pack_size_micros, notes, '
        'created_at_micros, updated_at_micros) '
        "VALUES ('$id', '$name', 'each', 1000000, '', 7, 7)",
      );
    }
    schema.rawDatabase.execute(
      'INSERT INTO recipes '
      '(id, output_item_id, name, created_at_micros) '
      "VALUES ('${tid('R1')}', '${tid('I3')}', 'Bread', 7)",
    );
    for (final (revId, revision) in [(tid('RV1'), 1), (tid('RV2'), 2)]) {
      schema.rawDatabase.execute(
        'INSERT INTO recipe_revisions '
        '(id, recipe_id, revision, yield_micros, source_kind, '
        'created_at_micros) '
        "VALUES ('$revId', '${tid('R1')}', $revision, 2000000, 'form', 7)",
      );
      schema.rawDatabase.execute(
        'INSERT INTO recipe_lines '
        '(revision_id, line_index, ingredient_item_id, '
        'quantity_per_batch_micros) '
        "VALUES ('$revId', 0, '${tid('I1')}', 3000000)",
      );
      schema.rawDatabase.execute(
        'INSERT INTO recipe_lines '
        '(revision_id, line_index, ingredient_item_id, '
        'quantity_per_batch_micros) '
        "VALUES ('$revId', 1, '${tid('I2')}', 500000)",
      );
    }
    schema.rawDatabase.execute(
      'INSERT INTO events '
      '(id, name, scheduled_date, status, planned_exposure, '
      'closed_at_micros, created_at_micros, updated_at_micros) '
      "VALUES ('${tid('E1')}', 'July fair', '2026-07-01', "
      "'closed', 200, 9, 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO forecast_snapshots '
      '(id, event_id, method, method_version, policy, upcoming_exposure, '
      'history_window, inputs_hash, source_command_id, created_at_micros) '
      "VALUES ('${tid('S1')}', '${tid('E1')}', "
      "'direct_median', 3, 'balanced', 200, 12, '${'a' * 64}', "
      "'${tid('C1')}', 8)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO forecast_lines '
      '(snapshot_id, item_id, pack_size_micros, on_hand_micros, '
      'expected_use_micros, planned_micros, load_micros, acquire_micros, '
      'evidence_grade, demand_basis) '
      "VALUES ('${tid('S1')}', '${tid('I3')}', "
      "1000000, 5000000, 2000000, 2200000, 3000000, 0, 'single_event', "
      "'per_person')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Opening the database runs onUpgrade.

    // Items: byte-intact, unit_label NULL — no label appears until typed.
    final items = await (db.select(
      db.items,
    )..orderBy([(i) => OrderingTerm.asc(i.id)])).get();
    expect(items, hasLength(3));
    for (final item in items) {
      expect(item.unitLabel, isNull, reason: 'migration assigns no labels');
      expect(item.createdAtMicros, 7);
      expect(item.packSizeMicros, 1000000);
    }

    // Recipes: the copy-rewrite kept the row exactly; the binding survives.
    final recipe = await (db.select(db.recipes)).getSingle();
    expect(recipe.id, tid('R1'));
    expect(recipe.outputItemId, tid('I3'));
    expect(recipe.name, 'Bread');
    expect(recipe.archivedAtMicros, isNull);
    expect(recipe.createdAtMicros, 7);

    // The append-only legacy table was NOT rewritten: all four rows remain,
    // byte for byte.
    final legacy = await db
        .customSelect(
          'SELECT revision_id, line_index, ingredient_item_id, '
          'quantity_per_batch_micros FROM recipe_lines '
          'ORDER BY revision_id, line_index',
        )
        .get();
    expect(legacy, hasLength(4));
    expect(legacy.first.read<String>('ingredient_item_id'), tid('I1'));
    expect(legacy.first.read<int>('quantity_per_batch_micros'), 3000000);

    // Every legacy line was copied into recipe_lines_v2: link kept, name
    // backfilled from the linked item, unit label NULL, amount intact.
    final copied =
        await (db.select(db.recipeLinesV2)..orderBy([
              (l) => OrderingTerm.asc(l.revisionId),
              (l) => OrderingTerm.asc(l.lineIndex),
            ]))
            .get();
    expect(copied, hasLength(4));
    for (final revisionId in [tid('RV1'), tid('RV2')]) {
      final lines = copied.where((l) => l.revisionId == revisionId).toList();
      expect(lines, hasLength(2));
      expect(lines[0].ingredientItemId, tid('I1'), reason: 'link kept');
      expect(lines[0].ingredientName, 'Flour', reason: 'name backfilled');
      expect(lines[0].unitLabel, isNull);
      expect(lines[0].quantityPerBatchMicros, 3000000);
      expect(lines[1].ingredientItemId, tid('I2'));
      expect(lines[1].ingredientName, 'Salt');
      expect(lines[1].quantityPerBatchMicros, 500000);
    }

    // The stored forecast reads exactly as it was computed.
    final snapshot = await (db.select(db.forecastSnapshots)).getSingle();
    expect(snapshot.methodVersion, 3);
    expect(snapshot.inputsHash, 'a' * 64);
    final line = await (db.select(db.forecastLines)).getSingle();
    expect(line.expectedUseMicros, 2000000);
    expect(line.loadMicros, 3000000);
    expect(db.schemaVersion, 7);
  });

  test('after upgrade: "recipe without any catalog item" is representable, '
      'NULL outputs never collide, and one live recipe per output item '
      'stays enforced by the recreated index', () async {
    final schema = await verifier.schemaAt(4);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await db.customStatement('PRAGMA foreign_keys = OFF');

    // Two live recipes with no output item coexist (NULLs are distinct).
    await db.customStatement(
      'INSERT INTO recipes (id, output_item_id, name, created_at_micros) '
      "VALUES ('${tid('RA')}', NULL, 'Chilli batch', 1)",
    );
    await db.customStatement(
      'INSERT INTO recipes (id, output_item_id, name, created_at_micros) '
      "VALUES ('${tid('RB')}', NULL, 'Soup batch', 1)",
    );

    // One live recipe per output item is still enforced…
    await insertItem(db, tid('IA'), name: 'Chilli');
    await db.customStatement(
      "UPDATE recipes SET output_item_id = '${tid('IA')}' "
      "WHERE id = '${tid('RA')}'",
    );
    await expectLater(
      db.customStatement(
        "UPDATE recipes SET output_item_id = '${tid('IA')}' "
        "WHERE id = '${tid('RB')}'",
      ),
      throwsA(anything),
      reason: 'uidx_recipes_output_live must survive the rewrite',
    );
    // …but only for LIVE recipes: archiving RA frees the output.
    await db.customStatement(
      "UPDATE recipes SET archived_at_micros = 9 WHERE id = '${tid('RA')}'",
    );
    await db.customStatement(
      "UPDATE recipes SET output_item_id = '${tid('IA')}' "
      "WHERE id = '${tid('RB')}'",
    );
  });

  test(
    'after upgrade the new columns accept and reject the right values',
    () async {
      final schema = await verifier.schemaAt(4);
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await db.customStatement('PRAGMA foreign_keys = OFF');

      await insertItem(db, tid('IA'), name: 'Flour');
      // items.unit_label: the CHECK travelled with the ALTER TABLE.
      await db.customStatement(
        "UPDATE items SET unit_label = 'cups' WHERE id = ?",
        [tid('IA')],
      );
      for (final bad in ['', 'x' * 25]) {
        await expectLater(
          db.customStatement('UPDATE items SET unit_label = ? WHERE id = ?', [
            bad,
            tid('IA'),
          ]),
          throwsA(anything),
          reason: '"$bad" is outside the unit_label range',
        );
      }
      // NULL stays legal: counted things carry no label.
      await db.customStatement(
        'UPDATE items SET unit_label = NULL WHERE id = ?',
        [tid('IA')],
      );

      // recipe_lines_v2 CHECKs: name 1-120, label 1-24, amount positive.
      await insertRecipeRevision(db, tid('RV'), recipeId: tid('NOPE'));
      await insertRecipeLineV2(
        db,
        revisionId: tid('RV'),
        ingredientName: 'Flour',
        unitLabel: 'cup',
      );
      for (final insert in [
        () => insertRecipeLineV2(
          db,
          revisionId: tid('RV'),
          lineIndex: 1,
          ingredientName: '',
        ),
        () => insertRecipeLineV2(
          db,
          revisionId: tid('RV'),
          lineIndex: 2,
          ingredientName: 'Salt',
          unitLabel: 'x' * 25,
        ),
        () => insertRecipeLineV2(
          db,
          revisionId: tid('RV'),
          lineIndex: 3,
          ingredientName: 'Salt',
          quantityPerBatchMicros: 0,
        ),
      ]) {
        await expectLater(insert(), throwsA(anything));
      }
    },
  );
}
