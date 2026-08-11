/// §11.2 Tier 1: derived on-hand equals a Dart fold over the same rows
/// (seeded property test), reversals round-trip on-hand exactly, the §4.3
/// label query reads only current revisions of closed events and never
/// touches forecast state, and the v1 seed is present.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/data/db/daos/forecast_dao.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDb();
  });

  tearDown(() => db.close());

  group('v1 seed', () {
    test('workspace_meta singleton with a 26-char uid', () async {
      final row = await db.select(db.workspaceMeta).getSingle();
      expect(row.id, 1);
      expect(row.workspaceUid.length, 26);
      expect(row.displayName, 'My workspace');
      expect(row.createdByAppVersion, seedAppVersion);
    });

    test('default settings', () async {
      final rows = await db.select(db.settings).get();
      final byKey = {for (final r in rows) r.key: r.value};
      expect(byKey, {
        'planning_policy_default': '"balanced"',
        'exposure_label': '"attendance"',
        'history_window_events': '12',
        'seeded_v1': 'true',
      });
    });
  });

  group('derived on-hand', () {
    test('empty ledger sums to zero', () async {
      expect(await db.ledgerDao.onHandMicros(tid('I1')), 0);
      expect(await db.ledgerDao.onHandByItem(), isEmpty);
    });

    test('per-kind sign effects sum exactly', () async {
      await insertCommand(db, tid('C1'));
      await insertItem(db, tid('I1'));
      await insertEvent(db, tid('E1'), status: 'active');
      await insertMovement(
        db,
        tid('M1'),
        itemId: tid('I1'),
        kind: 'receive',
        deltaMicros: 5000000,
        sourceCommandId: tid('C1'),
      );
      await insertMovement(
        db,
        tid('M2'),
        itemId: tid('I1'),
        kind: 'waste',
        deltaMicros: -2000000,
        sourceCommandId: tid('C1'),
      );
      await insertMovement(
        db,
        tid('M3'),
        itemId: tid('I1'),
        kind: 'adjust',
        deltaMicros: -1000000,
        sourceCommandId: tid('C1'),
      );
      await insertMovement(
        db,
        tid('M4'),
        itemId: tid('I1'),
        kind: 'consume',
        deltaMicros: -1000000,
        eventId: tid('E1'),
        sourceCommandId: tid('C1'),
      );
      await insertMovement(
        db,
        tid('M5'),
        itemId: tid('I1'),
        kind: 'reversal',
        deltaMicros: 2000000,
        reversesMovementId: tid('M2'),
        sourceCommandId: tid('C1'),
      );
      expect(await db.ledgerDao.onHandMicros(tid('I1')), 3000000);
      expect(await db.ledgerDao.onHandByItem(), {tid('I1'): 3000000});
    });

    test('negative on-hand is representable, never clamped', () async {
      await insertCommand(db, tid('C1'));
      await insertItem(db, tid('I1'));
      await insertMovement(
        db,
        tid('M1'),
        itemId: tid('I1'),
        kind: 'adjust',
        deltaMicros: -1500000,
        sourceCommandId: tid('C1'),
      );
      expect(await db.ledgerDao.onHandMicros(tid('I1')), -1500000);
    });

    test(
      'SQL sum equals a Dart fold over the same rows (seeded property)',
      () async {
        final rng = Random(20260811);
        await insertCommand(db, tid('C1'));
        await insertEvent(db, tid('E1'), status: 'active');
        final items = [tid('IA'), tid('IB'), tid('IC'), tid('ID')];
        for (final item in items) {
          await insertItem(db, item);
        }

        // Dart-side mirror of every inserted row.
        final rows = <({String id, String itemId, int delta, String kind})>[];
        final reversed = <String>{};

        for (var n = 0; n < 250; n++) {
          // Fixed width: 'M1' and 'M100' would otherwise pad to the same id.
          final id = tid('M${n.toString().padLeft(3, '0')}');
          final itemId = items[rng.nextInt(items.length)];
          final magnitude = rng.nextInt(1000000) + 1;
          final kindPick = rng.nextInt(5);
          switch (kindPick) {
            case 0:
              await insertMovement(
                db,
                id,
                itemId: itemId,
                kind: 'receive',
                deltaMicros: magnitude,
                sourceCommandId: tid('C1'),
                occurredAtMicros: n,
                recordedAtMicros: n,
              );
              rows.add((
                id: id,
                itemId: itemId,
                delta: magnitude,
                kind: 'receive',
              ));
            case 1:
              await insertMovement(
                db,
                id,
                itemId: itemId,
                kind: 'waste',
                deltaMicros: -magnitude,
                sourceCommandId: tid('C1'),
                occurredAtMicros: n,
                recordedAtMicros: n,
              );
              rows.add((
                id: id,
                itemId: itemId,
                delta: -magnitude,
                kind: 'waste',
              ));
            case 2:
              final delta = rng.nextBool() ? magnitude : -magnitude;
              await insertMovement(
                db,
                id,
                itemId: itemId,
                kind: 'adjust',
                deltaMicros: delta,
                sourceCommandId: tid('C1'),
                occurredAtMicros: n,
                recordedAtMicros: n,
              );
              rows.add((id: id, itemId: itemId, delta: delta, kind: 'adjust'));
            case 3:
              await insertMovement(
                db,
                id,
                itemId: itemId,
                kind: 'consume',
                deltaMicros: -magnitude,
                eventId: tid('E1'),
                sourceCommandId: tid('C1'),
                occurredAtMicros: n,
                recordedAtMicros: n,
              );
              rows.add((
                id: id,
                itemId: itemId,
                delta: -magnitude,
                kind: 'consume',
              ));
            case 4:
              // Reverse a random earlier non-reversal row not yet reversed.
              final candidates = rows
                  .where(
                    (r) => r.kind != 'reversal' && !reversed.contains(r.id),
                  )
                  .toList();
              if (candidates.isEmpty) {
                continue;
              }
              final target = candidates[rng.nextInt(candidates.length)];
              reversed.add(target.id);
              await insertMovement(
                db,
                id,
                itemId: target.itemId,
                kind: 'reversal',
                deltaMicros: -target.delta,
                eventId: target.kind == 'consume' ? tid('E1') : null,
                reversesMovementId: target.id,
                sourceCommandId: tid('C1'),
                occurredAtMicros: n,
                recordedAtMicros: n,
              );
              rows.add((
                id: id,
                itemId: target.itemId,
                delta: -target.delta,
                kind: 'reversal',
              ));
          }
        }

        final fold = <String, int>{};
        for (final row in rows) {
          fold[row.itemId] = (fold[row.itemId] ?? 0) + row.delta;
        }

        for (final item in items) {
          expect(
            await db.ledgerDao.onHandMicros(item),
            fold[item] ?? 0,
            reason: 'per-item sum for $item',
          );
        }
        // Every key in the fold has at least one row, so the GROUP BY result
        // must match it exactly — including items whose rows sum to zero.
        expect(await db.ledgerDao.onHandByItem(), fold);
      },
    );

    test('reversal round-trip restores on-hand exactly', () async {
      await insertCommand(db, tid('C1'));
      await insertItem(db, tid('I1'));
      await insertMovement(
        db,
        tid('M1'),
        itemId: tid('I1'),
        kind: 'receive',
        deltaMicros: 7333333,
        sourceCommandId: tid('C1'),
      );
      final before = await db.ledgerDao.onHandMicros(tid('I1'));
      expect(before, 7333333);

      await insertMovement(
        db,
        tid('M2'),
        itemId: tid('I1'),
        kind: 'waste',
        deltaMicros: -2111111,
        sourceCommandId: tid('C1'),
      );
      expect(await db.ledgerDao.onHandMicros(tid('I1')), 5222222);

      await insertMovement(
        db,
        tid('M3'),
        itemId: tid('I1'),
        kind: 'reversal',
        deltaMicros: 2111111,
        reversesMovementId: tid('M2'),
        sourceCommandId: tid('C1'),
      );
      expect(await db.ledgerDao.onHandMicros(tid('I1')), before);
    });
  });

  group('label query (§4.3)', () {
    /// Two closed events with closeouts (one revised), one active and one
    /// cancelled event with (validator-illegal but SQL-representable)
    /// closeouts, one closed event without a closeout.
    Future<void> seedHistory() async {
      await insertCommand(db, tid('C1'));
      await insertItem(db, tid('I1'));
      await insertItem(db, tid('I2'));

      await insertEvent(
        db,
        tid('EA'),
        scheduledDate: '2026-08-01',
        status: 'closed',
        closedAtMicros: 10,
        plannedExposure: 999,
      ); // prediction; must never surface
      await insertEvent(
        db,
        tid('EB'),
        scheduledDate: '2026-08-05',
        status: 'closed',
        closedAtMicros: 20,
      );
      await insertEvent(
        db,
        tid('EC'),
        scheduledDate: '2026-08-03',
        status: 'active',
      );
      await insertEvent(
        db,
        tid('ED'),
        scheduledDate: '2026-08-04',
        status: 'closed',
        closedAtMicros: 30,
      );
      await insertEvent(
        db,
        tid('EE'),
        scheduledDate: '2026-08-02',
        status: 'cancelled',
      );

      await insertCloseout(
        db,
        tid('HA1'),
        eventId: tid('EA'),
        revision: 1,
        confirmedExposure: 100,
        sourceCommandId: tid('C1'),
      );
      await insertCloseoutLine(
        db,
        closeoutId: tid('HA1'),
        itemId: tid('I1'),
        depletionMicros: 10000000,
      );
      await insertCloseout(
        db,
        tid('HA2'),
        eventId: tid('EA'),
        revision: 2,
        supersedesCloseoutId: tid('HA1'),
        confirmedExposure: 120,
        sourceCommandId: tid('C1'),
      );
      await insertCloseoutLine(
        db,
        closeoutId: tid('HA2'),
        itemId: tid('I1'),
        depletionMicros: 8000000,
        stockout: true,
      );

      await insertCloseout(
        db,
        tid('HB1'),
        eventId: tid('EB'),
        revision: 1,
        confirmedExposure: 150,
        sourceCommandId: tid('C1'),
      );
      await insertCloseoutLine(
        db,
        closeoutId: tid('HB1'),
        itemId: tid('I1'),
        depletionMicros: 12000000,
        approximate: true,
      );

      await insertCloseout(
        db,
        tid('HC1'),
        eventId: tid('EC'),
        revision: 1,
        confirmedExposure: 50,
        sourceCommandId: tid('C1'),
      );
      await insertCloseoutLine(
        db,
        closeoutId: tid('HC1'),
        itemId: tid('I1'),
        depletionMicros: 1000000,
      );

      await insertCloseout(
        db,
        tid('HE1'),
        eventId: tid('EE'),
        revision: 1,
        confirmedExposure: 60,
        sourceCommandId: tid('C1'),
      );
      await insertCloseoutLine(
        db,
        closeoutId: tid('HE1'),
        itemId: tid('I1'),
        depletionMicros: 2000000,
      );
    }

    test(
      'returns only latest revisions of closed events, newest first',
      () async {
        await seedHistory();
        final rows = await db.forecastDao.labelHistory(
          tid('I1'),
          historyWindow: 12,
        );
        expect(rows, hasLength(2));

        expect(rows[0].closeoutId, tid('HB1'));
        expect(rows[0].eventId, tid('EB'));
        expect(rows[0].confirmedExposure, 150);
        expect(rows[0].depletionMicros, 12000000);
        expect(rows[0].stockout, isFalse);
        expect(rows[0].approximate, isTrue);

        expect(
          rows[1].closeoutId,
          tid('HA2'),
          reason: 'revision 2 supersedes revision 1',
        );
        expect(rows[1].eventId, tid('EA'));
        expect(
          rows[1].confirmedExposure,
          120,
          reason: 'confirmed exposure, never events.planned_exposure (999)',
        );
        expect(rows[1].depletionMicros, 8000000);
        expect(rows[1].stockout, isTrue);
        expect(rows[1].approximate, isFalse);
      },
    );

    test('LIMIT is the history window', () async {
      await seedHistory();
      final rows = await db.forecastDao.labelHistory(
        tid('I1'),
        historyWindow: 1,
      );
      expect(rows, hasLength(1));
      expect(rows.single.closeoutId, tid('HB1'));
    });

    test('unknown item yields no labels', () async {
      await seedHistory();
      expect(
        await db.forecastDao.labelHistory(tid('I2'), historyWindow: 12),
        isEmpty,
      );
    });

    test('same-date events tie-break on event id, descending', () async {
      await insertCommand(db, tid('C1'));
      await insertItem(db, tid('I1'));
      await insertEvent(
        db,
        tid('TIEA'),
        scheduledDate: '2026-08-06',
        status: 'closed',
        closedAtMicros: 1,
      );
      await insertEvent(
        db,
        tid('TIEB'),
        scheduledDate: '2026-08-06',
        status: 'closed',
        closedAtMicros: 2,
      );
      await insertCloseout(
        db,
        tid('HTA'),
        eventId: tid('TIEA'),
        revision: 1,
        confirmedExposure: 10,
        sourceCommandId: tid('C1'),
      );
      await insertCloseoutLine(
        db,
        closeoutId: tid('HTA'),
        itemId: tid('I1'),
        depletionMicros: 1,
      );
      await insertCloseout(
        db,
        tid('HTB'),
        eventId: tid('TIEB'),
        revision: 1,
        confirmedExposure: 20,
        sourceCommandId: tid('C1'),
      );
      await insertCloseoutLine(
        db,
        closeoutId: tid('HTB'),
        itemId: tid('I1'),
        depletionMicros: 2,
      );

      final rows = await db.forecastDao.labelHistory(
        tid('I1'),
        historyWindow: 12,
      );
      expect(rows.map((r) => r.eventId), [tid('TIEB'), tid('TIEA')]);
    });

    test(
      'forecast tables, predictions, and overrides cannot leak in',
      () async {
        await seedHistory();
        final before = await db.forecastDao.labelHistory(
          tid('I1'),
          historyWindow: 12,
        );

        // Populate every forecast table with loud, valid rows.
        await insertSnapshot(
          db,
          tid('S1'),
          eventId: tid('EA'),
          sourceCommandId: tid('C1'),
          upcomingExposure: 777,
        );
        await insertForecastLine(
          db,
          snapshotId: tid('S1'),
          itemId: tid('I1'),
          onHandMicros: -123456,
          expectedUseMicros: 999999999,
          evidenceGrade: 'observed_range',
        );
        await insertEvidence(
          db,
          snapshotId: tid('S1'),
          itemId: tid('I1'),
          closeoutId: tid('HA1'),
          sourceEventId: tid('EA'),
          exposure: 777,
          depletionMicros: 424242,
          stockout: true,
          approximate: true,
        );
        await insertOverride(
          db,
          tid('O1'),
          snapshotId: tid('S1'),
          itemId: tid('I1'),
          overrideLoadMicros: 555555555,
          reason: 'panic',
        );

        final after = await db.forecastDao.labelHistory(
          tid('I1'),
          historyWindow: 12,
        );
        expect(after, hasLength(before.length));
        for (var i = 0; i < after.length; i++) {
          expect(after[i].closeoutId, before[i].closeoutId);
          expect(after[i].eventId, before[i].eventId);
          expect(after[i].confirmedExposure, before[i].confirmedExposure);
          expect(after[i].depletionMicros, before[i].depletionMicros);
          expect(after[i].stockout, before[i].stockout);
          expect(after[i].approximate, before[i].approximate);
        }
      },
    );

    test('the SQL is structurally unable to read predictions', () {
      const sql = ForecastDao.labelQuerySql;
      expect(sql.contains('forecast'), isFalse);
      expect(sql.contains('planned_exposure'), isFalse);
      expect(sql.contains('closeout_drafts'), isFalse);
      expect(sql, contains("e.status = 'closed'"));
      expect(sql, contains('MAX(h2.revision)'));
    });
  });
}
