/// Schema v4 (folder appearance), in the pattern of the v2 → v3 test: the
/// owner has live data on her phone, so the contract under test is not just
/// "the two new columns exist" but "every v3 row is still there, byte for
/// byte, afterwards — and appearance stays NULL so nothing changes how her
/// folders read until she acts". Migration assigns NO hues and NO icons:
/// NULL renders the effective defaults (hue by position order, icon by
/// starter name); only fresh workspaces are seeded with the reconciliation
/// table's identities.
library;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/folder_appearance.dart';
import 'package:loadout/data/db/app_database.dart';

import '../generated/migrations/schema.dart';
import 'fixtures.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v3 → v4 produces exactly the declared v4 schema', () async {
    final connection = await verifier.startAt(3);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);
  });

  test('v1 → v4 climbs the whole staircase to the declared schema', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);
  });

  test('v3 data survives the upgrade untouched and appearance stays NULL — '
      'the effective defaults take over, no number changes', () async {
    final schema = await verifier.schemaAt(3);
    // Seed through the v3 schema exactly as the phone would have it: a
    // tidy-up folder holding an item, and a stored per-event forecast line.
    schema.rawDatabase.execute(
      'INSERT INTO commands '
      '(id, origin, kind, payload_json, status, created_at_micros) '
      "VALUES ('${'C1'.padRight(26, '0')}', 'form', 'CreateFolder', '{}', "
      "'applied', 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO folders '
      '(id, name, position, demand_basis, always_planned, '
      'created_at_micros, updated_at_micros) '
      "VALUES ('${'F1'.padRight(26, '0')}', 'Drinks', 4, 'per_person', 0, "
      '7, 7)',
    );
    schema.rawDatabase.execute(
      'INSERT INTO items '
      '(id, name, unit, pack_size_micros, folder_id, demand_basis, '
      'per_event_baseline_micros, created_at_micros, updated_at_micros) '
      "VALUES ('${'I1'.padRight(26, '0')}', 'Cola', 'each', 1000000, "
      "'${'F1'.padRight(26, '0')}', 'per_event', 2000000, 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO events '
      '(id, name, scheduled_date, status, planned_exposure, '
      'closed_at_micros, created_at_micros, updated_at_micros) '
      "VALUES ('${'E1'.padRight(26, '0')}', 'July fair', '2026-07-01', "
      "'closed', 200, 9, 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO forecast_snapshots '
      '(id, event_id, method, method_version, policy, upcoming_exposure, '
      'history_window, inputs_hash, source_command_id, created_at_micros) '
      "VALUES ('${'S1'.padRight(26, '0')}', '${'E1'.padRight(26, '0')}', "
      "'direct_median', 3, 'balanced', 200, 12, '${'a' * 64}', "
      "'${'C1'.padRight(26, '0')}', 8)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO forecast_lines '
      '(snapshot_id, item_id, pack_size_micros, on_hand_micros, '
      'expected_use_micros, planned_micros, load_micros, acquire_micros, '
      'evidence_grade, demand_basis) '
      "VALUES ('${'S1'.padRight(26, '0')}', '${'I1'.padRight(26, '0')}', "
      "1000000, 5000000, 2000000, 2200000, 3000000, 0, 'single_event', "
      "'per_event')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Opening the database runs onUpgrade.
    final folder = await (db.select(db.folders)).getSingle();
    expect(folder.id, 'F1'.padRight(26, '0'));
    expect(folder.name, 'Drinks');
    expect(folder.position, 4);
    expect(folder.demandBasis, 'per_person');
    expect(folder.createdAtMicros, 7);
    expect(folder.hueName, isNull, reason: 'migration assigns nothing');
    expect(folder.iconName, isNull, reason: 'migration assigns nothing');

    final item = await (db.select(db.items)).getSingle();
    expect(item.folderId, 'F1'.padRight(26, '0'));
    expect(item.perEventBaselineMicros, 2000000);

    // The stored forecast reads exactly as it was computed.
    final snapshot = await (db.select(db.forecastSnapshots)).getSingle();
    expect(snapshot.methodVersion, 3);
    expect(snapshot.inputsHash, 'a' * 64);
    final line = await (db.select(db.forecastLines)).getSingle();
    expect(line.expectedUseMicros, 2000000);
    expect(line.loadMicros, 3000000);
    expect(line.demandBasis, 'per_event');
    expect(db.schemaVersion, 6);
  });

  test('a fresh database seeds the reconciliation identities: every hue '
      'exactly once, every icon per the table', () async {
    final db = openTestDb();
    addTearDown(db.close);
    final rows = await (db.select(
      db.folders,
    )..orderBy([(f) => OrderingTerm.asc(f.position)])).get();
    expect(rows, hasLength(8));
    for (final row in rows) {
      final appearance = starterFolderAppearance[row.name]!;
      expect(row.hueName, appearance.hue.dbValue, reason: row.name);
      expect(row.iconName, appearance.iconName, reason: row.name);
    }
    expect(
      {for (final row in rows) row.hueName},
      {for (final hue in FolderHue.values) hue.dbValue},
      reason: 'each of the eight hues used exactly once',
    );
  });

  test(
    'after upgrade the new columns accept and reject the right values',
    () async {
      final schema = await verifier.schemaAt(3);
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await db.customStatement('PRAGMA foreign_keys = OFF');

      await insertFolder(db, tid('FA'), name: 'Van shelf');
      // The CHECKs travelled with the ALTER TABLE.
      for (final (column, good, bads) in <(String, Object, List<Object>)>[
        ('hue_name', 'fern', ['teal', '', 'FERN']),
        ('icon_name', 'local_drink', ['', 'x' * 41]),
      ]) {
        await db.customStatement(
          'UPDATE folders SET $column = ? WHERE id = ?',
          [good, tid('FA')],
        );
        for (final bad in bads) {
          await expectLater(
            db.customStatement('UPDATE folders SET $column = ? WHERE id = ?', [
              bad,
              tid('FA'),
            ]),
            throwsA(anything),
            reason: '$bad is outside the $column range',
          );
        }
      }
      // NULL stays legal: "never chose" is the honest default.
      await db.customStatement(
        'UPDATE folders SET hue_name = NULL, icon_name = NULL WHERE id = ?',
        [tid('FA')],
      );
    },
  );
}
