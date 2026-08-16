/// Startup machine (design §7.3), UI-free.
///
/// Bootstrap inspects the `db/` directory and the key store before the router
/// shows anything:
///
/// | DB file | Parked copy | Key | Behavior |
/// |---------|-------------|-----|----------|
/// | absent  | none    | absent  | [StartupFreshWorkspace] → `/welcome`; key generated on create |
/// | present | any     | present | normal open; wrong-key probe → [StartupRecovery] (wrongKey) |
/// | present | any     | absent  | [StartupRecovery] (keyMissing) |
/// | absent  | none    | present | old key retained, entry rotated → [StartupFreshWorkspace] |
/// | absent  | **some**| any     | [StartupParkedWorkspace] → `/recovery`; **no key is rotated** |
///
/// The last row is the interrupted-restore hole. `restoreBackup` renames the
/// live workspace to `db/loadout.db.pre-restore` while it re-encrypts the
/// restored payload (§8.2); a process death in that window leaves no live
/// database and a key that still opens the parked one. Reading that as a
/// fresh install — rotating the key and routing to `/welcome` — throws away a
/// season of records that is sitting right there on disk. So bootstrap looks
/// for parked ciphertext (`.pre-restore`, and the `orphaned-*` archives
/// start-fresh leaves) BEFORE it concludes anything, and never rotates or
/// destroys a key while recoverable ciphertext exists.
///
/// Never silently delete a DB file; never auto-create a new DB over the
/// present/absent case. The recovery actions are (a) put a parked workspace
/// back ([StartupService.recoverParkedWorkspace]), (b) restore from a Loadout
/// backup file (§8 flow, wired by the shell) and (c) start fresh
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

// Uint8List comes from here (drift re-exports dart:typed_data).
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
// Prefixed: `package:drift/drift.dart` and `package:sqlite3/sqlite3.dart`
// both export names that would otherwise collide here.
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../core/diagnostics/diag.dart';
import '../../data/db/app_database.dart';
import '../db/open_database.dart';
import '../files/ios_backup_exclusion.dart';
import '../files/loadout_paths.dart';
import '../files/scratch_space.dart';
import '../security/hex.dart';
import '../security/key_manager.dart';
import 'parked_workspace.dart';

export 'parked_workspace.dart';

enum RecoveryReason {
  keyMissing,
  wrongKey,

  /// No live database, but a restore parked the original beside it
  /// (`db/loadout.db.pre-restore`) and died before the swap.
  interruptedRestore,

  /// No live database, but an `orphaned-*` archive from an earlier
  /// start-fresh / workspace reset is still on disk.
  archivedWorkspace,
}

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

/// Route `/recovery`. [parked] lists every recoverable workspace copy found
/// in `db/`, newest first — empty in the plain key-missing/wrong-key cases,
/// non-empty whenever putting a copy back is a real option.
///
/// `base` rather than `final` so [StartupParkedWorkspace] can specialise it
/// while every `is StartupRecovery` check (the router's `/recovery` pin, the
/// bootstrap switch) keeps working unchanged.
base class StartupRecovery extends StartupState {
  const StartupRecovery(this.reason, {this.parked = const []});
  final RecoveryReason reason;
  final List<ParkedWorkspace> parked;
}

/// Route `/recovery` with the put-it-back action: there is no live database,
/// but at least one parked workspace is on disk. Distinct from the
/// key-missing/wrong-key recovery states because nothing here is broken —
/// the data is intact and openable, it is just in the wrong place.
final class StartupParkedWorkspace extends StartupRecovery {
  StartupParkedWorkspace(List<ParkedWorkspace> parked)
    : assert(parked.isNotEmpty, 'a parked state needs a parked workspace'),
      super(
        parked.first.kind == ParkedWorkspaceKind.interruptedRestore
            ? RecoveryReason.interruptedRestore
            : RecoveryReason.archivedWorkspace,
        parked: parked,
      );

  /// The copy the recovery screen offers: the newest one. The rest stay
  /// exactly where they are.
  ParkedWorkspace get candidate => parked.first;
}

/// Why putting a parked workspace back could not be done. Every one of these
/// leaves the parked copy exactly where it was.
enum ParkedRecoveryFailure {
  /// A live `db/loadout.db` exists — it wins, always.
  liveWorkspacePresent,

  /// The parked file is gone (deleted or already recovered elsewhere).
  missing,

  /// No key at all is stored on this device.
  noKeyOnDevice,

  /// Keys are stored, but none of them opens this copy.
  noMatchingKey,

