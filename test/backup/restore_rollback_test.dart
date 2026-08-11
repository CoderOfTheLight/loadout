/// §11.2: restore rollback — an injected failure at any phase leaves the
/// live workspace exactly as it was (`.pre-restore` renamed back, reopened,
/// content intact) and emits `restoreRolledBack`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/features/backup/domain/backup_service.dart';

import '../infrastructure/harness.dart';

void main() {
  const passphrase = 'correct horse battery';

  for (final failPhase in [
    'after-close',
    'after-export',
    'after-swap',
    'after-reopen',
  ]) {
    test(
      'failure at $failPhase rolls back to the pre-restore workspace',
      () async {
        final h = SecurityHarness.create('rollback_$failPhase');
        addTearDown(h.dispose);

        // Workspace state A goes into the backup.
        final db = await h.startup.createFreshWorkspace();
        await seedWorkspaceData(db);
        final container = await h.backup.createBackup(passphrase: passphrase);
        final kept = File('${h.tempRoot.path}/kept.loadout');
        container.copySync(kept.path);

        // The live workspace then advances to state B — the state a failed
        // restore must preserve.
        await h.startup.database.customStatement(
          "INSERT INTO settings (key, value, updated_at_micros) "
          "VALUES ('state_b_row', '\"b\"', 1)",
        );
        await h.startup.close();
        final deviceKey = await h.keyManager.getOrCreateDatabaseKey();
        final dumpStateB = dumpDatabase(h.paths.databaseFile, deviceKey);
        await h.startup.open();

        final failing = h.backupWithInjector((phase) async {
          if (phase == failPhase) {
            throw StateError('injected failure at $phase');
          }
        });
        final preview = await failing.validateBackup(
          container: kept,
          passphrase: passphrase,
        );
        await expectLater(
          failing.restoreBackup(preview),
          throwsA(
            isA<BackupError>().having(
              (e) => e.kind,
              'kind',
              BackupErrorKind.restoreFailed,
            ),
          ),
        );

        // Rollback invariants: no stray files, live DB reopened and intact.
        expect(
          File('${h.paths.databaseFile.path}.pre-restore').existsSync(),
          isFalse,
          reason: 'the pre-restore copy is renamed back on rollback',
        );
        expect(File('${h.paths.databaseFile.path}.new').existsSync(), isFalse);
        expect(
          h.startup.isOpen,
          isTrue,
          reason: 'rollback reopens the live DB',
        );
        final rows = await h.startup.database
            .customSelect(
              "SELECT value FROM settings WHERE key = 'state_b_row'",
            )
            .get();
        expect(
          rows,
          hasLength(1),
          reason: 'state B survived the failed restore',
        );
        expect(h.diag.has(DiagEvent.restoreRolledBack), isTrue);
        expect(h.diag.has(DiagEvent.restoreOk), isFalse);

        await h.startup.close();
        expect(
          dumpDatabase(h.paths.databaseFile, deviceKey),
          dumpStateB,
          reason: 'live DB content is byte-for-byte the pre-restore state',
        );
      },
    );
  }

  test('a successful restore after a failed one still works', () async {
    final h = SecurityHarness.create('rollback_then_ok');
    addTearDown(h.dispose);
    final db = await h.startup.createFreshWorkspace();
    await seedWorkspaceData(db);
    final container = await h.backup.createBackup(passphrase: passphrase);
    final kept = File('${h.tempRoot.path}/kept.loadout');
    container.copySync(kept.path);

    final failing = h.backupWithInjector((phase) async {
      if (phase == 'after-swap') {
        throw StateError('injected');
      }
    });
    final failedPreview = await failing.validateBackup(
      container: kept,
      passphrase: passphrase,
    );
    await expectLater(
      failing.restoreBackup(failedPreview),
      throwsA(isA<BackupError>()),
    );

    final preview = await h.backup.validateBackup(
      container: kept,
      passphrase: passphrase,
    );
    await h.backup.restoreBackup(preview);
    expect(h.diag.has(DiagEvent.restoreOk), isTrue);
    final rows = await h.startup.database
        .customSelect('SELECT count(*) AS c FROM inventory_movements')
        .get();
    expect(rows.single.read<int>('c'), 3);
  });
}
