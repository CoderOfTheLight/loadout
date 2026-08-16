/// Backup/restore infrastructure (design §8).
///
/// Container (§8.1): `loadout-backup-<yyyymmdd>-<hhmmss>.loadout`, a STORED
/// zip of a cleartext `manifest.json` and `payload.db` (standalone
/// SQLCipher-4 raw-key database under `Argon2id(passphrase, salt)`). The
/// payload is produced from the live connection with plaintext never touching
/// disk via `sqlcipher_export`. File egress/ingress (save/pick dialogs) is
/// deliberately NOT here — this layer is a pure file-path API.
library;

// The prefer_initializing_formals fix ('this._x' named parameters) needs
// the experimental private-named-parameters language feature, which this
// SDK does not enable; explicit `_x = x` initializers stay.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:cryptography/dart.dart' show DartArgon2id;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../core/diagnostics/diag.dart';
import '../../core/time.dart';
import '../../data/db/app_database.dart' show seedAppVersion;
import '../../features/backup/domain/backup_service.dart';
import '../files/scratch_space.dart';
import '../security/hex.dart';
import '../security/key_manager.dart';
import '../startup/startup_service.dart' show DatabaseHost;
import 'stored_zip.dart';

/// Argon2id cost parameters (§8.1 normative production values; recorded in
/// every manifest so future versions can raise costs without breaking old
/// files).
final class Argon2Cost {
  const Argon2Cost({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.hashLength,
  });

  static const Argon2Cost production = Argon2Cost(
    memoryKiB: 19456,
    iterations: 3,
    parallelism: 1,
    hashLength: 32,
  );

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;
}

