/// Schema v3 (folders + demand basis), in the pattern of the v1 → v2 test:
/// the owner has live data on her phone, so the contract under test is not
/// just "the new table and columns exist" but "every v2 row is still there,
/// byte for byte, afterwards — and her forecasts read exactly as they were
/// stored". Migration creates NO folders: a migrated workspace gets folders
/// from the tidy-up flow, never from an upgrade; only fresh workspaces are
/// seeded with the eight starters.
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

  test('v2 → v3 produces exactly the declared v3 schema', () async {
    final connection = await verifier.startAt(2);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
  });

  test('v1 → v3 climbs the whole staircase to the declared schema', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
  });

  test('v2 data survives the upgrade untouched, folders stay empty, and the '
      'stored forecast is byte-identical', () async {
    final schema = await verifier.schemaAt(2);
    // Seed through the v2 schema exactly as the phone would have it: an
    // item with a serves-per-unit, a closed event, and a stored forecast
    // snapshot with a line and evidence.
    schema.rawDatabase.execute(
      'INSERT INTO commands '
      '(id, origin, kind, payload_json, status, created_at_micros) '
      "VALUES ('${'C1'.padRight(26, '0')}', 'form', 'CreateItem', '{}', "
      "'applied', 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO items '
      '(id, name, unit, pack_size_micros, serves_per_unit_micros, category, '
      'notes, created_at_micros, updated_at_micros) '
      "VALUES ('${'I1'.padRight(26, '0')}', 'Dish soap', 'each', 1000000, "
      "4000000, 'Cleaning', 'from the phone', 7, 7)",
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
      "'direct_median', 2, 'balanced', 200, 12, '${'a' * 64}', "
      "'${'C1'.padRight(26, '0')}', 8)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO forecast_lines '
      '(snapshot_id, item_id, pack_size_micros, on_hand_micros, '
      'expected_use_micros, planned_micros, load_micros, acquire_micros, '
      'evidence_grade) '
      "VALUES ('${'S1'.padRight(26, '0')}', '${'I1'.padRight(26, '0')}', "
      "1000000, 5000000, 2000000, 2200000, 3000000, 0, 'single_event')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Opening the database runs onUpgrade.
    final item = await (db.select(db.items)).getSingle();
    expect(item.id, 'I1'.padRight(26, '0'));
    expect(item.name, 'Dish soap');
    expect(item.servesPerUnitMicros, 4000000);
    expect(item.category, 'Cleaning');
    expect(item.notes, 'from the phone');
    expect(item.createdAtMicros, 7);
    expect(item.folderId, isNull, reason: 'migration files nothing');
    expect(item.demandBasis, isNull, reason: 'NULL = inherit = per_person');
    expect(item.perEventBaselineMicros, isNull);
    expect(item.perPersonNumerator, isNull);
    expect(item.perPersonDenominator, isNull);

    // A MIGRATED workspace gets no starter folders — the tidy-up flow, not
    // the migration, creates hers.
    expect(await (db.select(db.folders)).get(), isEmpty);

    // The stored forecast reads exactly as it was computed: same numbers,
    // same method version 2, basis column NULL (= per-person, which it was).
    final snapshot = await (db.select(db.forecastSnapshots)).getSingle();
    expect(snapshot.methodVersion, 2);
    expect(snapshot.inputsHash, 'a' * 64);
    final line = await (db.select(db.forecastLines)).getSingle();
    expect(line.expectedUseMicros, 2000000);
    expect(line.loadMicros, 3000000);
    expect(line.demandBasis, isNull);
    expect(line.baselinePerEventMicros, isNull);
    expect(db.schemaVersion, 3);
  });

  test('a fresh database seeds the eight starter folders in packing order; '
      'only Cleaning & setup answers per_event', () async {
    final db = openTestDb();
    addTearDown(db.close);
    final rows = await (db.select(
      db.folders,
    )..orderBy([(f) => OrderingTerm.asc(f.position)])).get();
    expect(
      [for (final row in rows) row.name],
      [
        'Cooked on site',
        'Bought ready to serve',
        'Fresh produce',
        'Bakery',
        'Drinks',
        'Disposables',
        'Cleaning & setup',
        'Sales table',
      ],
    );
    expect([for (final row in rows) row.position], [0, 1, 2, 3, 4, 5, 6, 7]);
    expect({
      for (final row in rows) row.name: row.demandBasis,
    }, containsPair('Cleaning & setup', 'per_event'));
    expect(
      rows.where((row) => row.demandBasis == 'per_event'),
      hasLength(1),
      reason: 'disposables scale with the crowd; only cleaning gear does not',
    );
    expect(
      rows.any((row) => row.alwaysPlanned),
      isFalse,
      reason: '"comes along to every event" is suggested, never assumed',
    );
  });

  test(
    'after upgrade the new columns accept and reject the right values',
    () async {
      final schema = await verifier.schemaAt(2);
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await db.customStatement('PRAGMA foreign_keys = OFF');

      await insertItem(db, tid('IA'), name: 'Soap');
      // The CHECKs travelled with the ALTER TABLE.
      for (final (column, good, bads) in <(String, Object, List<Object>)>[
        ('demand_basis', 'per_event', ['per_stall', '']),
        ('per_event_baseline_micros', 2000000, [0, -1, 1000000000001]),
        ('per_person_numerator', 3, [0, -1, 10001]),
        ('per_person_denominator', 4, [0, -1, 10001]),
      ]) {
        await db.customStatement('UPDATE items SET $column = ? WHERE id = ?', [
          good,
          tid('IA'),
        ]);
        for (final bad in bads) {
          await expectLater(
            db.customStatement('UPDATE items SET $column = ? WHERE id = ?', [
              bad,
              tid('IA'),
            ]),
            throwsA(anything),
            reason: '$bad is outside the $column range',
          );
        }
      }

      // The folders table arrived with its own CHECKs and live-name index.
      await insertFolder(db, tid('F1'), name: 'Van shelf');
      await expectLater(
        insertFolder(db, tid('F2'), name: 'VAN SHELF'),
        throwsA(anything),
        reason: 'live folder names are unique case-insensitively',
      );
      // An archived folder frees its name.
      await db.customStatement(
        'UPDATE folders SET archived_at_micros = 5 WHERE id = ?',
        [tid('F1')],
      );
      await insertFolder(db, tid('F3'), name: 'Van shelf', position: 1);
      await expectLater(
        insertFolder(db, tid('F4'), name: 'Bad basis', demandBasis: 'nope'),
        throwsA(anything),
      );
    },
  );
}
