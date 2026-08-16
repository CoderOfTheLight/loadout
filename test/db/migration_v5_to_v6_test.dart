/// Schema v6 (items learn their barcode), in the pattern of the earlier
/// migration tests: the owner has live data on her phone, so the contract
/// under test is not just "the new shape exists" but:
///
///  * every v5 row survives byte for byte — items gain a NULL barcode
///    ("never scanned") and nothing changes until the owner scans one;
///  * unit labels, folder filing, decoupled recipes (bound AND not-yet-added)
///    and their v2 lines, and stored forecasts all read exactly as they
///    were written;
///  * the new partial index `uidx_items_barcode_live` enforces one LIVE item
///    per payload, never collides NULLs, and frees a barcode on archive
///    exactly as `uidx_items_name_live` frees names;
///  * the CHECK travelled with the ALTER TABLE: payloads are bounded 1-64
///    and NULL stays legal.
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

  test('v5 → v6 produces exactly the declared v6 schema', () async {
    final connection = await verifier.startAt(5);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 6);
  });

  test('every earlier version climbs the staircase to the declared v6 '
      'schema', () async {
    for (final from in [1, 2, 3, 4]) {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 6);
    }
  });

  test('v5 data survives untouched: unit labels, folder filing, decoupled '
      'recipes and their v2 lines, stored forecasts — and every item '
      'arrives with barcode NULL', () async {
    final schema = await verifier.schemaAt(5);
    // Seed through the v5 schema exactly as the phone would have it: a
    // folder with a filed, labelled item; a not-yet-added recipe (v5's new
    // NULL output binding) with one linked and one free v2 line; a stored
    // forecast line.
    schema.rawDatabase.execute(
      'INSERT INTO commands '
      '(id, origin, kind, payload_json, status, created_at_micros) '
      "VALUES ('${tid('C1')}', 'form', 'CreateRecipe', '{}', 'applied', 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO folders '
      '(id, name, position, demand_basis, always_planned, hue_name, '
      'icon_name, created_at_micros, updated_at_micros) '
      "VALUES ('${tid('F1')}', 'Bakery', 0, 'per_person', 0, 'honey', "
      "'bakery_dining', 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO items '
      '(id, name, unit, pack_size_micros, unit_label, folder_id, notes, '
      'created_at_micros, updated_at_micros) '
      "VALUES ('${tid('I1')}', 'Flour', 'each', 1000000, 'cups', "
      "'${tid('F1')}', '', 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO items '
      '(id, name, unit, pack_size_micros, notes, '
      'created_at_micros, updated_at_micros) '
      "VALUES ('${tid('I2')}', 'Salt', 'each', 1000000, '', 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO items '
      '(id, name, unit, pack_size_micros, notes, archived_at_micros, '
      'created_at_micros, updated_at_micros) '
      "VALUES ('${tid('I3')}', 'Retired urn', 'each', 1000000, '', 8, 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO recipes (id, output_item_id, name, created_at_micros) '
      "VALUES ('${tid('R1')}', NULL, 'Bread', 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO recipe_revisions '
      '(id, recipe_id, revision, yield_micros, source_kind, '
      'created_at_micros) '
      "VALUES ('${tid('RV1')}', '${tid('R1')}', 1, 2000000, 'form', 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO recipe_lines_v2 '
      '(revision_id, line_index, ingredient_name, unit_label, '
      'ingredient_item_id, quantity_per_batch_micros) '
      "VALUES ('${tid('RV1')}', 0, 'Flour', 'cups', '${tid('I1')}', 3000000)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO recipe_lines_v2 '
      '(revision_id, line_index, ingredient_name, unit_label, '
      'ingredient_item_id, quantity_per_batch_micros) '
      "VALUES ('${tid('RV1')}', 1, 'A pinch of luck', NULL, NULL, 500000)",
    );
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
      "VALUES ('${tid('S1')}', '${tid('I1')}', "
      "1000000, 5000000, 2000000, 2200000, 3000000, 0, 'single_event', "
      "'per_person')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Opening the database runs onUpgrade.

    // Items: byte-intact, barcode NULL — nothing is scanned by a migration.
    final items = await (db.select(
      db.items,
    )..orderBy([(i) => OrderingTerm.asc(i.id)])).get();
    expect(items, hasLength(3));
    for (final item in items) {
      expect(item.barcode, isNull, reason: 'migration assigns no barcodes');
      expect(item.createdAtMicros, 7);
      expect(item.packSizeMicros, 1000000);
    }
    expect(items[0].unitLabel, 'cups', reason: 'v5 label preserved');
    expect(items[0].folderId, tid('F1'), reason: 'filing preserved');
    expect(items[1].unitLabel, isNull);
    expect(items[2].archivedAtMicros, 8, reason: 'archived rows ride too');

    // The not-yet-added recipe keeps its v5 shape and both v2 lines.
    final recipe = await (db.select(db.recipes)).getSingle();
    expect(recipe.outputItemId, isNull);
    expect(recipe.name, 'Bread');
    final lines = await (db.select(
      db.recipeLinesV2,
    )..orderBy([(l) => OrderingTerm.asc(l.lineIndex)])).get();
    expect(lines, hasLength(2));
    expect(lines[0].ingredientItemId, tid('I1'), reason: 'link kept');
    expect(lines[0].ingredientName, 'Flour');
    expect(lines[0].unitLabel, 'cups');
    expect(lines[1].ingredientItemId, isNull, reason: 'free line stays free');
    expect(lines[1].ingredientName, 'A pinch of luck');

    // The stored forecast reads exactly as it was computed.
    final snapshot = await (db.select(db.forecastSnapshots)).getSingle();
    expect(snapshot.methodVersion, 3);
    expect(snapshot.inputsHash, 'a' * 64);
    final line = await (db.select(db.forecastLines)).getSingle();
    expect(line.expectedUseMicros, 2000000);
    expect(line.loadMicros, 3000000);

    // The new index arrived with the upgrade.
    final index = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE name = 'uidx_items_barcode_live'",
        )
        .get();
    expect(index, hasLength(1));
    expect(db.schemaVersion, 6);
  });

  test('after upgrade: one LIVE item per barcode, NULLs never collide, and '
      'archiving frees the payload for a future item', () async {
    final schema = await verifier.schemaAt(5);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await db.customStatement('PRAGMA foreign_keys = OFF');

    // Any number of never-scanned (NULL) live items coexist.
    await insertItem(db, tid('IA'), name: 'Buns');
    await insertItem(db, tid('IB'), name: 'Rolls');
    await insertItem(db, tid('IC'), name: 'Baps');

    await db.customStatement(
      "UPDATE items SET barcode = '5000112637922' WHERE id = ?",
      [tid('IA')],
    );
    await expectLater(
      db.customStatement(
        "UPDATE items SET barcode = '5000112637922' WHERE id = ?",
        [tid('IB')],
      ),
      throwsA(anything),
      reason: 'two LIVE items may never share one payload',
    );
    // …but archiving the holder frees it, exactly as names free.
    await db.customStatement(
      'UPDATE items SET archived_at_micros = 9 WHERE id = ?',
      [tid('IA')],
    );
    await db.customStatement(
      "UPDATE items SET barcode = '5000112637922' WHERE id = ?",
      [tid('IB')],
    );
  });

  test('after upgrade the new column accepts and rejects the right '
      'values', () async {
    final schema = await verifier.schemaAt(5);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await db.customStatement('PRAGMA foreign_keys = OFF');

    await insertItem(db, tid('IA'), name: 'Buns');
    // items.barcode: the CHECK travelled with the ALTER TABLE.
    await db.customStatement('UPDATE items SET barcode = ? WHERE id = ?', [
      'x' * 64,
      tid('IA'),
    ]);
    for (final bad in ['', 'x' * 65]) {
      await expectLater(
        db.customStatement('UPDATE items SET barcode = ? WHERE id = ?', [
          bad,
          tid('IA'),
        ]),
        throwsA(anything),
        reason: '"$bad" is outside the barcode range',
      );
    }
    // NULL stays legal: never-scanned items carry no barcode.
    await db.customStatement('UPDATE items SET barcode = NULL WHERE id = ?', [
      tid('IA'),
    ]);
  });
}
