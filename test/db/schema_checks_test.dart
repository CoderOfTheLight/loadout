/// §11.2 Tier 1: every SQL CHECK violation throws SqliteException, and the
/// partial unique indices distinguish live from archived rows.
///
/// Foreign keys are switched OFF in this file on purpose: CHECK and index
/// enforcement is independent of referential integrity, and junk parent ids
/// keep each violation isolated to the constraint under test.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDb();
    await db.customStatement('PRAGMA foreign_keys = OFF');
  });

  tearDown(() => db.close());

  Future<void> bad(String sql, [List<Object?> args = const []]) => expectLater(
    db.customStatement(sql, args),
    throwsA(isA<SqliteException>()),
  );

  group('workspace_meta', () {
    test('id must equal 1 (singleton)', () async {
      await bad(
        'INSERT INTO workspace_meta '
        '(id, workspace_uid, created_at_micros, created_by_app_version) '
        'VALUES (2, ?, 1, ?)',
        [tid('WS2'), 'v'],
      );
    });
  });

  group('commands', () {
    test('origin outside form|agent', () async {
      await bad(
        'INSERT INTO commands '
        '(id, origin, kind, payload_json, status, created_at_micros) '
        "VALUES (?, 'robot', 'K', '{}', 'applied', 1)",
        [tid('C1')],
      );
    });

    test('status outside staged|applied|rejected', () async {
      await bad(
        'INSERT INTO commands '
        '(id, origin, kind, payload_json, status, created_at_micros) '
        "VALUES (?, 'form', 'K', '{}', 'pending', 1)",
        [tid('C2')],
      );
    });
  });

  group('items', () {
    test('unit outside the closed list', () async {
      await bad(
        'INSERT INTO items '
        '(id, name, unit, pack_size_micros, created_at_micros, updated_at_micros) '
        "VALUES (?, 'X', 'lb', 1, 1, 1)",
        [tid('I1')],
      );
    });

    test('pack size must be positive', () async {
      await bad(
        'INSERT INTO items '
        '(id, name, unit, pack_size_micros, created_at_micros, updated_at_micros) '
        "VALUES (?, 'X', 'each', 0, 1, 1)",
        [tid('I2')],
      );
    });

    test('serves per unit is NULL or inside [1, 1e10] (v2)', () async {
      Future<void> serves(String id, Object? micros) => db.customStatement(
        'INSERT INTO items (id, name, unit, pack_size_micros, '
        'serves_per_unit_micros, created_at_micros, updated_at_micros) '
        "VALUES (?, ?, 'each', 1, ?, 1, 1)",
        [tid(id), 'X$id', micros],
      );
      // "I don't know" is the honest default and must stay legal.
      await serves('I3', null);
      await serves('I4', 1);
      await serves('I5', 10000000000);
      for (final micros in [0, -1, 10000000001]) {
        await expectLater(
          serves('I6X${micros.toString().replaceAll('-', 'N')}', micros),
          throwsA(isA<SqliteException>()),
        );
      }
    });
  });

  group('events', () {
    test('scheduled_date must be YYYY-MM-DD', () async {
      for (final date in ['2026-8-01', '20260801', '2026/08/01', 'someday']) {
        await bad(
          'INSERT INTO events '
          '(id, name, scheduled_date, created_at_micros, updated_at_micros) '
          "VALUES (?, 'E', ?, 1, 1)",
          [tid('E$date'), date],
        );
      }
    });

    test('status outside the lifecycle list', () async {
      await bad(
        'INSERT INTO events '
        '(id, name, scheduled_date, status, created_at_micros, updated_at_micros) '
        "VALUES (?, 'E', '2026-08-01', 'done', 1, 1)",
        [tid('E1')],
      );
    });

    test('closed requires closed_at_micros', () async {
      await bad(
        'INSERT INTO events '
        '(id, name, scheduled_date, status, closed_at_micros, '
        'created_at_micros, updated_at_micros) '
        "VALUES (?, 'E', '2026-08-01', 'closed', NULL, 1, 1)",
        [tid('E2')],
      );
    });

    test('ends before starts is rejected', () async {
      await bad(
        'INSERT INTO events '
        '(id, name, scheduled_date, starts_at_micros, ends_at_micros, '
        'created_at_micros, updated_at_micros) '
        "VALUES (?, 'E', '2026-08-01', 100, 99, 1, 1)",
        [tid('E3')],
      );
    });

    test('planned_exposure outside [1, 1e6]', () async {
      for (final exposure in [0, -5, 1000001]) {
        await bad(
          'INSERT INTO events '
          '(id, name, scheduled_date, planned_exposure, '
          'created_at_micros, updated_at_micros) '
          "VALUES (?, 'E', '2026-08-01', ?, 1, 1)",
          [tid('E4X$exposure'.replaceAll('-', 'N')), exposure],
        );
      }
    });
  });

  group('event_items', () {
    test('negative position', () async {
      await bad(
        'INSERT INTO event_items (event_id, item_id, position) '
        'VALUES (?, ?, -1)',
        [tid('E9'), tid('I9')],
      );
    });
  });

  group('inventory_movements', () {
    Future<void> badMovement({
      required String id,
      String kind = 'adjust',
      required int delta,
      String? eventId,
      String? reverses,
    }) => bad(
      'INSERT INTO inventory_movements '
      '(id, item_id, kind, delta_micros, event_id, reverses_movement_id, '
      'source_command_id, occurred_at_micros, recorded_at_micros) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1)',
      [tid(id), tid('I1'), kind, delta, eventId, reverses, tid('C1')],
    );

    test('delta may never be zero', () async {
      await badMovement(id: 'M1', delta: 0);
    });

    test('delta magnitude capped at 1e15', () async {
      await badMovement(id: 'M2', delta: 1000000000000001);
      await badMovement(id: 'M3', delta: -1000000000000001);
    });

    test('kind outside the closed list', () async {
      await badMovement(id: 'M4', kind: 'opening', delta: 5);
    });

    test('sign per kind: receive must be positive', () async {
      await badMovement(id: 'M5', kind: 'receive', delta: -5);
    });

    test('sign per kind: consume must be negative', () async {
      await badMovement(
        id: 'M6',
        kind: 'consume',
        delta: 5,
        eventId: tid('E1'),
      );
    });

    test('sign per kind: waste must be negative', () async {
      await badMovement(id: 'M7', kind: 'waste', delta: 5);
    });

    test('reversal requires a target', () async {
      await badMovement(id: 'M8', kind: 'reversal', delta: 5);
    });

    test('a non-reversal may not name a target', () async {
      await badMovement(
        id: 'M9',
        kind: 'receive',
        delta: 5,
        reverses: tid('MX'),
      );
    });

    test('consume requires an event', () async {
      await badMovement(id: 'MA', delta: -5, kind: 'consume');
    });

    test('a movement is reversible at most once (UNIQUE)', () async {
      await insertCommand(db, tid('C1'));
      await insertItem(db, tid('I1'));
      await insertMovement(
        db,
        tid('MB'),
        itemId: tid('I1'),
        kind: 'receive',
        deltaMicros: 5,
        sourceCommandId: tid('C1'),
      );
      await insertMovement(
        db,
        tid('MC'),
        itemId: tid('I1'),
        kind: 'reversal',
        deltaMicros: -5,
        reversesMovementId: tid('MB'),
        sourceCommandId: tid('C1'),
      );
      await badMovement(
        id: 'MD',
        kind: 'reversal',
        delta: -5,
        reverses: tid('MB'),
      );
    });
  });

  group('event_closeouts', () {
    Future<void> badCloseout({
      required String id,
      int revision = 1,
      int exposure = 100,
      String? supersedes,
      String event = 'E1',
    }) => bad(
      'INSERT INTO event_closeouts '
      '(id, event_id, revision, supersedes_closeout_id, confirmed_exposure, '
      'source_command_id, confirmed_at_micros) '
      'VALUES (?, ?, ?, ?, ?, ?, 1)',
      [tid(id), tid(event), revision, supersedes, exposure, tid('C1')],
    );

    test('revision must be positive', () async {
      await badCloseout(id: 'H1', revision: 0);
    });

    test('confirmed_exposure outside [1, 1e6]', () async {
      await badCloseout(id: 'H2', exposure: 0);
      await badCloseout(id: 'H3', exposure: 1000001);
    });

    test('revision 1 may not supersede', () async {
      await badCloseout(id: 'H4', revision: 1, supersedes: tid('HX'));
    });

    test('revision 2+ must supersede', () async {
      await badCloseout(id: 'H5', revision: 2);
    });

    test('(event_id, revision) unique', () async {
      await insertCommand(db, tid('C1'));
      await insertEvent(db, tid('E1'), status: 'closed', closedAtMicros: 1);
      await insertCloseout(
        db,
        tid('H6'),
        eventId: tid('E1'),
        revision: 1,
        confirmedExposure: 10,
        sourceCommandId: tid('C1'),
      );
      await badCloseout(id: 'H7', revision: 1);
    });
  });

  group('closeout_lines', () {
    Future<void> badLine({
      required String closeout,
      int depletion = 0,
      int? loaded,
      int? returned,
      int? waste,
      int stockout = 0,
    }) => bad(
      'INSERT INTO closeout_lines '
      '(closeout_id, item_id, loaded_micros, returned_micros, waste_micros, '
      'depletion_micros, stockout) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [tid(closeout), tid('I1'), loaded, returned, waste, depletion, stockout],
    );

    test('worksheet fields must be nonnegative', () async {
      await badLine(closeout: 'HA', loaded: -1);
      await badLine(closeout: 'HB', returned: -1);
      await badLine(closeout: 'HC', waste: -1);
    });

    test('depletion outside [0, 1e12]', () async {
      await badLine(closeout: 'HD', depletion: -1);
      await badLine(closeout: 'HE', depletion: 1000000000001);
    });

    test(
      'full worksheet must reconcile: depletion = loaded - returned - waste',
      () async {
        await badLine(
          closeout: 'HF',
          loaded: 10,
          returned: 2,
          waste: 1,
          depletion: 5,
        );
      },
    );

    test('partial worksheet is exempt from reconciliation', () async {
      // returned missing: any depletion within cap is accepted.
      await db.customStatement(
        'INSERT INTO closeout_lines '
        '(closeout_id, item_id, loaded_micros, waste_micros, depletion_micros) '
        'VALUES (?, ?, 10, 1, 5)',
        [tid('HG'), tid('I1')],
      );
    });

    test('stockout is a strict boolean', () async {
      await badLine(closeout: 'HH', stockout: 2);
    });
  });

  group('recipe_revisions', () {
    Future<void> badRevision({
      required String id,
      int revision = 1,
      int yieldMicros = 1,
      String sourceKind = 'form',
    }) => bad(
      'INSERT INTO recipe_revisions '
      '(id, recipe_id, revision, yield_micros, source_kind, created_at_micros) '
      'VALUES (?, ?, ?, ?, ?, 1)',
      [tid(id), tid('R1'), revision, yieldMicros, sourceKind],
    );

    test('revision must be positive', () async {
      await badRevision(id: 'RV1', revision: 0);
    });

    test('yield must be positive', () async {
      await badRevision(id: 'RV2', yieldMicros: 0);
    });

    test('source_kind outside form|ocr', () async {
      await badRevision(id: 'RV3', sourceKind: 'import');
    });

    test('(recipe_id, revision) unique', () async {
      await insertRecipeRevision(db, tid('RV4'), recipeId: tid('R1'));
      await badRevision(id: 'RV5');
    });
  });

  group('recipe_lines', () {
    test('negative line index', () async {
      await bad(
        'INSERT INTO recipe_lines '
        '(revision_id, line_index, ingredient_item_id, quantity_per_batch_micros) '
        'VALUES (?, -1, ?, 1)',
        [tid('RV1'), tid('I1')],
      );
    });

    test('quantity per batch must be positive', () async {
      await bad(
        'INSERT INTO recipe_lines '
        '(revision_id, line_index, ingredient_item_id, quantity_per_batch_micros) '
        'VALUES (?, 0, ?, 0)',
        [tid('RV1'), tid('I1')],
      );
    });

    test('(revision_id, ingredient_item_id) unique', () async {
      await insertRecipeLine(
        db,
        revisionId: tid('RV1'),
        ingredientItemId: tid('I1'),
      );
      await bad(
        'INSERT INTO recipe_lines '
        '(revision_id, line_index, ingredient_item_id, quantity_per_batch_micros) '
        'VALUES (?, 1, ?, 1)',
        [tid('RV1'), tid('I1')],
      );
    });
  });

  group('forecast_snapshots', () {
    Future<void> badSnapshot({
      required String id,
      int methodVersion = 1,
      String policy = 'balanced',
      int exposure = 100,
      int window = 12,
    }) => bad(
      'INSERT INTO forecast_snapshots '
      '(id, event_id, method, method_version, policy, upcoming_exposure, '
      'history_window, inputs_hash, source_command_id, created_at_micros) '
      "VALUES (?, ?, 'direct_median', ?, ?, ?, ?, ?, ?, 1)",
      [
        tid(id),
        tid('E1'),
        methodVersion,
        policy,
        exposure,
        window,
        'a' * 64,
        tid('C1'),
      ],
    );

    test('method_version must be positive', () async {
      await badSnapshot(id: 'S1', methodVersion: 0);
    });

    test('policy outside lean|balanced|cautious', () async {
      await badSnapshot(id: 'S2', policy: 'yolo');
    });

    test('upcoming_exposure outside [1, 1e6]', () async {
      await badSnapshot(id: 'S3', exposure: 0);
      await badSnapshot(id: 'S4', exposure: 1000001);
    });

    test('history_window must be positive', () async {
      await badSnapshot(id: 'S5', window: 0);
    });
  });

  group('forecast_lines', () {
    Future<void> badLine({
      int packSize = 1,
      int inbound = 0,
      Object? expectedUse,
      Object? planned,
      Object? load,
      Object? acquire,
      String grade = 'observed_range',
    }) => bad(
      'INSERT INTO forecast_lines '
      '(snapshot_id, item_id, pack_size_micros, on_hand_micros, '
      'confirmed_inbound_micros, expected_use_micros, planned_micros, '
      'load_micros, acquire_micros, evidence_grade) '
      'VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?)',
      [
        tid('S1'),
        tid('I1'),
        packSize,
        inbound,
        expectedUse,
        planned,
        load,
        acquire,
        grade,
      ],
    );

    test('pack size must be positive', () async {
      await badLine(packSize: 0, expectedUse: 1);
    });

    test('nonnegative engine outputs', () async {
      await badLine(inbound: -1, expectedUse: 1);
      await badLine(expectedUse: -1);
      await badLine(expectedUse: 1, planned: -1);
      await badLine(expectedUse: 1, load: -1);
      await badLine(expectedUse: 1, acquire: -1);
    });

    test('evidence_grade outside the closed list', () async {
      await badLine(expectedUse: 1, grade: 'guess');
    });

    test(
      'insufficient_data must have NULL expected_use, and vice versa',
      () async {
        await badLine(grade: 'insufficient_data', expectedUse: 1);
        await badLine(grade: 'observed_range', expectedUse: null);
      },
    );

    test('baseline columns are nonnegative and range-checked (v2)', () async {
      // A stored baseline lives beside the engine outputs, not inside them:
      // grade stays insufficient_data and expected_use stays NULL.
      await insertForecastLine(
        db,
        snapshotId: tid('S1'),
        itemId: tid('I1'),
        baselineServesPerUnitMicros: 4000000,
        baselineExpectedUseMicros: 25000000,
        baselinePlannedMicros: 27500000,
        baselineLoadMicros: 28000000,
        baselineAcquireMicros: 0,
      );
      var seq = 0;
      Future<void> badBaseline(String column, int value) => bad(
        'INSERT INTO forecast_lines '
        '(snapshot_id, item_id, pack_size_micros, on_hand_micros, '
        'evidence_grade, $column) '
        "VALUES (?, ?, 1, 0, 'insufficient_data', ?)",
        [tid('S2'), tid('IB${seq++}'), value],
      );
      await badBaseline('baseline_serves_per_unit_micros', 0);
      await badBaseline('baseline_serves_per_unit_micros', 10000000001);
      await badBaseline('baseline_expected_use_micros', -1);
      await badBaseline('baseline_planned_micros', -1);
      await badBaseline('baseline_load_micros', -1);
      await badBaseline('baseline_acquire_micros', -1);
    });
  });

  group('forecast_evidence', () {
    Future<void> badEvidence({
      int position = 0,
      int exposure = 100,
      int depletion = 0,
      int stockout = 0,
    }) => bad(
      'INSERT INTO forecast_evidence '
      '(snapshot_id, item_id, position, closeout_id, source_event_id, '
      'exposure, depletion_micros, stockout, approximate) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)',
      [
        tid('S1'),
        tid('I1'),
        position,
        tid('H1'),
        tid('E1'),
        exposure,
        depletion,
        stockout,
      ],
    );

    test('negative position', () async {
      await badEvidence(position: -1);
    });

    test('exposure outside [1, 1e6]', () async {
      await badEvidence(exposure: 0);
      await badEvidence(exposure: 1000001);
    });

    test('depletion outside [0, 1e12]', () async {
      await badEvidence(depletion: -1);
      await badEvidence(depletion: 1000000000001);
    });

    test('stockout is a strict boolean', () async {
      await badEvidence(stockout: 2);
    });
  });

  group('forecast_overrides', () {
    test('override load must be nonnegative when present', () async {
      await bad(
        'INSERT INTO forecast_overrides '
        '(id, snapshot_id, item_id, override_load_micros, reason, created_at_micros) '
        "VALUES (?, ?, ?, -1, 'why', 1)",
        [tid('O1'), tid('S1'), tid('I1')],
      );
    });
  });

  group('partial unique indices', () {
    test(
      'live item names unique case-insensitively; archived names free',
      () async {
        await insertItem(db, tid('IA'), name: 'Tortillas');
        await expectLater(
          insertItem(db, tid('IB'), name: 'TORTILLAS'),
          throwsA(isA<SqliteException>()),
        );
        // Master data is mutable: archive the live row, then the name frees up.
        await db.customStatement(
          'UPDATE items SET archived_at_micros = 5 WHERE id = ?',
          [tid('IA')],
        );
        await insertItem(db, tid('IB'), name: 'TORTILLAS');
        // A second archived duplicate is also fine.
        await insertItem(db, tid('IC'), name: 'tortillas', archivedAtMicros: 9);
      },
    );

    test(
      'at most one live recipe per output item; archived recipes free',
      () async {
        await insertRecipe(db, tid('RA'), outputItemId: tid('I1'));
        await expectLater(
          insertRecipe(db, tid('RB'), outputItemId: tid('I1')),
          throwsA(isA<SqliteException>()),
        );
        await db.customStatement(
          'UPDATE recipes SET archived_at_micros = 5 WHERE id = ?',
          [tid('RA')],
        );
        await insertRecipe(db, tid('RB'), outputItemId: tid('I1'));
        await insertRecipe(
          db,
          tid('RC'),
          outputItemId: tid('I1'),
          archivedAtMicros: 9,
        );
      },
    );
  });
}
