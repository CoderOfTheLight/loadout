/// Schema v7 (prices on everything), in the pattern of the earlier
/// migration tests: the owner has live data on her phone, so the contract
/// under test is not just "the new shape exists" but:
///
///  * every v6 row survives byte for byte — items (barcodes included) gain
///    a NULL unit_price_cents ("never priced") and closeout lines gain a
///    NULL unit_price_cents ("price unknown then"); nothing costs anything
///    until the owner types a price;
///  * confirmed closeout history — headers, lines, worksheet numbers,
///    flags — reads exactly as it was written, and the append-only triggers
///    still forbid rewriting it (the additive ADD COLUMN disturbed
///    neither);
///  * the CHECK travelled with both ALTER TABLEs: 1..100000000 cents, NULL
///    stays legal.
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

  test('v6 → v7 produces exactly the declared v7 schema', () async {
    final connection = await verifier.startAt(6);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 7);
  });

  test('every earlier version climbs the staircase to the declared v7 '
      'schema', () async {
    for (final from in [1, 2, 3, 4, 5]) {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 7);
    }
  });

  test('v6 data survives untouched: barcodes, unit labels, filing, and a '
      'confirmed closeout with its lines — and every price column arrives '
      'NULL', () async {
    final schema = await verifier.schemaAt(6);
    // Seed through the v6 schema exactly as the phone would have it: a
    // folder with a filed, labelled, scanned item; a plain item; an
    // archived item; a closed event with a confirmed closeout whose lines
    // carry worksheet numbers and flags.
    schema.rawDatabase.execute(
      'INSERT INTO commands '
      '(id, origin, kind, payload_json, status, created_at_micros) '
      "VALUES ('${tid('C1')}', 'form', 'RecordCloseout', '{}', 'applied', 1)",
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
      '(id, name, unit, pack_size_micros, unit_label, barcode, folder_id, '
      'notes, created_at_micros, updated_at_micros) '
      "VALUES ('${tid('I1')}', 'Flour', 'each', 1000000, 'cups', "
      "'5000112637922', '${tid('F1')}', '', 7, 7)",
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
      'INSERT INTO events '
      '(id, name, scheduled_date, status, planned_exposure, '
      'closed_at_micros, created_at_micros, updated_at_micros) '
      "VALUES ('${tid('E1')}', 'July fair', '2026-07-01', "
      "'closed', 200, 9, 7, 7)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO event_closeouts '
      '(id, event_id, revision, confirmed_exposure, note, '
      'source_command_id, confirmed_at_micros) '
      "VALUES ('${tid('CO1')}', '${tid('E1')}', 1, 180, 'busy day', "
      "'${tid('C1')}', 9)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO closeout_lines '
      '(closeout_id, item_id, loaded_micros, returned_micros, waste_micros, '
      'depletion_micros, stockout, approximate) '
      "VALUES ('${tid('CO1')}', '${tid('I1')}', 40000000, 5000000, 5000000, "
      '30000000, 1, 0)',
    );
    schema.rawDatabase.execute(
      'INSERT INTO closeout_lines '
      '(closeout_id, item_id, depletion_micros, stockout, approximate) '
      "VALUES ('${tid('CO1')}', '${tid('I2')}', 0, 0, 1)",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Opening the database runs onUpgrade.

    // Items: byte-intact, unit_price_cents NULL — a migration prices
    // nothing.
    final items = await (db.select(
      db.items,
    )..orderBy([(i) => OrderingTerm.asc(i.id)])).get();
    expect(items, hasLength(3));
    for (final item in items) {
      expect(item.unitPriceCents, isNull, reason: 'migration assigns no price');
      expect(item.createdAtMicros, 7);
      expect(item.packSizeMicros, 1000000);
    }
    expect(items[0].barcode, '5000112637922', reason: 'v6 barcode preserved');
    expect(items[0].unitLabel, 'cups');
    expect(items[0].folderId, tid('F1'));
    expect(items[1].barcode, isNull);
    expect(items[2].archivedAtMicros, 8, reason: 'archived rows ride too');

    // The confirmed closeout reads exactly as it was written, price NULL =
    // "price unknown then" on every pre-v7 line.
    final header = await (db.select(db.eventCloseouts)).getSingle();
    expect(header.revision, 1);
    expect(header.confirmedExposure, 180);
    expect(header.note, 'busy day');
    final lines = await (db.select(
      db.closeoutLines,
    )..orderBy([(l) => OrderingTerm.asc(l.itemId)])).get();
    expect(lines, hasLength(2));
    expect(lines[0].loadedMicros, 40000000);
    expect(lines[0].returnedMicros, 5000000);
    expect(lines[0].wasteMicros, 5000000);
    expect(lines[0].depletionMicros, 30000000);
    expect(lines[0].stockout, isTrue);
    expect(lines[0].unitPriceCents, isNull);
    expect(lines[1].depletionMicros, 0);
    expect(lines[1].approximate, isTrue);
    expect(lines[1].unitPriceCents, isNull);
    expect(db.schemaVersion, 7);
  });

  // NOTE deliberately absent here: "the append-only triggers still forbid
  // rewriting closeout_lines after v7". SchemaVerifier databases are built
  // from the generated schema, which carries tables and indices but NOT the
  // onCreate customStatement triggers — so that contract is pinned where
  // the triggers actually exist: on a fresh database, in
  // closeout_price_snapshot_test.dart (SQL backstop) and
  // append_only_test.dart.

  test('after upgrade both new columns accept and reject the right '
      'values', () async {
    final schema = await verifier.schemaAt(6);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await db.customStatement('PRAGMA foreign_keys = OFF');

    await insertItem(db, tid('IA'), name: 'Buns');
    // items.unit_price_cents: the CHECK travelled with the ALTER TABLE.
    for (final legal in [1, 100000000]) {
      await db.customStatement(
        'UPDATE items SET unit_price_cents = ? WHERE id = ?',
        [legal, tid('IA')],
      );
    }
    for (final bad in [0, -1, 100000001]) {
      await expectLater(
        db.customStatement(
          'UPDATE items SET unit_price_cents = ? WHERE id = ?',
          [bad, tid('IA')],
        ),
        throwsA(anything),
        reason: '$bad is outside the price range',
      );
    }
    // NULL stays legal: unpriced items carry no price.
    await db.customStatement(
      'UPDATE items SET unit_price_cents = NULL WHERE id = ?',
      [tid('IA')],
    );

    // closeout_lines.unit_price_cents: same CHECK; the table is append-only
    // so each probe is a fresh INSERT.
    await db.customStatement(
      'INSERT INTO closeout_lines '
      '(closeout_id, item_id, depletion_micros, unit_price_cents) '
      "VALUES ('${tid('CO1')}', '${tid('IA')}', 0, 1)",
    );
    await db.customStatement(
      'INSERT INTO closeout_lines '
      '(closeout_id, item_id, depletion_micros, unit_price_cents) '
      "VALUES ('${tid('CO2')}', '${tid('IA')}', 0, 100000000)",
    );
    for (final bad in [0, -1, 100000001]) {
      await expectLater(
        db.customStatement(
          'INSERT INTO closeout_lines '
          '(closeout_id, item_id, depletion_micros, unit_price_cents) '
          "VALUES ('${tid('CO3')}', '${tid('IA')}', 0, ?)",
          [bad],
        ),
        throwsA(anything),
        reason: '$bad is outside the price range',
      );
    }
    await db.customStatement(
      'INSERT INTO closeout_lines '
      '(closeout_id, item_id, depletion_micros, unit_price_cents) '
      "VALUES ('${tid('CO3')}', '${tid('IA')}', 0, NULL)",
    );
  });
}