/// `exportKey = Argon2id(passphrase, salt)` via `package:cryptography`'s
/// pure-Dart implementation (the package's only use in the app, §2).
Future<Uint8List> deriveBackupKey({
  required String passphrase,
  required Uint8List salt,
  required Argon2Cost cost,
}) async {
  final algorithm = DartArgon2id(
    parallelism: cost.parallelism,
    memory: cost.memoryKiB,
    iterations: cost.iterations,
    hashLength: cost.hashLength,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

final class BackupServiceImpl implements BackupService {
  BackupServiceImpl({
    required DatabaseHost host,
    required KeyManager keyManager,
    required ScratchSpace scratch,
    required File databaseFile,
    required int appSchemaVersion,
    Diag diag = const NoopDiag(),
    Clock clock = const SystemClock(),
    Argon2Cost kdfCost = Argon2Cost.production,
    Random? saltSource,
    this.restoreFaultInjector, // test seam: throws at a named phase
  }) : _host = host,
       _keyManager = keyManager,
       _scratch = scratch,
       _databaseFile = databaseFile,
       _appSchemaVersion = appSchemaVersion,
       _diag = diag,
       _clock = clock,
       _kdfCost = kdfCost,
       _saltSource = saltSource;

  final DatabaseHost _host;
  final KeyManager _keyManager;
  final ScratchSpace _scratch;
  final File _databaseFile;
  final int _appSchemaVersion;
  final Diag _diag;
  final Clock _clock;
  final Argon2Cost _kdfCost;
  final Random? _saltSource;

  /// Test-only fault injection for the restore rollback tests. Phases:
  /// 'after-close', 'after-export', 'after-swap', 'after-reopen'.
  final Future<void> Function(String phase)? restoreFaultInjector;

  static const String _manifestName = 'manifest.json';
  static const String _payloadName = 'payload.db';

  // ---------------------------------------------------------------- create

  @override
  Future<File> createBackup({
    required String passphrase,
    void Function(BackupPhase)? onProgress,
  }) async {
    final started = DateTime.now();
    final session = await _scratch.createSession('backup');
    try {
      onProgress?.call(BackupPhase.derivingKey);
      final salt = _newSalt();
      final exportKey = await deriveBackupKey(
        passphrase: passphrase,
        salt: salt,
        cost: _kdfCost,
      );

      onProgress?.call(BackupPhase.exportingPayload);
      final payload = File(p.join(session.path, _payloadName));
      final userVersion = await _exportPayloadFromLive(payload, exportKey);
      final counts = await _liveCounts();

      onProgress?.call(BackupPhase.hashingPayload);
      final payloadBytes = await payload.readAsBytes();
      final payloadSha = sha256.convert(payloadBytes).toString();

      onProgress?.call(BackupPhase.writingContainer);
      final createdAt = DateTime.fromMicrosecondsSinceEpoch(
        _clock.now().epochMicrosUtc,
        isUtc: true,
      );
      final manifest = <String, Object?>{
        'format': 'loadout-backup',
        'formatVersion': 1,
        'appVersion': seedAppVersion,
        'schemaVersion': userVersion,
        'createdAtUtc': createdAt.toIso8601String(),
        'kdf': KdfParams(
          saltB64: base64Encode(salt),
          memoryKiB: _kdfCost.memoryKiB,
          iterations: _kdfCost.iterations,
          parallelism: _kdfCost.parallelism,
          hashLength: _kdfCost.hashLength,
        ).toJson(),
        'cipher': 'sqlcipher4-rawkey',
        'payloadSha256': payloadSha,
        'counts': counts.toJson(),
      };
      final containerBytes = writeStoredZip([
        StoredZipEntry(
          name: _manifestName,
          bytes: Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
        ),
        StoredZipEntry(name: _payloadName, bytes: payloadBytes),
      ]);
      final container = File(
        p.join(session.path, _containerFileName(createdAt)),
      );
      await container.writeAsBytes(containerBytes, flush: true);
      await payload.delete();

      _diag.event(
        DiagEvent.backupCreateOk,
        count: counts.movements,
        elapsed: DateTime.now().difference(started),
        schemaVersion: userVersion,
      );
      onProgress?.call(BackupPhase.done);
      return container;
    } catch (e) {
      _diag.event(
        DiagEvent.backupCreateFail,
        errorType: e.runtimeType.toString(),
      );
      try {
        await _scratch.disposeSession(session);
      } catch (_) {
        // Sweep on next start (§10) is the backstop.
      }
      if (e is BackupError) {
        rethrow;
      }
      throw BackupError(BackupErrorKind.createFailed, e.runtimeType.toString());
    }
  }

  Future<int> _exportPayloadFromLive(File payload, Uint8List exportKey) async {
    final db = _host.database;
    final hexKey = hexEncode(exportKey);
    final userVersion = await _liveUserVersion();
    await db.customStatement('ATTACH DATABASE ? AS export KEY "x\'$hexKey\'"', [
      payload.path,
    ]);
    try {
      await db.customSelect("SELECT sqlcipher_export('export')").get();
      await db.customStatement('PRAGMA export.user_version = $userVersion');
    } finally {
      await db.customStatement('DETACH DATABASE export');
    }
    return userVersion;
  }

  Future<int> _liveUserVersion() async {
    final row = await _host.database
        .customSelect('PRAGMA user_version')
        .getSingle();
    return row.read<int>('user_version');
  }

  Future<BackupCounts> _liveCounts() async {
    final row = await _host.database
        .customSelect(
          'SELECT (SELECT count(*) FROM inventory_movements) AS movements, '
          '(SELECT count(*) FROM items) AS items, '
          '(SELECT count(*) FROM events) AS events',
        )
        .getSingle();
    return BackupCounts(
      movements: row.read<int>('movements'),
      items: row.read<int>('items'),
      events: row.read<int>('events'),
    );
  }

  Uint8List _newSalt() {
    final rng = _saltSource ?? Random.secure();
    final salt = Uint8List(16);
    for (var i = 0; i < salt.length; i++) {
      salt[i] = rng.nextInt(256);
    }
    return salt;
  }

  static String _containerFileName(DateTime utc) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'loadout-backup-${utc.year}${two(utc.month)}${two(utc.day)}'
        '-${two(utc.hour)}${two(utc.minute)}${two(utc.second)}.loadout';
  }

  // -------------------------------------------------------------- describe

  @override
  Future<BackupDescription> describeBackup(File container) async {
    if (!await container.exists()) {
      throw const BackupError(BackupErrorKind.notFound);
    }
    final bytes = await container.readAsBytes();
    final entries = _parseContainer(bytes);
    return _parseManifest(entries[_manifestName]!, bytes.length);
  }

  Map<String, Uint8List> _parseContainer(Uint8List bytes) {
    final List<StoredZipEntry> entries;
    try {
      entries = readStoredZip(bytes);
    } on StoredZipFormatException catch (e) {
      throw BackupError(BackupErrorKind.badContainer, e.reason);
    }
    final byName = {for (final e in entries) e.name: e.bytes};
    if (byName.length != 2 ||
        !byName.containsKey(_manifestName) ||
        !byName.containsKey(_payloadName)) {
      throw const BackupError(BackupErrorKind.badContainer, 'entries');
    }
    return byName;
  }

  BackupDescription _parseManifest(Uint8List manifestBytes, int containerSize) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(manifestBytes));
    } on FormatException {
      throw const BackupError(BackupErrorKind.badManifest, 'json');
    }
    if (decoded is! Map<String, Object?>) {
      throw const BackupError(BackupErrorKind.badManifest, 'shape');
    }
    final kdf = decoded['kdf'];
    final counts = decoded['counts'];
    if (decoded['format'] != 'loadout-backup' ||
        decoded['formatVersion'] is! int ||
        decoded['appVersion'] is! String ||
        decoded['schemaVersion'] is! int ||
        decoded['createdAtUtc'] is! String ||
        decoded['cipher'] is! String ||
        decoded['payloadSha256'] is! String ||
        kdf is! Map<String, Object?> ||
        counts is! Map<String, Object?>) {
      throw const BackupError(BackupErrorKind.badManifest, 'fields');
    }
    if (kdf['algorithm'] != KdfParams.algorithm ||
        kdf['saltB64'] is! String ||
        kdf['memoryKiB'] is! int ||
        kdf['iterations'] is! int ||
        kdf['parallelism'] is! int ||
        kdf['hashLength'] is! int) {
      throw const BackupError(BackupErrorKind.badManifest, 'kdf');
    }
    if (counts['movements'] is! int ||
        counts['items'] is! int ||
        counts['events'] is! int) {
      throw const BackupError(BackupErrorKind.badManifest, 'counts');
    }
    final sha = decoded['payloadSha256']! as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw const BackupError(BackupErrorKind.badManifest, 'payloadSha256');
    }
    return BackupDescription(
      formatVersion: decoded['formatVersion']! as int,
      appVersion: decoded['appVersion']! as String,
      schemaVersion: decoded['schemaVersion']! as int,
      createdAtUtc: decoded['createdAtUtc']! as String,
      kdf: KdfParams(
        saltB64: kdf['saltB64']! as String,
        memoryKiB: kdf['memoryKiB']! as int,
        iterations: kdf['iterations']! as int,
        parallelism: kdf['parallelism']! as int,
        hashLength: kdf['hashLength']! as int,
      ),
      cipher: decoded['cipher']! as String,
      payloadSha256: sha,
      counts: BackupCounts(
        movements: counts['movements']! as int,
        items: counts['items']! as int,
        events: counts['events']! as int,
      ),
      containerSizeBytes: containerSize,
    );
  }

  // -------------------------------------------------------------- validate

  @override
  Future<RestorePreview> validateBackup({
    required File container,
    required String passphrase,
  }) async {
    try {
      return await _validate(container: container, passphrase: passphrase);
    } catch (e) {
      _diag.event(
        DiagEvent.backupValidateFail,
        errorType: e.runtimeType.toString(),
      );
      rethrow;
    }
  }

  Future<RestorePreview> _validate({
    required File container,
    required String passphrase,
  }) async {
    if (!await container.exists()) {
      throw const BackupError(BackupErrorKind.notFound);
    }
    // (1) Copy the picked file into support/scratch/restore/<session>/;
    // everything below reads the copy, never the live DB.
    final session = await _scratch.createSession('restore');
    try {
      final staged = File(p.join(session.path, p.basename(container.path)));
      await container.copy(staged.path);
      final bytes = await staged.readAsBytes();

      // (2) Zip structure + manifest schema + formatVersion == 1.
      final entries = _parseContainer(bytes);
      final description = _parseManifest(entries[_manifestName]!, bytes.length);
      if (description.formatVersion != 1) {
        throw const BackupError(BackupErrorKind.unsupportedFormatVersion);
      }
      if (description.cipher != 'sqlcipher4-rawkey') {
        throw const BackupError(BackupErrorKind.badManifest, 'cipher');
      }
      final kdf = description.kdf;
      if (kdf.hashLength != 32 ||
          kdf.memoryKiB < 8 ||
          kdf.memoryKiB > 1 << 20 ||
          kdf.iterations < 1 ||
          kdf.iterations > 64 ||
          kdf.parallelism < 1 ||
          kdf.parallelism > 16) {
        // Bounds keep a hostile manifest from turning the KDF into a
        // memory/CPU bomb; tampered params otherwise just derive a wrong key.
        throw const BackupError(BackupErrorKind.badManifest, 'kdfBounds');
      }
      final Uint8List salt;
      try {
        salt = base64Decode(kdf.saltB64);
      } on FormatException {
        throw const BackupError(BackupErrorKind.badManifest, 'saltB64');
      }

      // (3) payloadSha256 matches (cheap truncation check before the KDF).
      final payloadBytes = entries[_payloadName]!;
      if (sha256.convert(payloadBytes).toString() !=
          description.payloadSha256) {
        throw const BackupError(BackupErrorKind.payloadHashMismatch);
      }
      final payloadFile = File(p.join(session.path, _payloadName));
      await payloadFile.writeAsBytes(payloadBytes, flush: true);

      // (4) Derive exportKey with the MANIFEST's KDF params; wrong passphrase
      // (or tampered params) fails the key-check here.
      final exportKey = await deriveBackupKey(
        passphrase: passphrase,
        salt: salt,
        cost: Argon2Cost(
          memoryKiB: kdf.memoryKiB,
          iterations: kdf.iterations,
          parallelism: kdf.parallelism,
          hashLength: kdf.hashLength,
        ),
      );

      final BackupCounts verifiedCounts;
      final int payloadUserVersion;
      final payloadDb = sqlite3.open(payloadFile.path, mode: OpenMode.readOnly);
      try {
        payloadDb.execute('PRAGMA key = "x\'${hexEncode(exportKey)}\'";');
        try {
          // Page-1-only probe: a wrong key fails HMAC on the first page read.
          // Deliberately narrow so stage (5) below — the whole-file HMAC
          // sweep — is what catches tampered later pages.
          payloadDb.select('PRAGMA schema_version;');
        } on SqliteException {
          throw const BackupError(BackupErrorKind.wrongPassphrase);
        }

        // (5) Page-HMAC then structural integrity.
        final cipherCheck = payloadDb.select('PRAGMA cipher_integrity_check;');
        if (cipherCheck.isNotEmpty) {
          throw const BackupError(
            BackupErrorKind.payloadCorrupt,
            'cipher_integrity_check',
          );
        }
        final integrity = payloadDb.select('PRAGMA integrity_check;');
        if (integrity.length != 1 || integrity.first.values.first != 'ok') {
          throw const BackupError(
            BackupErrorKind.payloadCorrupt,
            'integrity_check',
          );
        }

        // (6) Authoritative schema-version gate: the payload's user_version,
        // not the advisory manifest field.
        payloadUserVersion =
            payloadDb.select('PRAGMA user_version;').first.values.first! as int;
        if (payloadUserVersion > _appSchemaVersion) {
          throw const BackupError(BackupErrorKind.schemaTooNew);
        }
        if (payloadUserVersion < 1) {
          throw const BackupError(
            BackupErrorKind.payloadCorrupt,
            'user_version',
          );
        }

        // (7) Domain validation, limited to checks that exist.
        _validateDomainInvariants(payloadDb);

        final countRow = payloadDb
            .select(
              'SELECT (SELECT count(*) FROM inventory_movements) AS movements, '
              '(SELECT count(*) FROM items) AS items, '
              '(SELECT count(*) FROM events) AS events',
            )
            .first;
        verifiedCounts = BackupCounts(
          movements: countRow['movements'] as int,
          items: countRow['items'] as int,
          events: countRow['events'] as int,
        );
      } finally {
        payloadDb.close();
      }

      return RestorePreview(
        description: description,
        verifiedCounts: verifiedCounts,
        payloadUserVersion: payloadUserVersion,
        stagingDir: session,
        payloadFile: payloadFile,
        exportKey: exportKey,
      );
    } catch (_) {
      try {
        await _scratch.disposeSession(session);
      } catch (_) {
        // Swept on next start.
      }
      rethrow;
    }
  }

  /// §8.2 step 7: `foreign_key_check` clean; sign-per-kind scan; reversal
  /// pairing; closeout arithmetic; recipe-cycle detection on live revisions.
  /// There is no sequence-number check — ids are ULIDs.
  void _validateDomainInvariants(Database db) {
    void require(bool ok, String check) {
      if (!ok) {
        throw BackupError(BackupErrorKind.invariantViolation, check);
      }
    }

    int scalar(String sql) => db.select(sql).first.values.first! as int;

    require(
      db.select('PRAGMA foreign_key_check;').isEmpty,
      'foreign_key_check',
    );
    require(
      scalar(
            'SELECT count(*) FROM inventory_movements WHERE delta_micros = 0 '
            "OR (kind = 'receive' AND delta_micros <= 0) "
            "OR (kind IN ('consume', 'waste') AND delta_micros >= 0)",
          ) ==
          0,
      'movement_sign_per_kind',
    );
    // Reversal pairing: target exists, same item, exact delta negation.
    require(
      scalar(
            'SELECT count(*) FROM inventory_movements r '
            'LEFT JOIN inventory_movements t ON t.id = r.reverses_movement_id '
            "WHERE r.kind = 'reversal' AND (t.id IS NULL "
            'OR t.item_id != r.item_id OR r.delta_micros != -t.delta_micros)',
          ) ==
          0,
      'reversal_pairing',
    );
    // Targets unique (belt and braces over the UNIQUE index).
    require(
      db
          .select(
            'SELECT reverses_movement_id FROM inventory_movements '
            'WHERE reverses_movement_id IS NOT NULL '
            'GROUP BY reverses_movement_id HAVING count(*) > 1',
          )
          .isEmpty,
      'reversal_target_unique',
    );
    // Closeout worksheet arithmetic re-verified.
    require(
      scalar(
            'SELECT count(*) FROM closeout_lines '
            'WHERE loaded_micros IS NOT NULL AND returned_micros IS NOT NULL '
            'AND waste_micros IS NOT NULL AND depletion_micros != '
            'loaded_micros - returned_micros - waste_micros',
          ) ==
          0,
      'closeout_worksheet',
    );
    // Linked consume/waste movements match line values.
    require(
      scalar(
            'SELECT count(*) FROM closeout_lines cl '
            'LEFT JOIN inventory_movements m ON m.id = cl.consumption_movement_id '
            'WHERE cl.consumption_movement_id IS NOT NULL AND (m.id IS NULL '
            "OR m.kind != 'consume' OR m.item_id != cl.item_id "
            'OR m.delta_micros != -cl.depletion_micros)',
          ) ==
          0,
      'closeout_consume_link',
    );
    require(
      scalar(
            'SELECT count(*) FROM closeout_lines cl '
            'LEFT JOIN inventory_movements m ON m.id = cl.waste_movement_id '
            'WHERE cl.waste_movement_id IS NOT NULL AND (m.id IS NULL '
            "OR m.kind != 'waste' OR m.item_id != cl.item_id "
            'OR cl.waste_micros IS NULL '
            'OR m.delta_micros != -cl.waste_micros)',
          ) ==
          0,
      'closeout_waste_link',
    );
    require(!_hasRecipeCycle(db), 'recipe_cycle');
  }

  /// Cycle detection over live recipes' latest revisions (output item →
  /// ingredient items), deterministic iteration order. Local equivalent of
  /// the domain-layer recipe-graph guard, run against the payload SQL.
  ///
  /// v5 payloads carry `recipe_lines_v2` (a superset of the frozen legacy
  /// table, links nullable, outputs nullable); pre-v5 payloads only
  /// `recipe_lines`. The payload is validated at ITS stored version — before
  /// any migration — so pick the table by existence.
  bool _hasRecipeCycle(Database db) {
    final hasV2 =
        db
                .select(
                  "SELECT COUNT(*) AS c FROM sqlite_master "
                  "WHERE type = 'table' AND name = 'recipe_lines_v2'",
                )
                .first['c']!
            as int >
        0;
    final edges = db.select(
      hasV2
          ? 'SELECT r.output_item_id AS output, '
                'l.ingredient_item_id AS ingredient '
                'FROM recipes r '
                'JOIN recipe_revisions rr ON rr.recipe_id = r.id '
                'JOIN recipe_lines_v2 l ON l.revision_id = rr.id '
                'WHERE r.archived_at_micros IS NULL '
                'AND r.output_item_id IS NOT NULL '
                'AND l.ingredient_item_id IS NOT NULL AND rr.revision = '
                '(SELECT max(revision) FROM recipe_revisions '
                'WHERE recipe_id = r.id)'
          : 'SELECT r.output_item_id AS output, '
                'l.ingredient_item_id AS ingredient '
                'FROM recipes r '
                'JOIN recipe_revisions rr ON rr.recipe_id = r.id '
                'JOIN recipe_lines l ON l.revision_id = rr.id '
                'WHERE r.archived_at_micros IS NULL AND rr.revision = '
                '(SELECT max(revision) FROM recipe_revisions '
                'WHERE recipe_id = r.id)',
    );
    final adjacency = <String, List<String>>{};
    for (final row in edges) {
      adjacency
          .putIfAbsent(row['output'] as String, () => [])
          .add(row['ingredient'] as String);
    }
    for (final targets in adjacency.values) {
      targets.sort();
    }
    const white = 0, grey = 1, black = 2;
    final color = <String, int>{};
    bool visit(String node) {
      color[node] = grey;
      for (final next in adjacency[node] ?? const <String>[]) {
        final c = color[next] ?? white;
        if (c == grey || (c == white && visit(next))) {
          return true;
        }
      }
      color[node] = black;
      return false;
    }

    final roots = adjacency.keys.toList()..sort();
    for (final node in roots) {
      if ((color[node] ?? white) == white && visit(node)) {
        return true;
      }
    }
    return false;
  }

  // --------------------------------------------------------------- restore

  @override
  Future<void> restoreBackup(RestorePreview preview) async {
    if (!await preview.payloadFile.exists()) {
      throw const BackupError(BackupErrorKind.restoreFailed, 'stagingGone');
    }
    final deviceKey = await _keyManager.getOrCreateDatabaseKey();
    final newDb = File('${_databaseFile.path}.new');
    var swapped = false;
    // Whether THIS restore parked the live workspace. A `.pre-restore` copy
    // can already be sitting there from an earlier restore that died
    // mid-swap — that is the §7.3 parked state, and `/settings/restore` is
    // reachable from its recovery screen. This restore did not put that copy
    // there, so this restore neither deletes it on success nor renames it
    // back on failure.
    var parked = false;
    try {
      await _host.close();
      await restoreFaultInjector?.call('after-close');

      // Rename db/loadout.db (+-wal, -shm) aside; never delete.
      parked = _renameSidecars(from: '', to: '.pre-restore');

      // Re-encrypt the payload under the DEVICE key via sqlcipher_export
      // into db/loadout.db.new; plaintext never touches disk.
      if (newDb.existsSync()) {
        newDb.deleteSync();
      }
      _reencrypt(
        source: preview.payloadFile,
        sourceKey: preview.exportKey,
        target: newDb,
        targetKey: deviceKey,
        userVersion: preview.payloadUserVersion,
      );
      await restoreFaultInjector?.call('after-export');

      // Atomic rename to loadout.db: at every instant exactly one openable
      // authoritative DB exists.
      newDb.renameSync(_databaseFile.path);
      swapped = true;
      await restoreFaultInjector?.call('after-swap');

      // Reopen; drift migrations run if the payload schema is older;
      // post-open sanity (key-check + workspace_meta read) is part of open().
      await _host.open();
      await restoreFaultInjector?.call('after-reopen');

      // Success: delete staging and the .pre-restore copy this restore made.
      if (parked) {
        _deleteSidecars(suffix: '.pre-restore');
      }
      try {
        await _scratch.disposeSession(preview.stagingDir);
      } catch (_) {
        // Swept on next start.
      }
      _diag.event(
        DiagEvent.restoreOk,
        count: preview.verifiedCounts.movements,
        schemaVersion: preview.payloadUserVersion,
      );
    } catch (e) {
      await _rollback(newDb: newDb, swapped: swapped, parked: parked);
      _diag.event(
        DiagEvent.restoreRolledBack,
        errorType: e.runtimeType.toString(),
      );
      if (e is BackupError) {
        rethrow;
      }
      throw BackupError(
        BackupErrorKind.restoreFailed,
        e.runtimeType.toString(),
      );
    }
  }

  Future<void> _rollback({
    required File newDb,
    required bool swapped,
    required bool parked,
  }) async {
    try {
      await _host.close();
    } catch (_) {
      // Host may already be closed.
    }
    try {
      if (newDb.existsSync()) {
        newDb.deleteSync();
      }
      if (swapped) {
        // The current loadout.db* is the failed new workspace this restore
        // created; remove it before putting anything back.
        _deleteSidecars(suffix: '');
      }
      if (parked) {
        _renameSidecars(from: '.pre-restore', to: '');
      }
      // Restored INTO the §7.3 parked state: there was no live workspace
      // before, so there is none to reopen. Opening here would create an
      // empty one over the top; bootstrap offers the parked copy instead.
      if (_databaseFile.existsSync()) {
        await _host.open();
      }
    } catch (_) {
      // The .pre-restore copy is still on disk; bootstrap surfaces recovery.
    }
  }

  /// Renames `loadout.db$from` (+`-wal`, `-shm`) to `loadout.db$to`.
  /// Returns whether the main database file itself moved — the caller needs
  /// to know whether the `.pre-restore` copy is its own to clean up.
  bool _renameSidecars({required String from, required String to}) {
    var movedMain = false;
    for (final suffix in const ['', '-wal', '-shm']) {
      final source = File('${_databaseFile.path}$suffix$from');
      if (source.existsSync()) {
        source.renameSync('${_databaseFile.path}$suffix$to');
        movedMain |= suffix.isEmpty;
      }
    }
    return movedMain;
  }

  void _deleteSidecars({required String suffix}) {
    for (final sidecar in const ['', '-wal', '-shm']) {
      final file = File('${_databaseFile.path}$sidecar$suffix');
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  void _reencrypt({
    required File source,
    required Uint8List sourceKey,
    required File target,
    required Uint8List targetKey,
    required int userVersion,
  }) {
    final db = sqlite3.open(source.path);
    try {
      db.execute('PRAGMA key = "x\'${hexEncode(sourceKey)}\'";');
      db.select('SELECT count(*) FROM sqlite_master;'); // key-check
      final escapedPath = target.path.replaceAll("'", "''");
      db.execute(
        "ATTACH DATABASE '$escapedPath' AS target "
        'KEY "x\'${hexEncode(targetKey)}\'";',
      );
      try {
        db.select("SELECT sqlcipher_export('target');");
        db.execute('PRAGMA target.user_version = $userVersion;');
      } finally {
        db.execute('DETACH DATABASE target;');
      }
    } finally {
      db.close();
    }
  }
}
