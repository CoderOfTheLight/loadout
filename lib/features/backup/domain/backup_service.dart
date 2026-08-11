/// Backup/restore service contract (design §8.2). Infrastructure implements
/// this; the application boundary wraps its typed [BackupError] throws into
/// `Result` via `BackupFacade`.
///
/// Container (§8.1): one `.loadout` file — a zip (STORED, no compression)
/// holding a cleartext `manifest.json` and `payload.db`, a standalone
/// SQLCipher-4 raw-key database encrypted under
/// `exportKey = Argon2id(passphrase, salt)`. SQLCipher's per-page
/// HMAC-SHA512 is the payload's integrity + authentication.
library;

import 'dart:io';
import 'dart:typed_data';

/// Progress phases reported by `createBackup` (backup screen UI).
enum BackupPhase {
  derivingKey,
  exportingPayload,
  hashingPayload,
  writingContainer,
  done,
}

/// Typed failure taxonomy. Deliberately content-free: no paths, no names.
enum BackupErrorKind {
  /// The picked container file does not exist / cannot be read.
  notFound,

  /// Not a readable STORED zip with the expected two entries.
  badContainer,

  /// manifest.json missing, unparseable, or schema-invalid.
  badManifest,

  /// `formatVersion != 1`.
  unsupportedFormatVersion,

  /// `payloadSha256` mismatch (cheap truncation check before the KDF).
  payloadHashMismatch,

  /// Key-check failed on the payload (wrong passphrase — or tampered KDF
  /// params, which derive the wrong key; indistinguishable by design).
  wrongPassphrase,

  /// `cipher_integrity_check` / `integrity_check` failed on the payload.
  payloadCorrupt,

  /// Payload `PRAGMA user_version` is newer than this app's schema.
  schemaTooNew,

  /// Domain validation failed (§8.2 step 7).
  invariantViolation,

  /// Backup creation failed.
  createFailed,

  /// Restore failed; the pre-restore database was rolled back.
  restoreFailed,
}

final class BackupError implements Exception {
  const BackupError(this.kind, [this.debugDetail]);

  final BackupErrorKind kind;

  /// Machine detail (check name only — never content) for tests/logs.
  final String? debugDetail;

  @override
  String toString() =>
      'BackupError(${kind.name}${debugDetail == null ? '' : ': $debugDetail'})';
}

/// KDF parameters as recorded in the cleartext manifest (§8.1) so future
/// versions can raise costs without breaking old files.
final class KdfParams {
  const KdfParams({
    required this.saltB64,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.hashLength,
  });

  static const String algorithm = 'argon2id';

  final String saltB64;
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;

  Map<String, Object?> toJson() => {
    'algorithm': algorithm,
    'saltB64': saltB64,
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'hashLength': hashLength,
  };
}

final class BackupCounts {
  const BackupCounts({
    required this.movements,
    required this.items,
    required this.events,
  });

  final int movements;
  final int items;
  final int events;

  Map<String, Object?> toJson() => {
    'movements': movements,
    'items': items,
    'events': events,
  };
}

/// Cleartext manifest view — obtainable without a passphrase.
final class BackupDescription {
  const BackupDescription({
    required this.formatVersion,
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.kdf,
    required this.cipher,
    required this.payloadSha256,
    required this.counts,
    required this.containerSizeBytes,
  });

  final int formatVersion;
  final String appVersion;

  /// Advisory only; the authoritative check is the payload's
  /// `PRAGMA user_version` (§8.2 step 6).
  final int schemaVersion;
  final String createdAtUtc;
  final KdfParams kdf;
  final String cipher;
  final String payloadSha256;
  final BackupCounts counts;
  final int containerSizeBytes;
}

/// Product of a successful `validateBackup`: everything `restoreBackup`
/// needs, verified against the decrypted payload. The derived export key
/// lives only in memory.
final class RestorePreview {
  const RestorePreview({
    required this.description,
    required this.verifiedCounts,
    required this.payloadUserVersion,
    required this.stagingDir,
    required this.payloadFile,
    required this.exportKey,
  });

  final BackupDescription description;

  /// Recounted from the decrypted payload (not trusted from the manifest).
  final BackupCounts verifiedCounts;
  final int payloadUserVersion;
  final Directory stagingDir;
  final File payloadFile;
  final Uint8List exportKey;
}

abstract interface class BackupService {
  Future<File> createBackup({
    required String passphrase,
    void Function(BackupPhase)? onProgress,
  });

  /// Manifest only — requires NO passphrase (manifest is cleartext).
  Future<BackupDescription> describeBackup(File container);

  /// Full validation; never touches the live DB. Throws typed [BackupError].
  Future<RestorePreview> validateBackup({
    required File container,
    required String passphrase,
  });

  /// Whole-workspace replace, atomic. No merge mode exists.
  Future<void> restoreBackup(RestorePreview preview);
}
