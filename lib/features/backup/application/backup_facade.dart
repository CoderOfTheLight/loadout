/// Application facade over the infrastructure `BackupService` (§6.5/§8):
/// wraps its typed [BackupError] throws into `Result` at the application
/// boundary. Error messages are content-free — no names, no paths.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/errors.dart';
import '../../../core/result.dart';
import '../domain/backup_service.dart';

/// A created backup container plus the name to suggest in the save dialog.
/// The save-file dialog itself (flutter_file_dialog) is UI-owned; this layer
/// never performs egress.
final class BackupFileHandle {
  const BackupFileHandle({required this.file, required this.suggestedFileName});

  final File file;
  final String suggestedFileName;
}

abstract interface class BackupFacade {
  Future<Result<BackupFileHandle>> createBackup({required String passphrase});
  Future<Result<BackupDescription>> describeBackup(String path);
  Future<Result<RestorePreview>> validateBackup({
    required String path,
    required String passphrase,
  });
  Future<Result<void>> restoreBackup(RestorePreview preview);
}

final class DefaultBackupFacade implements BackupFacade {
  const DefaultBackupFacade(this._service);

  final BackupService _service;

  @override
  Future<Result<BackupFileHandle>> createBackup({required String passphrase}) =>
      _guard(() async {
        final file = await _service.createBackup(passphrase: passphrase);
        return BackupFileHandle(
          file: file,
          suggestedFileName: p.basename(file.path),
        );
      });

  @override
  Future<Result<BackupDescription>> describeBackup(String path) =>
      _guard(() => _service.describeBackup(File(path)));

  @override
  Future<Result<RestorePreview>> validateBackup({
    required String path,
    required String passphrase,
  }) => _guard(
    () =>
        _service.validateBackup(container: File(path), passphrase: passphrase),
  );

  @override
  Future<Result<void>> restoreBackup(RestorePreview preview) =>
      _guard(() => _service.restoreBackup(preview));

  Future<Result<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } on BackupError catch (e) {
      return Err(_map(e));
    }
  }

  /// Distinct content-free messages: wrong-passphrase vs corrupt-file vs
  /// too-new must be distinguishable by the restore screen (§9).
  static DomainError _map(BackupError error) => switch (error.kind) {
    BackupErrorKind.notFound => const NotFoundError(
      'That backup file could not be found.',
    ),
    BackupErrorKind.wrongPassphrase => const ValidationError(
      'That passphrase does not unlock this backup.',
    ),
    BackupErrorKind.schemaTooNew => const StaleStateError(
      'This backup was made by a newer version of the app.',
    ),
    BackupErrorKind.badContainer ||
    BackupErrorKind.badManifest ||
    BackupErrorKind.unsupportedFormatVersion ||
    BackupErrorKind.payloadHashMismatch ||
    BackupErrorKind.payloadCorrupt ||
    BackupErrorKind.invariantViolation => const ValidationError(
      'This file is not a readable Loadout backup.',
    ),
    BackupErrorKind.createFailed => const ValidationError(
      'The backup could not be created. Nothing was changed.',
    ),
    BackupErrorKind.restoreFailed => const StaleStateError(
      'The restore did not complete. Your previous data was kept.',
    ),
  };
}
