/// Shared host-test harness for the security plane (design §11.2 Tier 2).
/// Real SQLCipher via the pubspec `source: sqlcipher` hook — no mocks, no
/// device, temp dirs only.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/infrastructure/backup/backup_service_impl.dart';
import 'package:loadout/infrastructure/backup/stored_zip.dart';
import 'package:loadout/infrastructure/files/loadout_paths.dart';
import 'package:loadout/infrastructure/files/scratch_space.dart';
import 'package:loadout/infrastructure/security/hex.dart';
import 'package:loadout/infrastructure/security/key_manager.dart';
import 'package:loadout/infrastructure/startup/startup_service.dart';
import 'package:sqlite3/sqlite3.dart';

/// Plaintext canary; must never appear in ciphertext files.
const String secretMarker = 'LOADOUT_SECRET_MARKER_7f3a9c';

/// Cheap-but-valid Argon2id cost for tests (validate() accepts >= 8 KiB).
const Argon2Cost testKdfCost = Argon2Cost(
  memoryKiB: 32,
  iterations: 1,
  parallelism: 1,
  hashLength: 32,
);

final class RecordedDiagEvent {
  RecordedDiagEvent(this.event, this.count, this.errorType, this.schemaVersion);

  final DiagEvent event;
  final int? count;
  final String? errorType;
  final int? schemaVersion;
}

final class CapturingDiag implements Diag {
  final List<RecordedDiagEvent> events = [];

  @override
  void event(
    DiagEvent event, {
    int? count,
    Duration? elapsed,
    String? errorType,
    int? schemaVersion,
  }) {
    events.add(RecordedDiagEvent(event, count, errorType, schemaVersion));
  }

  bool has(DiagEvent event) => events.any((e) => e.event == event);
}

final class SecurityHarness {
  SecurityHarness._(this.tempRoot, this.paths, this.keyManager, this.diag)
    : scratch = AppSupportScratchSpace(root: paths.scratchDir, diag: diag) {
    startup = StartupService(paths: paths, keyManager: keyManager, diag: diag);
    backup = BackupServiceImpl(
      host: startup,
      keyManager: keyManager,
      scratch: scratch,
      databaseFile: paths.databaseFile,
      appSchemaVersion: 1,
      diag: diag,
      kdfCost: testKdfCost,
      saltSource: Random(7),
    );
  }

  factory SecurityHarness.create(String label) {
    final tempRoot = Directory.systemTemp.createTempSync(label);
    final paths = LoadoutPaths(Directory('${tempRoot.path}/support'));
    return SecurityHarness._(
      tempRoot,
      paths,
      InMemoryKeyManager(random: Random(11)),
      CapturingDiag(),
    );
  }

  final Directory tempRoot;
  final LoadoutPaths paths;
  final InMemoryKeyManager keyManager;
  final CapturingDiag diag;
  final AppSupportScratchSpace scratch;
  late final StartupService startup;
  late final BackupServiceImpl backup;

  /// Rebuilds the backup service with a fault injector (rollback tests).
  BackupServiceImpl backupWithInjector(
    Future<void> Function(String phase) injector,
  ) => BackupServiceImpl(
    host: startup,
    keyManager: keyManager,
    scratch: scratch,
    databaseFile: paths.databaseFile,
    appSchemaVersion: 1,
    diag: diag,
    kdfCost: testKdfCost,
    restoreFaultInjector: injector,
  );

  Future<void> dispose() async {
    await startup.close();
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  }
}

