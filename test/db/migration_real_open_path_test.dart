/// Migrations must survive the REAL open path, not just the test harness.
///
/// The v5 white-screen on the owner's phone: SchemaVerifier and
/// `AppDatabase.forTesting(NativeDatabase.memory())` migrate on a bare
/// connection, but production opens through [openLoadoutExecutor], whose
/// `setup:` callback runs `PRAGMA foreign_keys = ON` on every connection —
/// BEFORE drift's `onUpgrade`. A migration that rebuilds a table (v5's
/// copy-rewrite of `recipes`) behaves differently under live enforcement.
///
/// This suite creates a genuine v4 database ON A KEYED FILE via the frozen
/// generated schema, seeds it the way the owner's phone was seeded (starter
/// folders, items with links, a recipe with revisions and lines), closes
/// it, and reopens it through the production executor so the v4→v5
/// migration runs exactly as it does on a device.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/infrastructure/db/open_database.dart';
import 'package:loadout/infrastructure/security/key_manager.dart';

import '../generated/migrations/schema_v4.dart' as v4_schema;
import '../generated/migrations/schema_v5.dart' as v5_schema;
import '../generated/migrations/schema_v6.dart' as v6_schema;

void main() {
  late Directory temp;
  late File dbFile;
  late Uint8List key;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('real_open_migration');
    dbFile = File('${temp.path}/loadout.db');
    key = generateDatabaseKey();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// A v4 database on a real keyed file, seeded like a used phone:
  /// workspace row, a folder, two items (one in the folder), a recipe
  /// bound to an output item, one revision, one linked line.
  Future<void> createUsedV4Phone() async {
    final v4 = v4_schema.DatabaseAtV4(
      openLoadoutExecutor(file: dbFile, key: key),
    );
    await v4.customStatement(
      "INSERT INTO workspace_meta (id, workspace_uid, display_name, "
      "created_at_micros, created_by_app_version) "
      "VALUES (1, '01HZZZZZZZZZZZZZZZZZZZZZZZ', 'My stall', 1, '1.0.0')",
    );
    await v4.customStatement(
      "INSERT INTO folders (id, name, position, demand_basis, always_planned, "
      "hue_name, icon_name, created_at_micros, updated_at_micros) "
      "VALUES ('01HFOLDER00000000000000001', 'Cooked on site', 0, "
      "'per_person', 0, 'clay', 'outdoor_grill', 1, 1)",
    );
    await v4.customStatement(
      "INSERT INTO items (id, name, unit, pack_size_micros, folder_id, "
      "created_at_micros, updated_at_micros) "
      "VALUES ('01HITEM000000000000000001', 'Soup', 'each', 1000000, "
      "'01HFOLDER00000000000000001', 1, 1)",
    );
    await v4.customStatement(
      "INSERT INTO items (id, name, unit, pack_size_micros, "
      "created_at_micros, updated_at_micros) "
      "VALUES ('01HITEM000000000000000002', 'Flour', 'each', 1000000, 1, 1)",
    );
    await v4.customStatement(
      "INSERT INTO recipes (id, output_item_id, name, created_at_micros) "
      "VALUES ('01HRECIPE0000000000000001', '01HITEM000000000000000001', "
      "'Soup batch', 1)",
    );
    await v4.customStatement(
      "INSERT INTO recipe_revisions (id, recipe_id, revision, yield_micros, "
      "source_kind, note, created_at_micros) "
      "VALUES ('01HREV0000000000000000001', '01HRECIPE0000000000000001', 1, "
      "10000000, 'form', '', 1)",
    );
    await v4.customStatement(
      "INSERT INTO recipe_lines (revision_id, line_index, "
      "ingredient_item_id, quantity_per_batch_micros) "
      "VALUES ('01HREV0000000000000000001', 0, "
      "'01HITEM000000000000000002', 500000)",
    );
    await v4.close();
  }

  test('THE WHITE-SCREEN PIN: a phone stranded by the pre-atomic v5 rollout '
      '(user_version 4, unit_label already present) completes its migration '
      'instead of dying on "duplicate column name"', () async {
    await createUsedV4Phone();

    // Reproduce the stranded state exactly: the first v5 launch applied the
    // ADD COLUMN and failed later, outside any transaction, leaving
    // user_version at 4. (The CHECK mirrors what drift's addColumn emits;
    // only the column's existence matters to the defect.)
    final strand = v4_schema.DatabaseAtV4(
      openLoadoutExecutor(file: dbFile, key: key),
    );
    await strand.customStatement(
      'ALTER TABLE items ADD COLUMN unit_label TEXT NULL '
      'CHECK (LENGTH("unit_label") BETWEEN 1 AND 24)',
    );
    await strand.close();

    // The owner's next launch: must open, finish the migration, keep data.
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    final version = await db.customSelect('PRAGMA user_version').get();
    expect(version.single.read<int>('user_version'), db.schemaVersion);

    final items = await db
        .customSelect('SELECT name, unit_label FROM items ORDER BY name')
        .get();
    expect(items, hasLength(2));
    expect(items.first.read<String>('name'), 'Flour');
    expect(items.first.read<String?>('unit_label'), isNull);

    final lines = await db
        .customSelect('SELECT ingredient_name FROM recipe_lines_v2')
        .get();
    expect(lines, hasLength(1), reason: 'the backfill still ran exactly once');

    final recipesNullable = await db
        .customSelect(
          'SELECT "notnull" AS nn FROM pragma_table_info(\'recipes\') '
          "WHERE name = 'output_item_id'",
        )
        .get();
    expect(
      recipesNullable.single.read<int>('nn'),
      0,
      reason: 'the copy-rewrite still completed',
    );
    await db.close();
  });

  test('a used v4 phone database migrates through the production open path '
      'with foreign keys enforced', () async {
    await createUsedV4Phone();

    // Reopen exactly as bootstrap does: production executor, same key.
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    // Forces the lazy open, which runs onUpgrade v4→v5 under PRAGMA
    // foreign_keys = ON — the phone's exact condition.
    final version = await db.customSelect('PRAGMA user_version').get();
    expect(version.single.read<int>('user_version'), db.schemaVersion);

    // The copy-rewrite of `recipes` must not have dropped rows or links.
    final recipes = await db
        .customSelect("SELECT id, output_item_id, name FROM recipes")
        .get();
    expect(recipes, hasLength(1));
    expect(
      recipes.single.read<String?>('output_item_id'),
      '01HITEM000000000000000001',
    );

    // The v5 backfill must have carried the line with its link and name.
    final lines = await db
        .customSelect(
          "SELECT ingredient_name, ingredient_item_id FROM recipe_lines_v2",
        )
        .get();
    expect(lines, hasLength(1));
    expect(lines.single.read<String>('ingredient_name'), 'Flour');
    expect(
      lines.single.read<String?>('ingredient_item_id'),
      '01HITEM000000000000000002',
    );

    // Foreign keys must still be intact and enforced after migration.
    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty, reason: 'migration left dangling references');

    await db.close();
  });

  /// A v5 database on a real keyed file, seeded like a used phone:
  /// workspace row, a folder, two items (one filed with a unit label), a
  /// recipe bound to an output item, one revision, one linked
  /// recipe_lines_v2 row.
  Future<void> createUsedV5Phone() async {
    final v5 = v5_schema.DatabaseAtV5(
      openLoadoutExecutor(file: dbFile, key: key),
    );
    await v5.customStatement(
      "INSERT INTO workspace_meta (id, workspace_uid, display_name, "
      "created_at_micros, created_by_app_version) "
      "VALUES (1, '01HZZZZZZZZZZZZZZZZZZZZZZZ', 'My stall', 1, '1.0.0')",
    );
    await v5.customStatement(
      "INSERT INTO folders (id, name, position, demand_basis, always_planned, "
      "hue_name, icon_name, created_at_micros, updated_at_micros) "
      "VALUES ('01HFOLDER00000000000000001', 'Cooked on site', 0, "
      "'per_person', 0, 'clay', 'outdoor_grill', 1, 1)",
    );
    await v5.customStatement(
      "INSERT INTO items (id, name, unit, pack_size_micros, unit_label, "
      "folder_id, created_at_micros, updated_at_micros) "
      "VALUES ('01HITEM000000000000000001', 'Soup', 'each', 1000000, "
      "'ladles', '01HFOLDER00000000000000001', 1, 1)",
    );
    await v5.customStatement(
      "INSERT INTO items (id, name, unit, pack_size_micros, "
      "created_at_micros, updated_at_micros) "
      "VALUES ('01HITEM000000000000000002', 'Flour', 'each', 1000000, 1, 1)",
    );
    await v5.customStatement(
      "INSERT INTO recipes (id, output_item_id, name, created_at_micros) "
      "VALUES ('01HRECIPE0000000000000001', '01HITEM000000000000000001', "
      "'Soup batch', 1)",
    );
    await v5.customStatement(
      "INSERT INTO recipe_revisions (id, recipe_id, revision, yield_micros, "
      "source_kind, note, created_at_micros) "
      "VALUES ('01HREV0000000000000000001', '01HRECIPE0000000000000001', 1, "
      "10000000, 'form', '', 1)",
    );
    await v5.customStatement(
      "INSERT INTO recipe_lines_v2 (revision_id, line_index, "
      "ingredient_name, unit_label, ingredient_item_id, "
      "quantity_per_batch_micros) "
      "VALUES ('01HREV0000000000000000001', 0, 'Flour', 'cups', "
      "'01HITEM000000000000000002', 500000)",
    );
    await v5.close();
  }

  test('a used v5 phone database migrates through the production open path '
      'to the current schema', () async {
    await createUsedV5Phone();

    // Reopen exactly as bootstrap does: production executor, same key.
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    // Forces the lazy open, which runs onUpgrade from v5 under PRAGMA
    // foreign_keys = ON — the phone's exact condition.
    final version = await db.customSelect('PRAGMA user_version').get();
    expect(version.single.read<int>('user_version'), db.schemaVersion);

    // Both items intact: unit_label preserved, barcode NULL — a migration
    // never scans anything.
    final items = await db
        .customSelect(
          'SELECT name, unit_label, barcode FROM items ORDER BY name',
        )
        .get();
    expect(items, hasLength(2));
    expect(items[0].read<String>('name'), 'Flour');
    expect(items[0].read<String?>('unit_label'), isNull);
    expect(items[0].read<String?>('barcode'), isNull);
    expect(items[1].read<String>('name'), 'Soup');
    expect(items[1].read<String?>('unit_label'), 'ladles');
    expect(items[1].read<String?>('barcode'), isNull);

    // The v5 recipe line rides byte for byte.
    final lines = await db
        .customSelect(
          'SELECT ingredient_name, unit_label, ingredient_item_id, '
          'quantity_per_batch_micros FROM recipe_lines_v2',
        )
        .get();
    expect(lines, hasLength(1));
    expect(lines.single.read<String>('ingredient_name'), 'Flour');
    expect(lines.single.read<String?>('unit_label'), 'cups');
    expect(
      lines.single.read<String?>('ingredient_item_id'),
      '01HITEM000000000000000002',
    );
    expect(lines.single.read<int>('quantity_per_batch_micros'), 500000);

    // Foreign keys intact, and the new index arrived.
    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty, reason: 'migration left dangling references');
    final index = await db
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE name = 'uidx_items_barcode_live'",
        )
        .get();
    expect(index, hasLength(1));

    await db.close();
  });

  test('THE WHITE-SCREEN PIN AT v6: a v5 phone stranded mid-v6 (barcode '
      'column — and even the index — already present, user_version still 5) '
      'completes its migration instead of dying on "duplicate column '
      'name"', () async {
    await createUsedV5Phone();

    // Reproduce the stranded state: a hypothetical partial v6 left the ADD
    // COLUMN (and index) behind with user_version still 5. The v6 wrapper
    // makes this unreachable in production — this pins that even if it
    // happened, the block completes instead of wedging the phone the way
    // the pre-atomic v5 rollout did. (The CHECK mirrors what drift's
    // addColumn emits; only existence matters to the defect.)
    final strand = v5_schema.DatabaseAtV5(
      openLoadoutExecutor(file: dbFile, key: key),
    );
    await strand.customStatement(
      'ALTER TABLE items ADD COLUMN barcode TEXT NULL '
      'CHECK (LENGTH("barcode") BETWEEN 1 AND 64)',
    );
    await strand.customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS uidx_items_barcode_live '
      'ON items (barcode) '
      'WHERE archived_at_micros IS NULL AND barcode IS NOT NULL',
    );
    await strand.close();

    // The owner's next launch: must open, finish the migration, keep data.
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    final version = await db.customSelect('PRAGMA user_version').get();
    expect(version.single.read<int>('user_version'), db.schemaVersion);

    final items = await db
        .customSelect(
          'SELECT name, unit_label, barcode FROM items ORDER BY name',
        )
        .get();
    expect(items, hasLength(2));
    expect(items[1].read<String?>('unit_label'), 'ladles');
    expect(items[1].read<String?>('barcode'), isNull);

    final lines = await db
        .customSelect('SELECT ingredient_name FROM recipe_lines_v2')
        .get();
    expect(lines, hasLength(1), reason: 'v5 recipe data kept');

    final index = await db
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE name = 'uidx_items_barcode_live'",
        )
        .get();
    expect(index, hasLength(1), reason: 'exactly one index, no duplicate');

    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty);
    await db.close();
  });

  /// A v6 database on a real keyed file, seeded like a used phone:
  /// workspace row, a folder, two items (one filed with a unit label AND a
  /// barcode), and a closed event with a confirmed closeout whose lines
  /// carry worksheet numbers — the history v7's price snapshot must never
  /// disturb.
  Future<void> createUsedV6Phone() async {
    final v6 = v6_schema.DatabaseAtV6(
      openLoadoutExecutor(file: dbFile, key: key),
    );
    await v6.customStatement(
      "INSERT INTO workspace_meta (id, workspace_uid, display_name, "
      "created_at_micros, created_by_app_version) "
      "VALUES (1, '01HZZZZZZZZZZZZZZZZZZZZZZZ', 'My stall', 1, '1.0.0')",
    );
    await v6.customStatement(
      "INSERT INTO folders (id, name, position, demand_basis, always_planned, "
      "hue_name, icon_name, created_at_micros, updated_at_micros) "
      "VALUES ('01HFOLDER00000000000000001', 'Cooked on site', 0, "
      "'per_person', 0, 'clay', 'outdoor_grill', 1, 1)",
    );
    await v6.customStatement(
      "INSERT INTO items (id, name, unit, pack_size_micros, unit_label, "
      "barcode, folder_id, created_at_micros, updated_at_micros) "
      "VALUES ('01HITEM000000000000000001', 'Soup', 'each', 1000000, "
      "'ladles', '5000112637922', '01HFOLDER00000000000000001', 1, 1)",
    );
    await v6.customStatement(
      "INSERT INTO items (id, name, unit, pack_size_micros, "
      "created_at_micros, updated_at_micros) "
      "VALUES ('01HITEM000000000000000002', 'Flour', 'each', 1000000, 1, 1)",
    );
    await v6.customStatement(
      "INSERT INTO commands (id, origin, kind, payload_json, status, "
      "created_at_micros) "
      "VALUES ('01HCMD0000000000000000001', 'form', 'RecordCloseout', '{}', "
      "'applied', 2)",
    );
    await v6.customStatement(
      "INSERT INTO events (id, name, scheduled_date, status, "
      "planned_exposure, closed_at_micros, created_at_micros, "
      "updated_at_micros) "
      "VALUES ('01HEVENT00000000000000001', 'July fair', '2026-07-01', "
      "'closed', 200, 3, 1, 3)",
    );
    await v6.customStatement(
      "INSERT INTO event_closeouts (id, event_id, revision, "
      "confirmed_exposure, note, source_command_id, confirmed_at_micros) "
      "VALUES ('01HCLOSE00000000000000001', '01HEVENT00000000000000001', 1, "
      "180, 'busy day', '01HCMD0000000000000000001', 3)",
    );
    await v6.customStatement(
      "INSERT INTO closeout_lines (closeout_id, item_id, loaded_micros, "
      "returned_micros, waste_micros, depletion_micros, stockout, "
      "approximate) "
      "VALUES ('01HCLOSE00000000000000001', '01HITEM000000000000000001', "
      "40000000, 5000000, 5000000, 30000000, 1, 0)",
    );
    await v6.customStatement(
      "INSERT INTO closeout_lines (closeout_id, item_id, depletion_micros, "
      "stockout, approximate) "
      "VALUES ('01HCLOSE00000000000000001', '01HITEM000000000000000002', "
      "0, 0, 1)",
    );
    await v6.close();
  }

  test('a used v6 phone database migrates through the production open path '
      'to v7', () async {
    await createUsedV6Phone();

    // Reopen exactly as bootstrap does: production executor, same key.
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    // Forces the lazy open, which runs onUpgrade v6→v7 under PRAGMA
    // foreign_keys = ON — the phone's exact condition.
    final version = await db.customSelect('PRAGMA user_version').get();
    expect(version.single.read<int>('user_version'), 7);

    // Both items intact: barcode preserved, unit_price_cents NULL — a
    // migration prices nothing.
    final items = await db
        .customSelect(
          'SELECT name, unit_label, barcode, unit_price_cents FROM items '
          'ORDER BY name',
        )
        .get();
    expect(items, hasLength(2));
    expect(items[0].read<String>('name'), 'Flour');
    expect(items[0].read<String?>('barcode'), isNull);
    expect(items[0].read<int?>('unit_price_cents'), isNull);
    expect(items[1].read<String>('name'), 'Soup');
    expect(items[1].read<String?>('unit_label'), 'ladles');
    expect(items[1].read<String?>('barcode'), '5000112637922');
    expect(items[1].read<int?>('unit_price_cents'), isNull);

    // The confirmed closeout rides byte for byte, its lines stamped NULL =
    // "price unknown then".
    final header = await db
        .customSelect(
          'SELECT revision, confirmed_exposure, note FROM event_closeouts',
        )
        .get();
    expect(header.single.read<int>('revision'), 1);
    expect(header.single.read<int>('confirmed_exposure'), 180);
    expect(header.single.read<String>('note'), 'busy day');
    final lines = await db
        .customSelect(
          'SELECT item_id, loaded_micros, returned_micros, waste_micros, '
          'depletion_micros, stockout, unit_price_cents FROM closeout_lines '
          'ORDER BY item_id',
        )
        .get();
    expect(lines, hasLength(2));
    expect(lines[0].read<int?>('loaded_micros'), 40000000);
    expect(lines[0].read<int?>('returned_micros'), 5000000);
    expect(lines[0].read<int?>('waste_micros'), 5000000);
    expect(lines[0].read<int>('depletion_micros'), 30000000);
    expect(lines[0].read<int>('stockout'), 1);
    expect(lines[0].read<int?>('unit_price_cents'), isNull);
    expect(lines[1].read<int>('depletion_micros'), 0);
    expect(lines[1].read<int?>('unit_price_cents'), isNull);

    // Foreign keys intact after migrating under live enforcement.
    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty, reason: 'migration left dangling references');

    await db.close();
  });

  test('THE WHITE-SCREEN PIN AT v7: a v6 phone stranded mid-v7 (one of the '
      'two price columns already present, user_version still 6) completes '
      'its migration instead of dying on "duplicate column name"', () async {
    await createUsedV6Phone();

    // Reproduce the stranded state: a hypothetical partial v7 left the
    // items ADD COLUMN behind with user_version still 6 and the
    // closeout_lines column never added. The atomic wrapper makes this
    // unreachable in production — this pins that even if it happened, the
    // guarded block completes the remainder instead of wedging the phone
    // the way the pre-atomic v5 rollout did. (The CHECK mirrors what
    // drift's addColumn emits; only the column's existence matters to the
    // defect.)
    final strand = v6_schema.DatabaseAtV6(
      openLoadoutExecutor(file: dbFile, key: key),
    );
    await strand.customStatement(
      'ALTER TABLE items ADD COLUMN unit_price_cents INTEGER NULL '
      'CHECK ("unit_price_cents" BETWEEN 1 AND 100000000)',
    );
    await strand.close();

    // The owner's next launch: must open, finish the migration, keep data.
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    final version = await db.customSelect('PRAGMA user_version').get();
    expect(version.single.read<int>('user_version'), 7);

    // The other half of v7 arrived exactly once…
    final lineColumns = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM pragma_table_info('closeout_lines') "
          "WHERE name = 'unit_price_cents'",
        )
        .get();
    expect(lineColumns.single.read<int>('c'), 1);
    // …the stranded half was not re-added…
    final itemColumns = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM pragma_table_info('items') "
          "WHERE name = 'unit_price_cents'",
        )
        .get();
    expect(itemColumns.single.read<int>('c'), 1);

    // …and the phone's data is intact.
    final items = await db
        .customSelect(
          'SELECT name, barcode, unit_price_cents FROM items ORDER BY name',
        )
        .get();
    expect(items, hasLength(2));
    expect(items[1].read<String?>('barcode'), '5000112637922');
    expect(items[1].read<int?>('unit_price_cents'), isNull);
    final lines = await db
        .customSelect('SELECT depletion_micros FROM closeout_lines')
        .get();
    expect(lines, hasLength(2), reason: 'closeout history kept');

    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty);
    await db.close();
  });
}
