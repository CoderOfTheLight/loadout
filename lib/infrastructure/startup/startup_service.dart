/// Four-state startup machine (design §7.3), UI-free.
///
/// Bootstrap inspects key and DB file presence before the router shows
/// anything:
///
/// | DB file | Key | Behavior |
/// |---------|-----|----------|
/// | absent  | absent  | [StartupFreshWorkspace] → `/welcome`; key generated on create |
/// | present | present | normal open; wrong-key probe → [StartupRecovery] (wrongKey) |
/// | present | absent  | [StartupRecovery] (keyMissing) |
/// | absent  | present | old key retained, entry rotated → [StartupFreshWorkspace] |
///
/// Never silently delete a DB file; never auto-create a new DB over the
/// present/absent case. The recovery actions are (a) restore from a Loadout
/// backup file (§8 flow, wired by the shell) and (b) start fresh
/// ([StartupService.startFreshFromRecovery] — the typed confirmation word is
/// the shell's concern), which archives the orphaned ciphertext to
/// `db/orphaned-<utcstamp>.db` (never deleted) and retains the key that
/// opens it — an archive without its key is deleted data.
library;

// The prefer_initializing_formals fix ('this._x' named parameters) needs
// the experimental private-named-parameters language feature, which this
// SDK does not enable; explicit `_x = x` initializers stay.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/diagnostics/diag.dart';
import '../../data/db/app_database.dart';
import '../db/open_database.dart';
import '../files/ios_backup_exclusion.dart';
import '../files/loadout_paths.dart';
import '../files/scratch_space.dart';
import '../security/key_manager.dart';

enum RecoveryReason { keyMissing, wrongKey }

sealed class StartupState {
  const StartupState();
}

/// Route `/welcome`; workspace (and key) created on user action.
final class StartupFreshWorkspace extends StartupState {
  const StartupFreshWorkspace();
}

/// Normal open succeeded; route the shell.
final class StartupWorkspaceOpen extends StartupState {
  const StartupWorkspaceOpen(this.database);
  final AppDatabase database;
}

/// Route `/recovery` ("This device can't unlock the existing data.").
final class StartupRecovery extends StartupState {
  const StartupRecovery(this.reason);
  final RecoveryReason reason;
}

/// Owner of the live [AppDatabase] handle. The restore flow (§8.2) closes and
/// reopens the authoritative DB through this seam.
abstract interface class DatabaseHost {
  /// Throws [StateError] when no database is open.
  AppDatabase get database;
  bool get isOpen;
  Future<AppDatabase> open();
  Future<void> close();
}

final class StartupService implements DatabaseHost {
  StartupService({
    required LoadoutPaths paths,
    required KeyManager keyManager,
    ScratchSpace? scratch,
    Diag diag = const NoopDiag(),
    IosBackupExclusion backupExclusion = const IosBackupExclusion(),
    AppDatabase Function(QueryExecutor executor)? databaseFactory,
  }) : _paths = paths,
       _keyManager = keyManager,
       _scratch = scratch,
       _diag = diag,
       _backupExclusion = backupExclusion,
       _databaseFactory = databaseFactory ?? AppDatabase.new;

  final LoadoutPaths _paths;
  final KeyManager _keyManager;
  final ScratchSpace? _scratch;
  final Diag _diag;
  final IosBackupExclusion _backupExclusion;
  final AppDatabase Function(QueryExecutor executor) _databaseFactory;

  AppDatabase? _db;

  LoadoutPaths get paths => _paths;