/// Seeds a small but representative workspace: a command, two items (one
/// carrying [secretMarker] in its name), an event, three movements, and a
/// marker settings row. Respects every CHECK/FK; no reversals/closeouts/
/// recipes so the §8.2 domain validators pass on zero rows.
Future<void> seedWorkspaceData(AppDatabase db) async {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch;
  final commandId = newUlid();
  final itemA = newUlid();
  final itemB = newUlid();
  final eventId = newUlid();
  await db.customStatement(
    'INSERT INTO commands (id, origin, kind, payload_json, status, '
    'created_at_micros, applied_at_micros) '
    "VALUES (?, 'form', 'test.seed', '{}', 'applied', ?, ?)",
    [commandId, now, now],
  );
  await db.customStatement(
    'INSERT INTO items (id, name, unit, pack_size_micros, notes, '
    'created_at_micros, updated_at_micros) '
    "VALUES (?, ?, 'each', 1000000, '', ?, ?)",
    [itemA, 'Item $secretMarker', now, now],
  );
  await db.customStatement(
    'INSERT INTO items (id, name, unit, pack_size_micros, notes, '
    'created_at_micros, updated_at_micros) '
    "VALUES (?, 'Plain item', 'kg', 500000, '', ?, ?)",
    [itemB, now, now],
  );
  await db.customStatement(
    'INSERT INTO events (id, name, scheduled_date, status, '
    'created_at_micros, updated_at_micros) '
    "VALUES (?, 'Market day', '2026-08-01', 'planned', ?, ?)",
    [eventId, now, now],
  );
  final movements = <(String, String, int)>[
    (newUlid(), 'receive', 5000000),
    (newUlid(), 'adjust', -1000000),
    (newUlid(), 'waste', -500000),
  ];
  for (final (id, kind, delta) in movements) {
    await db.customStatement(
      'INSERT INTO inventory_movements (id, item_id, kind, delta_micros, '
      "source_command_id, occurred_at_micros, recorded_at_micros, note) "
      "VALUES (?, ?, ?, ?, ?, ?, ?, '')",
      [id, itemA, kind, delta, commandId, now, now],
    );
  }
  await db.customStatement(
    'INSERT INTO settings (key, value, updated_at_micros) '
    'VALUES (?, ?, ?)',
    ['marker', '"$secretMarker"', now],
  );
}

/// Canonical logical dump of an encrypted database file: user_version, full
/// schema, and every table's rows in a deterministic order. Two databases
/// with identical dumps carry identical content.
String dumpDatabase(File file, Uint8List key) {
  final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
  try {
    db.execute('PRAGMA key = "x\'${hexEncode(key)}\'";');
    final buffer = StringBuffer();
    final userVersion = db.select('PRAGMA user_version;').first.values.first;
    buffer.writeln('user_version=$userVersion');
    final schema = db.select(
      "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
      'ORDER BY type, name',
    );
    for (final row in schema) {
      buffer.writeln('${row['type']}|${row['name']}|${row['sql']}');
    }
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    for (final table in tables) {
      final name = table['name'] as String;
      final columnCount = db.select('PRAGMA table_info("$name");').length;
      final order = List.generate(columnCount, (i) => '${i + 1}').join(', ');
      final rows = db.select('SELECT * FROM "$name" ORDER BY $order');
      for (final row in rows) {
        buffer.writeln('$name|${row.values.join('|')}');
      }
    }
    return buffer.toString();
  } finally {
    db.close();
  }
}

/// Rebuilds a `.loadout` container with optional manifest and payload edits
/// (tamper suite). When [fixPayloadSha] is true the manifest's payloadSha256
/// is recomputed over the (possibly mutated) payload, so tampering flows past
/// the cheap hash pre-check into the cipher checks.
Uint8List rebuildContainer(
  Uint8List containerBytes, {
  Map<String, Object?> Function(Map<String, Object?> manifest)? mutateManifest,
  Uint8List Function(Uint8List payload)? mutatePayload,
  bool fixPayloadSha = false,
}) {
  final entries = readStoredZip(containerBytes);
  final byName = {for (final e in entries) e.name: Uint8List.fromList(e.bytes)};
  var payload = byName['payload.db']!;
  if (mutatePayload != null) {
    payload = mutatePayload(payload);
  }
  var manifest =
      jsonDecode(utf8.decode(byName['manifest.json']!)) as Map<String, Object?>;
  if (mutateManifest != null) {
    manifest = mutateManifest(manifest);
  }
  if (fixPayloadSha) {
    manifest['payloadSha256'] = sha256.convert(payload).toString();
  }
  return writeStoredZip([
    StoredZipEntry(
      name: 'manifest.json',
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    ),
    StoredZipEntry(name: 'payload.db', bytes: payload),
  ]);
}
