/// §7.3 four-state startup machine, exercised against real encrypted
/// databases in temp dirs.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/infrastructure/security/key_manager.dart';
import 'package:loadout/infrastructure/startup/startup_service.dart';

import 'harness.dart';

void main() {
  late SecurityHarness h;

  setUp(() => h = SecurityHarness.create('startup_test'));
  tearDown(() => h.dispose());

  test('absent/absent -> fresh workspace; create seeds and opens', () async {
    expect(await h.startup.bootstrap(), isA<StartupFreshWorkspace>());
    expect(
      await h.keyManager.hasDatabaseKey(),
      isFalse,
      reason: 'key is generated on create, not on bootstrap',
    );

    final db = await h.startup.createFreshWorkspace();
    expect(await h.keyManager.hasDatabaseKey(), isTrue);
    final meta = await db
        .customSelect('SELECT workspace_uid FROM workspace_meta')
        .get();
    expect(meta, hasLength(1));
    expect(h.paths.databaseFile.existsSync(), isTrue);
  });

  test('present/present -> normal open with dbOpenOk', () async {
    await h.startup.createFreshWorkspace();
    await h.startup.close();

    final state = await h.startup.bootstrap();
    expect(state, isA<StartupWorkspaceOpen>());
    expect(h.diag.has(DiagEvent.dbOpenOk), isTrue);
  });

  test('present/absent -> recovery(keyMissing), db untouched', () async {
    await h.startup.createFreshWorkspace();
    await h.startup.close();
    await h.keyManager.destroyDatabaseKey();
    final bytesBefore = h.paths.databaseFile.readAsBytesSync();

    final state = await h.startup.bootstrap();
    expect(
      state,
      isA<StartupRecovery>().having(
        (s) => s.reason,
        'reason',
        RecoveryReason.keyMissing,
      ),
    );
    expect(h.diag.has(DiagEvent.dbKeyMissing), isTrue);
    expect(
      h.paths.databaseFile.readAsBytesSync(),
      bytesBefore,
      reason: 'never silently touch the ciphertext',
    );
  });

  test('wrong key -> recovery(wrongKey), db untouched', () async {
    await h.startup.createFreshWorkspace();
    await h.startup.close();
    await h.keyManager.rekeyDatabase(generateDatabaseKey());

    final state = await h.startup.bootstrap();
    expect(
      state,
      isA<StartupRecovery>().having(
        (s) => s.reason,
        'reason',
        RecoveryReason.wrongKey,
      ),
    );
    expect(h.diag.has(DiagEvent.dbOpenWrongKey), isTrue);
    expect(h.paths.databaseFile.existsSync(), isTrue);
  });

  test('absent/present -> key overwritten, fresh workspace', () async {
    final orphanKey = await h.keyManager.getOrCreateDatabaseKey();

    final state = await h.startup.bootstrap();
    expect(state, isA<StartupFreshWorkspace>());
    expect(await h.keyManager.hasDatabaseKey(), isTrue);
    expect(
      await h.keyManager.getOrCreateDatabaseKey(),
      isNot(equals(orphanKey)),
      reason: '§7.3: overwrite the key entry with a newly generated key',
    );
  });

  test('start fresh from recovery archives the orphaned ciphertext', () async {
    final db = await h.startup.createFreshWorkspace();
    await seedWorkspaceData(db);
    await h.startup.close();
    await h.keyManager.destroyDatabaseKey();
    expect(await h.startup.bootstrap(), isA<StartupRecovery>());

    final fresh = await h.startup.startFreshFromRecovery();
    final rows = await fresh
        .customSelect('SELECT count(*) AS c FROM items')
        .get();
    expect(rows.single.read<int>('c'), 0, reason: 'a brand-new workspace');

    final archived = h.paths.dbDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('orphaned-'))
        .toList();
    expect(
      archived,
      isNotEmpty,
      reason: 'ciphertext is archived, never deleted',
    );
  });

  test('createFreshWorkspace refuses to overwrite an existing db', () async {
    await h.startup.createFreshWorkspace();
    await h.startup.close();
    expect(h.startup.createFreshWorkspace, throwsStateError);
  });
}
