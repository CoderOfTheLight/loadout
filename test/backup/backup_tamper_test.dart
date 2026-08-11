/// §11.2 tamper suite: every manipulated container is refused at the §8.2
/// stage that owns it, and every failure leaves the live DB byte-identical.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/features/backup/domain/backup_service.dart';
import 'package:loadout/infrastructure/backup/backup_service_impl.dart';
import 'package:loadout/infrastructure/security/hex.dart';
import 'package:sqlite3/sqlite3.dart';

import '../infrastructure/harness.dart';

void main() {
  late SecurityHarness h;
  late File kept;
  late Uint8List liveDbBytes;
  const passphrase = 'correct horse battery';

  setUp(() async {
    h = SecurityHarness.create('backup_tamper');
    final db = await h.startup.createFreshWorkspace();
    await seedWorkspaceData(db);
    final container = await h.backup.createBackup(passphrase: passphrase);
    kept = File('${h.tempRoot.path}/kept.loadout');
    container.copySync(kept.path);
    await h.scratch.sweepAll();
    // Close the live DB and snapshot its bytes: validation must never touch
    // it, whatever the failure.
    await h.startup.close();
    liveDbBytes = h.paths.databaseFile.readAsBytesSync();
  });
  tearDown(() => h.dispose());

  Future<void> expectRefused(
    File container,
    String passphrase,
    BackupErrorKind kind,
  ) async {
    await expectLater(
      h.backup.validateBackup(container: container, passphrase: passphrase),
      throwsA(isA<BackupError>().having((e) => e.kind, 'kind', kind)),
    );
    expect(
      h.paths.databaseFile.readAsBytesSync(),
      liveDbBytes,
      reason: 'a refused restore must leave the live DB untouched',
    );
    expect(h.diag.has(DiagEvent.backupValidateFail), isTrue);
  }

  File writeTampered(Uint8List bytes) {
    final f = File('${h.tempRoot.path}/tampered.loadout');
    f.writeAsBytesSync(bytes);
    return f;
  }

  test('wrong passphrase fails the key-check', () async {
    await expectRefused(
      kept,
      'not the passphrase',
      BackupErrorKind.wrongPassphrase,
    );
  });

  test('flipped payload byte fails the sha pre-check', () async {
    final bytes = kept.readAsBytesSync();
    final tampered = rebuildContainer(
      bytes,
      mutatePayload: (payload) {
        final out = Uint8List.fromList(payload);
        out[out.length - 50] ^= 0xff;
        return out;
      },
    );
    await expectRefused(
      writeTampered(tampered),
      passphrase,
      BackupErrorKind.payloadHashMismatch,
    );
  });

  test('flipped payload byte with a consistent manifest fails '
      'cipher_integrity_check', () async {
    final bytes = kept.readAsBytesSync();
    final tampered = rebuildContainer(
      bytes,
      mutatePayload: (payload) {
        final out = Uint8List.fromList(payload);
        out[out.length - 50] ^= 0xff; // a late page: key-check still passes
        return out;
      },
      fixPayloadSha: true,
    );
    await expectRefused(
      writeTampered(tampered),
      passphrase,
      BackupErrorKind.payloadCorrupt,
    );
  });

  test('edited manifest KDF params derive the wrong key', () async {
    final tampered = rebuildContainer(
      kept.readAsBytesSync(),
      mutateManifest: (manifest) {
        final kdf = Map<String, Object?>.from(
          manifest['kdf']! as Map<String, Object?>,
        );
        kdf['saltB64'] = 'AAAAAAAAAAAAAAAAAAAAAA=='; // 16 zero bytes
        return {...manifest, 'kdf': kdf};
      },
    );
    await expectRefused(
      writeTampered(tampered),
      passphrase,
      BackupErrorKind.wrongPassphrase,
    );
  });

  test('hostile KDF cost params are rejected before the KDF runs', () async {
    final tampered = rebuildContainer(
      kept.readAsBytesSync(),
      mutateManifest: (manifest) {
        final kdf = Map<String, Object?>.from(
          manifest['kdf']! as Map<String, Object?>,
        );
        kdf['memoryKiB'] = 1 << 30; // a memory bomb
        return {...manifest, 'kdf': kdf};
      },
    );
    await expectRefused(
      writeTampered(tampered),
      passphrase,
      BackupErrorKind.badManifest,
    );
  });

  test('truncated container is refused before any crypto', () async {
    final bytes = kept.readAsBytesSync();
    await expectRefused(
      writeTampered(Uint8List.sublistView(bytes, 0, bytes.length - 40)),
      passphrase,
      BackupErrorKind.badContainer,
    );
  });

  test('unsupported formatVersion is refused', () async {
    final tampered = rebuildContainer(
      kept.readAsBytesSync(),
      mutateManifest: (manifest) => {...manifest, 'formatVersion': 2},
    );
    await expectRefused(
      writeTampered(tampered),
      passphrase,
      BackupErrorKind.unsupportedFormatVersion,
    );
  });

  test('payload from a newer schema is refused via user_version', () async {
    // Rewrite the payload's user_version above the app schema, keeping the
    // container self-consistent (sha fixed) — the manifest schemaVersion
    // stays 1 to prove the payload PRAGMA is the authoritative gate.
    final entries = kept.readAsBytesSync();
    final manifest = await h.backup.describeBackup(kept);
    final salt = base64Decode(manifest.kdf.saltB64);
    final exportKey = await deriveBackupKey(
      passphrase: passphrase,
      salt: salt,
      cost: testKdfCost,
    );
    final tampered = rebuildContainer(
      entries,
      mutatePayload: (payload) {
        final scratchFile = File('${h.tempRoot.path}/uv.db')
          ..writeAsBytesSync(payload);
        final raw = sqlite3.open(scratchFile.path);
        raw.execute('PRAGMA key = "x\'${hexEncode(exportKey)}\'";');
        raw.execute('PRAGMA user_version = 99;');
        raw.close();
        return scratchFile.readAsBytesSync();
      },
      fixPayloadSha: true,
    );
    await expectRefused(
      writeTampered(tampered),
      passphrase,
      BackupErrorKind.schemaTooNew,
    );
  });

  test('broken domain invariant in the payload is refused', () async {
    // Insert a reversal whose delta is NOT the exact negation of its target.
    // That row passes every SQL CHECK and FK (reversal deltas are
    // unconstrained by CHECK), so only the §8.2 reversal-pairing scan can
    // catch it.
    final manifest = await h.backup.describeBackup(kept);
    final salt = base64Decode(manifest.kdf.saltB64);
    final exportKey = await deriveBackupKey(
      passphrase: passphrase,
      salt: salt,
      cost: testKdfCost,
    );
    final tampered = rebuildContainer(
      kept.readAsBytesSync(),
      mutatePayload: (payload) {
        final scratchFile = File('${h.tempRoot.path}/inv.db')
          ..writeAsBytesSync(payload);
        final raw = sqlite3.open(scratchFile.path);
        raw.execute('PRAGMA key = "x\'${hexEncode(exportKey)}\'";');
        final target = raw
            .select(
              "SELECT id, item_id, source_command_id "
              "FROM inventory_movements WHERE kind = 'receive'",
            )
            .first;
        raw.execute(
          'INSERT INTO inventory_movements (id, item_id, kind, delta_micros, '
          'reverses_movement_id, source_command_id, occurred_at_micros, '
          "recorded_at_micros, note) VALUES "
          "('01AAAAAAAAAAAAAAAAAAAAAAAA', '${target['item_id']}', 'reversal', "
          "-1, '${target['id']}', '${target['source_command_id']}', 1, 1, '')",
        );
        raw.close();
        return scratchFile.readAsBytesSync();
      },
      fixPayloadSha: true,
    );
    await expectRefused(
      writeTampered(tampered),
      passphrase,
      BackupErrorKind.invariantViolation,
    );
  });
}