  /// A key opens it, but the ciphertext fails its integrity checks or is not
  /// a Loadout workspace.
  damaged,

  /// It validated, but the real open (drift migrations, workspace_meta
  /// sanity) failed; the swap was undone.
  openFailed,
}

final class ParkedRecoveryException implements Exception {
  const ParkedRecoveryException(this.failure, [this.detail]);
  final ParkedRecoveryFailure failure;

  /// Type name only — never a message, path, or SQL (§10).
  final String? detail;

  @override
  String toString() => 'ParkedRecoveryException(${failure.name})';
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

  /// Where a parked copy is staged for validation. Falls back to the
  /// canonical scratch root when no [ScratchSpace] was injected, so probing
  /// never depends on composition-root wiring; §10's start-of-run sweep
  /// clears it either way if we die mid-probe.
  late final ScratchSpace _probeScratch =
      _scratch ?? AppSupportScratchSpace(root: _paths.scratchDir, diag: _diag);

  /// Runs the §7.3 machine once, before the router shows anything. Also
  /// sweeps scratch space (§10: on every app start).
  Future<StartupState> bootstrap() async {
    await _scratch?.sweepAll();
    final keyPresent = await _keyManager.hasDatabaseKey();

    if (_paths.databaseFile.existsSync()) {
      // A live workspace always wins over anything parked beside it: the
      // §8.2 swap completed, so `loadout.db` is the authoritative copy. The
      // parked one is kept — retired to an `orphaned-*` archive with its key
      // retained, never deleted — both so the owner still has it and so a
      // later restore's rollback cannot rename a stale `.pre-restore` back
      // over a newer workspace.
      await _retireStaleParkedCopy();
      if (!keyPresent) {
        _diag.event(DiagEvent.dbKeyMissing);
        return StartupRecovery(
          RecoveryReason.keyMissing,
          parked: scanParkedWorkspaces(_paths),
        );
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
          return StartupRecovery(
            RecoveryReason.wrongKey,
            parked: scanParkedWorkspaces(_paths),
          );
        }
        if (isCipherMissingError(e)) {
          // Build misconfiguration (plain SQLite loaded): refuse to run.
          _diag.event(DiagEvent.dbCipherMissing);
          rethrow;
        }
        // Anything else that stops the open — a migration failure above
        // all — must leave a trace. The v5 rollout died silently here: the
        // diagnostic log showed only the startup sweep, and the actual
        // error had to be dug out with a profile build's console.
        _diag.event(
          DiagEvent.migrationFail,
          errorType: e.runtimeType.toString(),
        );
        rethrow;
      }
    }

