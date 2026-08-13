/// The first real migration (design §4.2: "SchemaVerifier migration tests
/// arrive with the first real migration"). The owner has live data on her
/// phone, so the contract under test is not just "the new columns exist" but
/// "every v1 row is still there, byte for byte, afterwards".
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/data/db/app_database.dart';

import '../generated/migrations/schema.dart';
import 'fixtures.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 → v2 produces exactly the declared v2 schema', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);
  });

  test('v1 data survives the upgrade untouched', () async {
    final schema = await verifier.schemaAt(1);
    // Seed through the v1 schema exactly as the phone would have it: an item
    // with the old unit/pack columns, and a movement whose sum is the
    // derived on-hand.
    schema.rawDatabase.execute(
      'INSERT INTO commands '
      '(id, origin, kind, payload_json, status, created_at_micros) '
      "VALUES ('${'C1'.padRight(26, '0')}', 'form', 'CreateItem', '{}', "
      "'applied', 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO items '
      '(id, name, unit, pack_size_micros, category, notes, '
      'created_at_micros, updated_at_micros) '
      "VALUES ('${'I1'.padRight(26, '0')}', 'Mince (500g packs)', 'kg', "
      "2500000, 'Fridge', 'from the phone', 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO inventory_movements '
      '(id, item_id, kind, delta_micros, source_command_id, '
      'occurred_at_micros, recorded_at_micros, note) '
      "VALUES ('${'M1'.padRight(26, '0')}', '${'I1'.padRight(26, '0')}', "
      "'receive', 9000000, '${'C1'.padRight(26, '0')}', 5, 5, 'first load')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Opening the database runs onUpgrade.
    final item = await (db.select(db.items)).getSingle();
    expect(item.id, 'I1'.padRight(26, '0'));
    expect(item.name, 'Mince (500g packs)');
    expect(item.unit, 'kg', reason: 'v1 units are preserved, not rewritten');
    expect(item.packSizeMicros, 2500000);
    expect(item.category, 'Fridge');
    expect(item.notes, 'from the phone');
    expect(item.createdAtMicros, 7);
    expect(
      item.servesPerUnitMicros,
      isNull,
      reason: 'the new column starts unanswered, never guessed',
    );
    expect(await db.ledgerDao.onHandMicros(item.id), 9000000);
    final movement = await (db.select(db.inventoryMovements)).getSingle();
    expect(movement.note, 'first load');
    expect(await db.schemaVersion, 2);
  });

  test('after upgrade the new columns accept and reject the right values',
      () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await db.customStatement('PRAGMA foreign_keys = OFF');

    await insertItem(db, tid('IA'), name: 'Pizza');
    await db.customStatement(
      'UPDATE items SET serves_per_unit_micros = 4000000 WHERE id = ?',
      [tid('IA')],
    );
    expect(
      (await (db.select(db.items)
                ..where((i) => i.id.equals(tid('IA'))))
              .getSingle())
          .servesPerUnitMicros,
      4000000,
    );
    // The CHECK travelled with the ALTER TABLE.
    for (final bad in [0, -1, 10000000001]) {
      await expectLater(
        db.customStatement(
          'UPDATE items SET serves_per_unit_micros = ? WHERE id = ?',
          [bad, tid('IA')],
        ),
        throwsA(anything),
        reason: '$bad is outside the serves-per-unit range',
      );
    }
  });
}