  /// Runs the §7.3 machine once, before the router shows anything. Also
  /// sweeps scratch space (§10: on every app start).
  Future<StartupState> bootstrap() async {
    await _scratch?.sweepAll();
    final dbPresent = _paths.databaseFile.existsSync();
    final keyPresent = await _keyManager.hasDatabaseKey();

    if (!dbPresent && !keyPresent) {
      return const StartupFreshWorkspace();
    }
    if (!dbPresent && keyPresent) {
      // §7.3 row 4: treat as fresh workspace; rotate the key entry, continue
      // to /welcome. (Storage-only overwrite — there is no database to
      // rekey.) The outgoing key is retained first: a restore or archive
      // interrupted mid-swap can leave ciphertext on disk that only this key
      // opens, and rotating over it would be silent data loss.
      await _keyManager.retainDatabaseKey(
        'superseded-${LoadoutPaths.utcStamp(DateTime.now().toUtc())}',
      );
      await _keyManager.rekeyDatabase(generateDatabaseKey());
      return const StartupFreshWorkspace();
    }
    if (dbPresent && !keyPresent) {
      _diag.event(DiagEvent.dbKeyMissing);
      return const StartupRecovery(RecoveryReason.keyMissing);
    }
    // present/present: normal open; the wrong-key probe guards mismatch.
    final started = DateTime.now();
    try {
      final db = await open();
      _diag.event(
        DiagEvent.dbOpenOk,
        elapsed: DateTime.now().difference(started),
        schemaVersion: db.schemaVersion,
      );
      return StartupWorkspaceOpen(db);
    } catch (e) {
      await close();
      if (isWrongKeyError(e)) {
        _diag.event(DiagEvent.dbOpenWrongKey);
        return const StartupRecovery(RecoveryReason.wrongKey);
      }
      if (isCipherMissingError(e)) {
        // Build misconfiguration (plain SQLite loaded): refuse to run at all.
        _diag.event(DiagEvent.dbCipherMissing);
      }
      rethrow;
    }
  }

  /// `/welcome/create`: generates the key on first call, creates + seeds the
  /// database. Requires that no database file exists.
  Future<AppDatabase> createFreshWorkspace() async {
    if (_paths.databaseFile.existsSync()) {
      throw StateError('database already exists; refusing to create over it');
    }
    return open();
  }

  /// `/recovery` action (b): archives the orphaned ciphertext (never
  /// deleted), destroys the old key entry, and creates a new workspace under
  /// a new key. The typed confirmation word is validated by the UI.
  Future<AppDatabase> startFreshFromRecovery() async {
    await close();
    final archived = _archiveOrphanedDatabase();
    // Retain the key BEFORE destroying it: the archive we just made is
    // ciphertext under it, and a key-less archive is deleted data.
    if (archived != null) {
      await _keyManager.retainDatabaseKey(archived);
    }
    await _keyManager.destroyDatabaseKey();
    return createFreshWorkspace();
  }

  /// Moves the database aside; returns the archive's label, or null when
  /// there was nothing to archive.
  String? _archiveOrphanedDatabase() {
    final db = _paths.databaseFile;
    if (!db.existsSync()) {
      return null;
    }
    final archived = _paths.orphanedDatabaseFile(DateTime.now().toUtc());
    db.renameSync(archived.path);
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${db.path}$suffix');
      if (sidecar.existsSync()) {
        sidecar.renameSync('${archived.path}$suffix');
      }
    }
    return p.basenameWithoutExtension(archived.path);
  }

  // ------------------------------------------------------------ DatabaseHost

  @override
  AppDatabase get database => _db ?? (throw StateError('no database is open'));

  @override
  bool get isOpen => _db != null;

  @override
  Future<AppDatabase> open() async {
    final existing = _db;
    if (existing != null) {
      return existing;
    }
    _paths.dbDir.createSync(recursive: true);
    final key = await _keyManager.getOrCreateDatabaseKey();
    final db = _databaseFactory(
      openLoadoutExecutor(file: _paths.databaseFile, key: key),
    );
    try {
      // Force the lazy open so wrong-key/cipher failures surface here, run
      // migrations, and prove the workspace row is readable (§7.3, §8.2
      // post-open sanity).
      final rows = await db
          .customSelect('SELECT workspace_uid FROM workspace_meta WHERE id = 1')
          .get();
      if (rows.length != 1) {
        throw StateError('workspace_meta singleton missing');
      }
    } catch (_) {
      await db.close();
      rethrow;
    }
    _db = db;
    // §7.2/§10: exclude db/ and scratch/ from iOS backup. Best-effort no-op
    // off iOS.
    unawaited(_backupExclusion.excludeFromBackup(_paths.dbDir));
    unawaited(_backupExclusion.excludeFromBackup(_paths.scratchDir));
    return db;
  }

  @override
  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
