/// §11.2: backup round-trip — create → describe → validate → restore brings
/// back exactly the content that was backed up (canonical dump equality,
/// user_version included), under the device key, with staging and
/// `.pre-restore` cleaned up.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/features/backup/domain/backup_service.dart';
import 'package:path/path.dart' as p;

import '../infrastructure/harness.dart';
import '../support/schema_version.dart';

void main() {
  late SecurityHarness h;

  setUp(() => h = SecurityHarness.create('backup_roundtrip'));
  tearDown(() => h.dispose());

  test('round-trip restores identical content', () async {
    // Build and snapshot the source-of-truth workspace.
    final db = await h.startup.createFreshWorkspace();
    await seedWorkspaceData(db);
    await h.startup.close();
    final deviceKey = await h.keyManager.getOrCreateDatabaseKey();
    final dumpAtBackup = dumpDatabase(h.paths.databaseFile, deviceKey);
    expect(dumpAtBackup, contains(secretMarker));

    // Create the backup and move the container out of scratch (the UI would
    // hand it to the save dialog and dispose the session).
    final reopened = await h.startup.open();
    final phases = <BackupPhase>[];
    final container = await h.backup.createBackup(
      passphrase: 'correct horse battery',
      onProgress: phases.add,
    );
    expect(phases, [
      BackupPhase.derivingKey,
      BackupPhase.exportingPayload,
      BackupPhase.hashingPayload,
      BackupPhase.writingContainer,
      BackupPhase.done,
    ]);
    expect(
      p.basename(container.path),
      matches(RegExp(r'^loadout-backup-\d{8}-\d{6}\.loadout$')),
    );
    final kept = File('${h.tempRoot.path}/kept.loadout');
    container.copySync(kept.path);
    expect(h.diag.has(DiagEvent.backupCreateOk), isTrue);

    // describeBackup needs no passphrase and reflects the manifest.
    final description = await h.backup.describeBackup(kept);
    expect(description.formatVersion, 1);
    expect(description.cipher, 'sqlcipher4-rawkey');
    expect(description.schemaVersion, appSchemaVersionUnderTest);
    expect(description.counts.movements, 3);
    expect(description.counts.items, 2);
    expect(description.counts.events, 1);
    expect(description.kdf.memoryKiB, testKdfCost.memoryKiB);
    expect(description.kdf.iterations, testKdfCost.iterations);
    expect(description.kdf.parallelism, testKdfCost.parallelism);
    expect(description.kdf.hashLength, 32);

    // The container itself never leaks plaintext.
    final containerBytes = kept.readAsBytesSync();
    expect(
      String.fromCharCodes(containerBytes).contains(secretMarker),
      isFalse,
      reason: 'payload is ciphertext; manifest is content-free',
    );

    // Diverge the live workspace so restore has something to undo.
    await reopened.customStatement(
      "INSERT INTO settings (key, value, updated_at_micros) "
      "VALUES ('post_backup_row', '\"x\"', 1)",
    );

    // validate → preview with verified counts.
    final preview = await h.backup.validateBackup(
      container: kept,
      passphrase: 'correct horse battery',
    );
    expect(preview.verifiedCounts.movements, 3);
    expect(preview.verifiedCounts.items, 2);
    expect(preview.verifiedCounts.events, 1);
    expect(preview.payloadUserVersion, appSchemaVersionUnderTest);
    expect(preview.stagingDir.existsSync(), isTrue);

    // restore, then compare the canonical dump.
    await h.backup.restoreBackup(preview);
    expect(h.diag.has(DiagEvent.restoreOk), isTrue);
    expect(h.startup.isOpen, isTrue);
    await h.startup.close();

    final dumpAfterRestore = dumpDatabase(h.paths.databaseFile, deviceKey);
    expect(
      dumpAfterRestore,
      dumpAtBackup,
      reason: 'restored content must be identical to what was backed up',
    );
    expect(dumpAfterRestore.contains('post_backup_row'), isFalse);

    // Cleanup invariants: staging gone, no .pre-restore, no .new.
    expect(preview.stagingDir.existsSync(), isFalse);
    expect(
      File('${h.paths.databaseFile.path}.pre-restore').existsSync(),
      isFalse,
    );
    expect(File('${h.paths.databaseFile.path}.new').existsSync(), isFalse);
  });

  test('describeBackup on a missing file is notFound', () async {
    await expectLater(
      h.backup.describeBackup(File('${h.tempRoot.path}/nope.loadout')),
      throwsA(
        isA<BackupError>().having(
          (e) => e.kind,
          'kind',
          BackupErrorKind.notFound,
        ),
      ),
    );
  });
}
