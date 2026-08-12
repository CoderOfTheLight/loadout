/// Feature-local providers for the backup/restore screens.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/time.dart';
import '../../../data/db/app_database.dart' hide EventCloseout;
import '../../../infrastructure/backup/backup_service_impl.dart';
import '../application/backup_facade.dart';
import '../../../data/db/table_watch.dart';

/// Settings key recording when a backup file was last handed to the save
/// dialog successfully (drives the §12.22 in-app nudge banner and the
/// last-backup caption on the backup screen). Device-local bookkeeping —
/// deliberately not one of the workspace preferences.
const String lastBackupAtKey = 'last_backup_at_micros';

/// When the last backup file was saved from this workspace, or null when no
/// backup has been saved yet. Null while no database is open.
final lastBackupProvider = StreamProvider.autoDispose<DateTime?>((ref) {
  ref.watch(startupStateProvider);
  ref.watch(databaseGenerationProvider);
  if (!ref.watch(databaseHostProvider).isOpen) {
    return Stream<DateTime?>.value(null);
  }
  final db = ref.watch(appDatabaseProvider);
  return db.watchTables('backup.lastBackupAt', {db.settings}).asyncMap((
    _,
  ) async {
    final raw = await db.settingsDao.value(lastBackupAtKey);
    if (raw == null) return null;
    final micros = jsonDecode(raw);
    if (micros is! int) return null;
    return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  });
});

/// Records "a backup file was saved just now" (see [lastBackupAtKey]).
Future<void> recordBackupSaved(
  AppDatabase db, {
  Clock clock = const SystemClock(),
}) {
  final nowMicros = clock.now().epochMicrosUtc;
  return db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: lastBackupAtKey,
          value: jsonEncode(nowMicros),
          updatedAtMicros: nowMicros,
        ),
      );
}

/// The facade the restore screen uses. With an open workspace this is the
/// app-wide [backupFacadeProvider]; in a §7.3 recovery state no database is
/// open, so reading that provider would throw ([appDatabaseProvider] guards
/// it) — yet restore is exactly the recovery action (a). This branch builds
/// the same service without touching the (nonexistent) live handle.
final restoreFacadeProvider = Provider.autoDispose<BackupFacade>((ref) {
  ref.watch(startupStateProvider);
  ref.watch(databaseGenerationProvider);
  if (ref.watch(databaseHostProvider).isOpen) {
    return ref.watch(backupFacadeProvider);
  }
  final startup = ref.watch(startupServiceProvider);
  return DefaultBackupFacade(
    BackupServiceImpl(
      host: startup,
      keyManager: ref.watch(keyManagerProvider),
      scratch: ref.watch(scratchSpaceProvider),
      databaseFile: startup.paths.databaseFile,
      appSchemaVersion: _appSchemaVersion(),
      diag: ref.watch(diagProvider),
    ),
  );
});

/// The app's compile-time schema version, read off an unopened [AppDatabase]
/// (the getter is a constant; the in-memory executor is never opened) so it
/// can never drift from the real database class.
int _appSchemaVersion() {
  final probe = AppDatabase.forTesting(NativeDatabase.memory());
  final version = probe.schemaVersion;
  unawaited(probe.close());
  return version;
}
