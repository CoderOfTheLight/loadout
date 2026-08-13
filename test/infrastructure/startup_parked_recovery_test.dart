/// §7.3 / §8.2: an interrupted restore must not read as a fresh install.
///
/// `restoreBackup` renames the live workspace to `db/loadout.db.pre-restore`
/// while it re-encrypts the restored payload. Kill the process there — OOM,
/// force quit, reboot — and the next launch finds no database file and a key
/// that still opens the parked one. Bootstrap used to call that a fresh
/// install, rotate the key, and send the owner to `/welcome` with a season of
/// records sitting untouched on disk and no route back.
///
/// Every test here leaves the disk exactly the way the real code leaves it
/// (see [parkLiveWorkspaceAsInterruptedRestore]) and then asserts on real
/// encrypted files through real SQLCipher.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/infrastructure/security/hex.dart';
import 'package:loadout/infrastructure/security/key_manager.dart';
import 'package:loadout/infrastructure/startup/startup_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'harness.dart';

void main() {
  late SecurityHarness h;

  setUp(() => h = SecurityHarness.create('parked_recovery'));
  tearDown(() => h.dispose());

  /// A seeded, closed workspace; returns the device key it is encrypted with.
  Future<Uint8List> seededWorkspace() async {
    final db = await h.startup.createFreshWorkspace();
    await seedWorkspaceData(db);
    await h.startup.close();
    return h.keyManager.getOrCreateDatabaseKey();
  }

  Future<int> itemCount() async {
    final rows = await h.startup.database
        .customSelect('SELECT count(*) AS c FROM items')
        .get();
    return rows.single.read<int>('c');
  }

  File preRestoreFile() =>
      File('${h.paths.databaseFile.path}$preRestoreSuffix');

  List<File> archives() => h.paths.dbDir
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).startsWith('orphaned-'))
      .toList();

  // ------------------------------------------------- detection at bootstrap

  test(
    'an interrupted restore boots to recovery, not to a fresh workspace',
    () async {
      final deviceKey = await seededWorkspace();
      parkLiveWorkspaceAsInterruptedRestore(h.paths);
      expect(h.paths.databaseFile.existsSync(), isFalse);
      expect(await h.keyManager.hasDatabaseKey(), isTrue);

      final state = await h.startup.bootstrap();

      expect(
        state,
        isA<StartupParkedWorkspace>(),
        reason: 'a parked workspace is not a fresh install',
      );
      final parked = (state as StartupParkedWorkspace).candidate;
      expect(parked.kind, ParkedWorkspaceKind.interruptedRestore);
      expect(
        state.reason,
        RecoveryReason.interruptedRestore,
        reason: 'the screen must be able to say what actually happened',
      );
      expect(
        state,
        isA<StartupRecovery>(),
        reason: 'the router pins /recovery on StartupRecovery',
      );
      expect(
        await h.keyManager.getOrCreateDatabaseKey(),
        deviceKey,
        reason: 'NEVER rotate a key while recoverable ciphertext is on disk',
      );
      expect(h.keyManager.retained, isEmpty, reason: 'nothing was superseded');
      expect(h.diag.has(DiagEvent.parkedWorkspaceFound), isTrue);
    },
  );

  test('an orphaned archive alone also boots to recovery', () async {
    await seededWorkspace();
    // start-fresh archives the workspace and destroys its key ...
    await h.startup.startFreshFromRecovery();
    await h.startup.close();
    final keyAfterFresh = await h.keyManager.getOrCreateDatabaseKey();
    // ... and then the new workspace is itself parked by a dead restore, so
    // only archives and a parked copy remain.
    parkLiveWorkspaceAsInterruptedRestore(h.paths);
    // Remove the parked copy so an archive is the ONLY thing left.
    preRestoreFile().renameSync('${h.tempRoot.path}/moved-away.db');

    final state = await h.startup.bootstrap();

    expect(state, isA<StartupParkedWorkspace>());
    expect(
      (state as StartupParkedWorkspace).candidate.kind,
      ParkedWorkspaceKind.archived,
    );
    expect(state.reason, RecoveryReason.archivedWorkspace);
    expect(
      await h.keyManager.getOrCreateDatabaseKey(),
      keyAfterFresh,
      reason: 'no rotation while an archive is on disk',
    );
  });

  test(
    'a genuinely fresh install still rotates and goes to /welcome',
    () async {
      // db absent, key present, NOTHING recoverable on disk: §7.3 row 4 stands.
      final orphanKey = await h.keyManager.getOrCreateDatabaseKey();

      expect(await h.startup.bootstrap(), isA<StartupFreshWorkspace>());
      expect(
        await h.keyManager.getOrCreateDatabaseKey(),
        isNot(orphanKey),
        reason: 'row 4 rotation is unchanged when there is nothing to lose',
      );
    },
  );

  // ---------------------------------------------------- putting it back

  test('recovery puts the workspace back with its rows intact', () async {
    final deviceKey = await seededWorkspace();
    final parkedBytes = () {
      parkLiveWorkspaceAsInterruptedRestore(h.paths);
      return preRestoreFile().readAsBytesSync();
    }();
    final state = await h.startup.bootstrap() as StartupParkedWorkspace;

    final db = await h.startup.recoverParkedWorkspace(state.candidate);

    expect(h.paths.databaseFile.existsSync(), isTrue);
    expect(
      preRestoreFile().existsSync(),
      isFalse,
      reason: 'the parked copy became the live one; it was moved, not copied',
    );
    expect(
      h.paths.databaseFile.readAsBytesSync(),
      parkedBytes,
      reason: 'the very same ciphertext is back in place',
    );
    expect(await itemCount(), 2, reason: 'the seeded workspace, intact');
    final marker = await db
        .customSelect("SELECT value FROM settings WHERE key = 'marker'")
        .get();
    expect(marker.single.read<String>('value'), contains(secretMarker));
    expect(
      await h.keyManager.getOrCreateDatabaseKey(),
      deviceKey,
      reason: 'the device key already opened it; nothing was rotated',
    );
    expect(h.keyManager.retained, isEmpty);
    expect(h.diag.has(DiagEvent.parkedWorkspaceRecovered), isTrue);
    expect(h.startup.isOpen, isTrue);
  });

  test('the recovered workspace boots normally next launch', () async {
    await seededWorkspace();
    parkLiveWorkspaceAsInterruptedRestore(h.paths);
    final state = await h.startup.bootstrap() as StartupParkedWorkspace;
    await h.startup.recoverParkedWorkspace(state.candidate);
    await h.startup.close();

    expect(await h.startup.bootstrap(), isA<StartupWorkspaceOpen>());
    expect(await itemCount(), 2);
    expect(scanParkedWorkspaces(h.paths), isEmpty);
  });

  test('an archive is recovered under its retained key', () async {
    await seededWorkspace();
    final originalKey = await h.keyManager.getOrCreateDatabaseKey();
    // Archive the seeded workspace (key retained), then park the empty
    // workspace start-fresh created: two parked copies, two different keys.
    await h.startup.startFreshFromRecovery();
    await h.startup.close();
    final freshKey = await h.keyManager.getOrCreateDatabaseKey();
    parkLiveWorkspaceAsInterruptedRestore(h.paths);

    final state = await h.startup.bootstrap() as StartupParkedWorkspace;
    expect(state.parked, hasLength(2));
    expect(
      state.candidate.kind,
      ParkedWorkspaceKind.interruptedRestore,
      reason: 'the newest copy is the one offered',
    );

    // Deliberately recover the OLDER archive: it holds the real records.
    final archive = state.parked.firstWhere(
      (w) => w.kind == ParkedWorkspaceKind.archived,
    );
    await h.startup.recoverParkedWorkspace(archive);

    expect(await itemCount(), 2, reason: 'the seeded records came back');
    expect(
      await h.keyManager.getOrCreateDatabaseKey(),
      originalKey,
      reason: 'the retained key that opens the archive is adopted as live',
    );
    expect(
      h.keyManager.retained.values,
      contains(equals(freshKey)),
      reason:
          'the outgoing key still opens the other parked copy — retaining '
          'it before the swap is the difference between kept and lost',
    );
    expect(
      preRestoreFile().existsSync(),
      isTrue,
      reason: 'the copy that was not chosen stays exactly where it is',
    );
  });

  test('several archives: the newest is offered, the rest are kept', () async {
    // Three archives, made in the past so their stamps are unambiguous.
    await seededWorkspace();
    parkLiveWorkspaceAsInterruptedRestore(h.paths);
    final source = preRestoreFile();
    for (final stamp in [
      '20260101000000',
      '20260815093000',
      '20260301000000',
    ]) {
      source.copySync('${h.paths.dbDir.path}/orphaned-$stamp.db');
    }
    source.deleteSync();

    final state = await h.startup.bootstrap() as StartupParkedWorkspace;

    expect(state.parked.map((w) => w.label), [
      'orphaned-20260815093000',
      'orphaned-20260301000000',
      'orphaned-20260101000000',
    ]);
    await h.startup.recoverParkedWorkspace(state.candidate);
    expect(await itemCount(), 2);
    expect(
      archives().map((f) => p.basenameWithoutExtension(f.path)),
      unorderedEquals(['orphaned-20260301000000', 'orphaned-20260101000000']),
      reason: 'only the chosen copy moves; the others are untouched',
    );
  });

  // ---------------------------------------------------------- ugly cases

  test('a live database beside a parked one wins, and the parked copy is '
      'archived with its key rather than deleted', () async {
    final deviceKey = await seededWorkspace();
    parkLiveWorkspaceAsInterruptedRestore(h.paths);
    // The restore got further next time: a new live workspace exists AND the
    // original is still parked (the process died before the cleanup delete).
    final parkedBytes = preRestoreFile().readAsBytesSync();
    await h.startup.createFreshWorkspace();
    await h.startup.close();

    final state = await h.startup.bootstrap();

    expect(state, isA<StartupWorkspaceOpen>(), reason: 'the live one wins');
    expect(await itemCount(), 0, reason: 'the live (new) workspace is open');
    expect(
      preRestoreFile().existsSync(),
      isFalse,
      reason: 'no stale .pre-restore is left for a later rollback to grab',
    );
    final archive = archives().single;
    expect(
      archive.readAsBytesSync(),
      parkedBytes,
      reason: 'kept byte-for-byte, just renamed to an archive',
    );
    expect(
      h.keyManager.retained[p.basenameWithoutExtension(archive.path)],
      deviceKey,
      reason: 'an archive without its key is deleted data',
    );
    expect(
      h.diag.has(DiagEvent.parkedWorkspaceFound),
      isTrue,
      reason: 'the owner can see it happened in /settings/diagnostics',
    );
  });

  test('recovery refuses to overwrite a live workspace', () async {
    await seededWorkspace();
    parkLiveWorkspaceAsInterruptedRestore(h.paths);
    final parked = scanParkedWorkspaces(h.paths).single;
    await h.startup.createFreshWorkspace();
    await h.startup.close();

    await expectLater(
      h.startup.recoverParkedWorkspace(parked),
      throwsA(
        isA<ParkedRecoveryException>().having(
          (e) => e.failure,
          'failure',
          ParkedRecoveryFailure.liveWorkspacePresent,
        ),
      ),
    );
    expect(parked.file.existsSync(), isTrue);
  });

  test(
    'a parked copy no key on this device opens is kept, and said so',
    () async {
      await seededWorkspace();
      parkLiveWorkspaceAsInterruptedRestore(h.paths);
      final parked = scanParkedWorkspaces(h.paths).single;
      final bytesBefore = parked.file.readAsBytesSync();
      // Every key this device holds is now the wrong one.
      await h.keyManager.rekeyDatabase(generateDatabaseKey());
      h.keyManager.retained.clear();

      await expectLater(
        h.startup.recoverParkedWorkspace(parked),
        throwsA(
          isA<ParkedRecoveryException>().having(
            (e) => e.failure,
            'failure',
            ParkedRecoveryFailure.noMatchingKey,
          ),
        ),
      );
      expect(
        parked.file.readAsBytesSync(),
        bytesBefore,
        reason: 'honest refusal, not a silent discard',
      );
      expect(h.paths.databaseFile.existsSync(), isFalse);
      expect(h.diag.has(DiagEvent.parkedWorkspaceUnreadable), isTrue);
    },
  );

  test('no key at all on the device is a distinct, honest refusal', () async {
    await seededWorkspace();
    parkLiveWorkspaceAsInterruptedRestore(h.paths);
    final parked = scanParkedWorkspaces(h.paths).single;
    await h.keyManager.destroyDatabaseKey();

    await expectLater(
      h.startup.recoverParkedWorkspace(parked),
      throwsA(
        isA<ParkedRecoveryException>().having(
          (e) => e.failure,
          'failure',
          ParkedRecoveryFailure.noKeyOnDevice,
        ),
      ),
    );
    expect(parked.file.existsSync(), isTrue);
  });

  test(
    'a parked copy that opens but is not a workspace is left where it is',
    () async {
      final deviceKey = await seededWorkspace();
      parkLiveWorkspaceAsInterruptedRestore(h.paths);
      final parked = scanParkedWorkspaces(h.paths).single;
      // Opens under the device key, passes both integrity sweeps, and still
      // is not a Loadout workspace: exactly the file we must NOT swap in.
      final direct = sqlite3.open(parked.file.path);
      direct.execute('PRAGMA key = "x\'${hexEncode(deviceKey)}\'";');
      direct.execute('DELETE FROM workspace_meta;');
      direct.close();

      await expectLater(
        h.startup.recoverParkedWorkspace(parked),
        throwsA(
          isA<ParkedRecoveryException>().having(
            (e) => e.failure,
            'failure',
            ParkedRecoveryFailure.damaged,
          ),
        ),
      );
      expect(parked.file.existsSync(), isTrue);
      expect(h.paths.databaseFile.existsSync(), isFalse);
      expect(h.diag.has(DiagEvent.parkedWorkspaceUnreadable), isTrue);
    },
  );

  test('corrupted parked ciphertext is refused, never discarded', () async {
    await seededWorkspace();
    parkLiveWorkspaceAsInterruptedRestore(h.paths);
    final parked = scanParkedWorkspaces(h.paths).single;
    final bytes = parked.file.readAsBytesSync();
    for (var i = bytes.length - 40; i < bytes.length; i++) {
      bytes[i] ^= 0xff;
    }
    parked.file.writeAsBytesSync(bytes, flush: true);

    // Which failure it is (page-1 HMAC vs a later page) depends on where the
    // damage landed; that it is refused and kept does not.
    await expectLater(
      h.startup.recoverParkedWorkspace(parked),
      throwsA(isA<ParkedRecoveryException>()),
    );
    expect(parked.file.readAsBytesSync(), bytes);
    expect(h.paths.databaseFile.existsSync(), isFalse);
  });

  test(
    'restoring a backup from the parked state keeps the parked copy',
    () async {
      final deviceKey = await seededWorkspace();
      await h.startup.open();
      final container = await h.backup.createBackup(
        passphrase: 'correct horse',
      );
      final kept = File('${h.tempRoot.path}/kept.loadout');
      container.copySync(kept.path);
      await h.startup.close();
      parkLiveWorkspaceAsInterruptedRestore(h.paths);
      final parkedBytes = preRestoreFile().readAsBytesSync();
      expect(await h.startup.bootstrap(), isA<StartupParkedWorkspace>());

      // The owner takes the other door out of /recovery.
      final preview = await h.backup.validateBackup(
        container: kept,
        passphrase: 'correct horse',
      );
      await h.backup.restoreBackup(preview);

      expect(await itemCount(), 2, reason: 'the backup was restored');
      expect(
        preRestoreFile().readAsBytesSync(),
        parkedBytes,
        reason: 'the restore did not park that copy, so it must not delete it',
      );

      // And the next launch retires it properly rather than leaving a stale
      // .pre-restore for a future rollback to rename back over the live db.
      await h.startup.close();
      expect(await h.startup.bootstrap(), isA<StartupWorkspaceOpen>());
      expect(preRestoreFile().existsSync(), isFalse);
      final archive = archives().single;
      expect(archive.readAsBytesSync(), parkedBytes);
      expect(
        h.keyManager.retained[p.basenameWithoutExtension(archive.path)],
        deviceKey,
      );
    },
  );

  test('probing leaves no staging behind', () async {
    await seededWorkspace();
    parkLiveWorkspaceAsInterruptedRestore(h.paths);
    final state = await h.startup.bootstrap() as StartupParkedWorkspace;
    await h.startup.recoverParkedWorkspace(state.candidate);

    final restoreStaging = Directory('${h.paths.scratchDir.path}/restore');
    expect(
      restoreStaging.existsSync() ? restoreStaging.listSync() : const [],
      isEmpty,
    );
  });

  // ------------------------------------------------ start fresh from here

  test(
    'starting fresh from a parked state keeps the copy AND its key',
    () async {
      final deviceKey = await seededWorkspace();
      parkLiveWorkspaceAsInterruptedRestore(h.paths);
      await h.startup.bootstrap();

      final fresh = await h.startup.startFreshFromRecovery();

      final rows = await fresh
          .customSelect('SELECT count(*) AS c FROM items')
          .get();
      expect(rows.single.read<int>('c'), 0, reason: 'a brand-new workspace');
      expect(preRestoreFile().existsSync(), isFalse);
      final archive = archives().single;
      expect(
        h.keyManager.retained[p.basenameWithoutExtension(archive.path)],
        deviceKey,
        reason:
            'destroying the device key would otherwise finish the job the '
            'interrupted restore started',
      );
      expect(
        await h.keyManager.getOrCreateDatabaseKey(),
        isNot(deviceKey),
        reason: 'the new workspace gets a new key',
      );
    },
  );
}
