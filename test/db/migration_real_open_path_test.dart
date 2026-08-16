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

import '../generated/migrations/schema_v4.dart';

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
    final v4 = DatabaseAtV4(openLoadoutExecutor(file: dbFile, key: key));
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
    final strand = DatabaseAtV4(openLoadoutExecutor(file: dbFile, key: key));
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
}