    // No live database. Before this can mean "fresh install", the parked
    // copies have to be ruled out — concluding otherwise rotates the key
    // over ciphertext only that key opens.
    final parked = scanParkedWorkspaces(_paths);
    if (parked.isNotEmpty) {
      _diag.event(DiagEvent.parkedWorkspaceFound, count: parked.length);
      return StartupParkedWorkspace(parked);
    }
    if (!keyPresent) {
      return const StartupFreshWorkspace();
    }
    // §7.3 row 4: nothing recoverable on disk, so treat as a fresh
    // workspace; rotate the key entry and continue to /welcome.
    // (Storage-only overwrite — there is no database to rekey.) The outgoing
    // key is retained first: it is the last thing that could open ciphertext
    // this scan did not recognise.
    await _keyManager.retainDatabaseKey(
      'superseded-${LoadoutPaths.utcStamp(DateTime.now().toUtc())}',
    );
    await _keyManager.rekeyDatabase(generateDatabaseKey());
    return const StartupFreshWorkspace();
  }

  /// `/welcome/create`: generates the key on first call, creates + seeds the
  /// database. Requires that no database file exists.
  Future<AppDatabase> createFreshWorkspace() async {
    if (_paths.databaseFile.existsSync()) {
      throw StateError('database already exists; refusing to create over it');
    }
    return open();
  }

  /// `/recovery` action (a): put [parked] back at `db/loadout.db` and open
  /// it.
  ///
  /// Validated before anything moves, with the care §8.2 takes over a
  /// restore payload: a copy is staged in scratch, every key this device
  /// holds is tried against it, and the winner has to survive
  /// `cipher_integrity_check`, `integrity_check`, a sane `user_version`, and
  /// a `workspace_meta` singleton. Only then is the parked file renamed into
  /// place — a rename, so the copy is never destroyed; if the real open
  /// still fails, the rename and any key change are undone and the copy is
  /// back exactly where it started.
  Future<AppDatabase> recoverParkedWorkspace(ParkedWorkspace parked) async {
    if (_paths.databaseFile.existsSync()) {
      throw const ParkedRecoveryException(
        ParkedRecoveryFailure.liveWorkspacePresent,
      );
    }
    if (!parked.file.existsSync()) {
      throw const ParkedRecoveryException(ParkedRecoveryFailure.missing);
    }
    await close();

    final key = await _probeParkedWorkspace(parked);
    final previousKey = await _keyManager.hasDatabaseKey()
        ? await _keyManager.getOrCreateDatabaseKey()
        : null;
    final rekeyed = previousKey == null || !_sameKey(previousKey, key);
    if (rekeyed) {
      // Retain the outgoing key before it is replaced (it may be the only
      // thing that opens some other archive), then adopt the one that opens
      // the workspace we are putting back.
      await _keyManager.retainDatabaseKey(
        'superseded-${LoadoutPaths.utcStamp(DateTime.now().toUtc())}',
      );
      await _keyManager.rekeyDatabase(key);
    }

    final moved = <(File source, File target)>[];
    try {
      for (final (suffix, source) in parked.existingMembers()) {
        final target = File('${_paths.databaseFile.path}$suffix');
        source.renameSync(target.path);
        moved.add((source, target));
      }
      final db = await open();
      _diag.event(
        DiagEvent.parkedWorkspaceRecovered,
        schemaVersion: db.schemaVersion,
      );
      return db;
    } catch (e) {
      await close();
      for (final (source, target) in moved.reversed) {
        if (target.existsSync()) {
          target.renameSync(source.path);
        }
      }
      if (rekeyed && previousKey != null) {
        await _keyManager.rekeyDatabase(previousKey);
      }
      _diag.event(
        DiagEvent.parkedWorkspaceUnreadable,
        errorType: e.runtimeType.toString(),
      );
      throw ParkedRecoveryException(
        ParkedRecoveryFailure.openFailed,
        e.runtimeType.toString(),
      );
    }
  }

  /// `/recovery` action (c): archives the orphaned ciphertext (never
  /// deleted), destroys the old key entry, and creates a new workspace under
  /// a new key. The typed confirmation word is validated by the UI.
  Future<AppDatabase> startFreshFromRecovery() async {
    await close();
    // A parked `.pre-restore` copy is ciphertext under the CURRENT device
    // key. Retire it to an archive (which retains that key) BEFORE the key
    // is destroyed below, or starting fresh would quietly finish the job the
    // interrupted restore started.
    await _retireStaleParkedCopy();
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
    final archived = _freshArchiveFile();
    db.renameSync(archived.path);
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${db.path}$suffix');
      if (sidecar.existsSync()) {
        sidecar.renameSync('${archived.path}$suffix');
      }
    }
    return p.basenameWithoutExtension(archived.path);
  }

  /// Renames a `.pre-restore` copy to an `orphaned-*` archive and retains the
  /// key that opens it. Kept, labelled, and no longer mistakable for a
  /// restore still in flight. No-op when nothing is parked.
  Future<void> _retireStaleParkedCopy() async {
    final parked = File('${_paths.databaseFile.path}$preRestoreSuffix');
    if (!parked.existsSync()) {
      return;
    }
    final archived = _freshArchiveFile();
    // Retain first: after the rename the file's only key is the live one.
    // No-op when no key is stored, which is the keyMissing case — the file
    // still survives, and its key may yet come back.
    await _keyManager.retainDatabaseKey(
      p.basenameWithoutExtension(archived.path),
    );
    parked.renameSync(archived.path);
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File(
        '${_paths.databaseFile.path}$suffix$preRestoreSuffix',
      );
      if (sidecar.existsSync()) {
        sidecar.renameSync('${archived.path}$suffix');
      }
    }
    _diag.event(DiagEvent.parkedWorkspaceFound, count: 1);
  }

  /// An `orphaned-<utcstamp>.db` path that is not taken. Two archives inside
  /// the same second would otherwise collide, and the second rename would
  /// destroy the first archive.
  File _freshArchiveFile() {
    final now = DateTime.now().toUtc();
    final base = _paths.orphanedDatabaseFile(now);
    if (!base.existsSync()) {
      return base;
    }
    final stem = base.path.substring(0, base.path.length - '.db'.length);
    for (var n = 2; ; n++) {
      final candidate = File('$stem-$n.db');
      if (!candidate.existsSync()) {
        return candidate;
      }
    }
  }

  // -------------------------------------------------- parked-copy probing

  /// The key that opens [parked], or a [ParkedRecoveryException] saying
  /// honestly why none does. Runs entirely against a staged copy: the parked
  /// file itself is never opened, checkpointed, or otherwise touched.
  Future<Uint8List> _probeParkedWorkspace(ParkedWorkspace parked) async {
    final candidates = await _candidateKeys(parked);
    if (candidates.isEmpty) {
      _diag.event(DiagEvent.parkedWorkspaceUnreadable);
      throw const ParkedRecoveryException(ParkedRecoveryFailure.noKeyOnDevice);
    }
    final session = await _probeScratch.createSession('restore');
    try {
      final staged = File(p.join(session.path, 'parked.db'));
      for (final (suffix, member) in parked.existingMembers()) {
        if (suffix == '-shm') {
          continue; // Derived; sqlite rebuilds it from the -wal.
        }
        member.copySync('${staged.path}$suffix');
      }
      final key = candidates.firstWhere(
        (candidate) => _keyOpens(staged, candidate),
        orElse: () => Uint8List(0),
      );
      if (key.isEmpty) {
        _diag.event(DiagEvent.parkedWorkspaceUnreadable);
        throw const ParkedRecoveryException(
          ParkedRecoveryFailure.noMatchingKey,
        );
      }
      final damage = _damageReport(staged, key);
      if (damage != null) {
        _diag.event(
          DiagEvent.parkedWorkspaceUnreadable,
          errorType: 'ParkedRecoveryException',
        );
        throw ParkedRecoveryException(ParkedRecoveryFailure.damaged, damage);
      }
      return key;
    } finally {
      try {
        await _probeScratch.disposeSession(session);
      } catch (_) {
        // Swept on next start (§10).
      }
    }
  }

  /// Keys worth trying, most likely first and de-duplicated: an archive's own
  /// retained key, then the live device key, then every other retained key
  /// (`superseded-*` entries from earlier rotations included).
  Future<List<Uint8List>> _candidateKeys(ParkedWorkspace parked) async {
    final out = <Uint8List>[];
    void add(Uint8List? key) {
      if (key != null && !out.any((seen) => _sameKey(seen, key))) {
        out.add(key);
      }
    }

    if (parked.kind == ParkedWorkspaceKind.archived) {
      add(await _keyManager.readRetainedKey(parked.label));
    }
    if (await _keyManager.hasDatabaseKey()) {
      add(await _keyManager.getOrCreateDatabaseKey());
    }
    for (final label in await _keyManager.retainedKeyLabels()) {
      add(await _keyManager.readRetainedKey(label));
    }
    return out;
  }

  /// SQLCipher page-1 key check on the staged copy.
  bool _keyOpens(File staged, Uint8List key) {
    try {
      final db = sqlite.sqlite3.open(staged.path);
      try {
        db.execute('PRAGMA key = "x\'${hexEncode(key)}\'";');
        db.select('SELECT count(*) FROM sqlite_master;');
        return true;
      } finally {
        db.close();
      }
    } on sqlite.SqliteException {
      return false;
    }
  }

  /// null when the staged copy is a sound Loadout workspace; otherwise the
  /// name of the check that failed (content-free).
  String? _damageReport(File staged, Uint8List key) {
    final db = sqlite.sqlite3.open(staged.path);
    try {
      db.execute('PRAGMA key = "x\'${hexEncode(key)}\'";');
      if (db.select('PRAGMA cipher_integrity_check;').isNotEmpty) {
        return 'cipher_integrity_check';
      }
      final integrity = db.select('PRAGMA integrity_check;');
      if (integrity.length != 1 || integrity.first.values.first != 'ok') {
        return 'integrity_check';
      }
      final userVersion = db.select('PRAGMA user_version;').first.values.first;
      if (userVersion is! int || userVersion < 1) {
        return 'user_version';
      }
      final meta = db.select(
        'SELECT count(*) AS c FROM workspace_meta WHERE id = 1;',
      );
      if ((meta.first['c'] as int) != 1) {
        return 'workspace_meta';
      }
      return null;
    } on sqlite.SqliteException {
      return 'sqlite';
    } finally {
      db.close();
    }
  }

  static bool _sameKey(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
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
    // off iOS. scratch/ is created here rather than lazily at first use:
    // setting the attribute on a path that does not exist yet fails
    // silently, and the directory would then be backed up the first time a
    // backup container is staged in it.
    _paths.scratchDir.createSync(recursive: true);
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
