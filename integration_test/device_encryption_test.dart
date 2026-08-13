/// Tier 3 (design §11.2): the proofs that only a real Android/iOS runtime
/// can give. Host tests already cover the logic; what they cannot cover is
/// whether the SQLCipher library that ships in the app bundle is the one
/// that gets loaded, whether the platform keystore actually persists the
/// key, and whether the file the OS ends up with is ciphertext.
///
/// Run with a device or emulator attached:
///   fvm flutter test integration_test/device_encryption_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/infrastructure/files/ios_backup_exclusion.dart';
import 'package:loadout/infrastructure/files/loadout_paths.dart';
import 'package:loadout/infrastructure/files/scratch_space.dart';
import 'package:loadout/infrastructure/security/key_manager.dart';
import 'package:loadout/infrastructure/startup/startup_service.dart';
import 'package:sqlite3/sqlite3.dart';

/// Written into the workspace, then hunted for in the raw database bytes.
const String canary = 'LOADOUT_DEVICE_CANARY_4b91d7';

/// `SQLite format 3\0` — the header every UNencrypted database starts with.
final List<int> plaintextMagic = ascii.encode('SQLite format 3');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LoadoutPaths paths;
  late SecureStorageKeyManager keyManager;
  late StartupService startup;

  setUp(() async {
    paths = await LoadoutPaths.resolve();
    keyManager = SecureStorageKeyManager();
    // Each run starts from nothing: this is a device, not a temp dir.
    await resetDeviceState(paths, keyManager);
    startup = StartupService(
      paths: paths,
      keyManager: keyManager,
      scratch: AppSupportScratchSpace(root: paths.scratchDir),
      diag: const NoopDiag(),
    );
  });

  tearDown(() async {
    await startup.close();
    await resetDeviceState(paths, keyManager);
  });

  testWidgets('the shipped sqlite3 is a SQLCipher build', (tester) async {
    final probe = sqlite3.openInMemory();
    addTearDown(probe.close);
    final rows = probe.select('PRAGMA cipher_version;');
    expect(
      rows,
      isNotEmpty,
      reason:
          'plain SQLite returns nothing here — the app would be writing '
          'the workspace in cleartext',
    );
  });

  testWidgets('the workspace file on disk is ciphertext', (tester) async {
    final db = await startup.createFreshWorkspace();
    await db.customStatement(
      "INSERT INTO settings (key, value, updated_at_micros) "
      "VALUES ('device_canary', '$canary', 0)",
    );
    await startup.close();

    final bytes = await paths.databaseFile.readAsBytes();
    expect(bytes, isNotEmpty);
    expect(
      _indexOfBytes(bytes, plaintextMagic),
      -1,
      reason: 'the file carries the plain SQLite header',
    );
    expect(
      _indexOfBytes(bytes, ascii.encode(canary)),
      -1,
      reason: 'workspace content is readable in the raw file',
    );

    // The sidecars leak just as badly if they are not encrypted too.
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${paths.databaseFile.path}$suffix');
      if (sidecar.existsSync()) {
        expect(
          _indexOfBytes(await sidecar.readAsBytes(), ascii.encode(canary)),
          -1,
          reason: '$suffix carries cleartext content',
        );
      }
    }
  });

  testWidgets('iOS applies the intended data-protection class', (tester) async {
    if (!Platform.isIOS) {
      return; // Android's equivalent is full-disk/file-based encryption.
    }
    const exclusion = IosBackupExclusion();
    if (await exclusion.isSimulator()) {
      // The Simulator does not implement Data Protection at all — it reports
      // no class whatever the app asks for. Only a real device can answer
      // this, which is the whole reason the check exists.
      return;
    }
    await startup.createFreshWorkspace();
    await startup.close();

    // §10 wants CompleteUntilFirstUserAuthentication: unreadable on a
    // powered-off device that was never unlocked, but it does not yank an
    // open handle mid-WAL-write the way Complete would. That is the platform
    // default, so no entitlement declares it — which makes checking the real
    // file the only honest proof.
    expect(
      await exclusion.fileProtection(paths.databaseFile),
      'NSFileProtectionCompleteUntilFirstUserAuthentication',
    );
  });

  testWidgets('the platform keystore persists the key across a reopen', (
    tester,
  ) async {
    final db = await startup.createFreshWorkspace();
    await db.customStatement(
      "INSERT INTO settings (key, value, updated_at_micros) "
      "VALUES ('device_canary', '$canary', 0)",
    );
    await startup.close();

    // A second service instance, as if the app had been restarted: it must
    // find the key the first one stored and reopen the same workspace.
    final reopened = StartupService(
      paths: paths,
      keyManager: SecureStorageKeyManager(),
      scratch: AppSupportScratchSpace(root: paths.scratchDir),
      diag: const NoopDiag(),
    );
    addTearDown(reopened.close);
    final state = await reopened.bootstrap();
    expect(state, isA<StartupWorkspaceOpen>());

    final rows = await (state as StartupWorkspaceOpen).database
        .customSelect("SELECT value FROM settings WHERE key = 'device_canary'")
        .get();
    expect(rows.single.read<String>('value'), canary);
  });

  testWidgets('a wrong key cannot open the workspace', (tester) async {
    await startup.createFreshWorkspace();
    await startup.close();

    // Same file, a different key: the §7.3 recovery path, exercised against
    // the real on-device ciphertext.
    await keyManager.rekeyDatabase(generateDatabaseKey());
    final stranger = StartupService(
      paths: paths,
      keyManager: keyManager,
      scratch: AppSupportScratchSpace(root: paths.scratchDir),
      diag: const NoopDiag(),
    );
    addTearDown(stranger.close);

    final state = await stranger.bootstrap();
    expect(
      state,
      isA<StartupRecovery>().having(
        (s) => s.reason,
        'reason',
        RecoveryReason.wrongKey,
      ),
    );
    expect(
      paths.databaseFile.existsSync(),
      isTrue,
      reason: 'a failed unlock must never delete the workspace',
    );
  });
}

/// Clears device state so each test starts from a known point.
Future<void> resetDeviceState(LoadoutPaths paths, KeyManager keyManager) async {
  if (paths.dbDir.existsSync()) {
    paths.dbDir.deleteSync(recursive: true);
  }
  if (paths.scratchDir.existsSync()) {
    paths.scratchDir.deleteSync(recursive: true);
  }
  await keyManager.destroyDatabaseKey();
}

int _indexOfBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return -1;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
