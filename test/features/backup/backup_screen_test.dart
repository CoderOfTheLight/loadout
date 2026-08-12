/// §11.3 backup-screen workflows: passphrase rules (hard minimum 8,
/// advisory meter recommending 12+, match required) and the create flow —
/// container built by the real service, handed to the fake save gateway,
/// scratch session disposed either way.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/backup/presentation/backup_providers.dart';
import 'package:loadout/features/backup/presentation/backup_screen.dart';
import 'package:loadout/features/backup/presentation/file_gateway.dart';
import 'package:path/path.dart' as p;

import '../../support/app_harness.dart';
import 'backup_test_support.dart';

void main() {
  FilledButton createButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Create backup file…'),
      matching: find.byType(FilledButton),
    ),
  );

  Finder passphraseField() => find.byType(TextField).at(0);
  Finder confirmField() => find.byType(TextField).at(1);

  testWidgets('passphrase rules: hard minimum 8, match, advisory meter', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpScreen(tester, const BackupScreen());

    // Empty: disabled.
    expect(createButton(tester).onPressed, isNull);

    // 7 characters: below the hard minimum.
    await tester.enterText(passphraseField(), 'seven77');
    await tester.pump();
    expect(createButton(tester).onPressed, isNull);
    expect(
      find.text('Too short — at least 8 characters are required.'),
      findsOneWidget,
    );

    // 8 characters: meets the minimum, meter still advises 12+.
    await tester.enterText(passphraseField(), 'eightchr');
    await tester.pump();
    expect(
      find.text('Meets the minimum — 12 or more characters is much safer.'),
      findsOneWidget,
    );
    // ... but the confirmation doesn't match yet.
    expect(createButton(tester).onPressed, isNull);

    await tester.enterText(confirmField(), 'different');
    await tester.pump();
    expect(find.text('Passphrases do not match.'), findsOneWidget);
    expect(createButton(tester).onPressed, isNull);

    await tester.enterText(confirmField(), 'eightchr');
    await tester.pump();
    expect(find.text('Passphrases do not match.'), findsNothing);
    expect(createButton(tester).onPressed, isNotNull);

    // Long passphrase: advisory meter reports strong; still enabled.
    await tester.enterText(passphraseField(), 'a strong passphrase');
    await tester.enterText(confirmField(), 'a strong passphrase');
    await tester.pump();
    expect(find.text('Strong passphrase.'), findsOneWidget);
    expect(createButton(tester).onPressed, isNotNull);
  });

  testWidgets('create flow hands the file to the gateway and cleans up', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final gateway = FakeFileGateway();
    final facade = fastBackupFacade(h);
    final container = containerWith(h, [
      fileGatewayProvider.overrideWithValue(gateway),
      backupFacadeProvider.overrideWithValue(facade),
    ]);
    addTearDown(container.dispose);
    await pumpScreenWith(tester, container, const BackupScreen());

    expect(find.text('No backup has been saved yet.'), findsOneWidget);

    await tester.enterText(passphraseField(), 'correct horse battery');
    await tester.enterText(confirmField(), 'correct horse battery');
    await tester.pump();
    await tapVisible(tester, find.text('Create backup file…'));
    await settleUntil(
      tester,
      () => visible(find.text('Backup file saved.')),
      reason: 'backup saved confirmation',
    );

    // The gateway received the app-named container file.
    final save = gateway.saves.single;
    expect(
      save.suggestedName,
      matches(RegExp(r'^loadout-backup-\d{8}-\d{6}\.loadout$')),
    );
    expect(save.bytes, isNotEmpty);

    // The scratch session was disposed after the hand-off.
    expect(File(save.sourcePath).existsSync(), isFalse);
    expect(Directory(p.dirname(save.sourcePath)).existsSync(), isFalse);

    // What left through the gateway is a readable Loadout backup.
    final kept = File(p.join(h.tempDir.path, 'kept.loadout'))
      ..writeAsBytesSync(save.bytes);
    final described = await tester.runAsync(
      () => facade.describeBackup(kept.path),
    );
    expect(described, isA<Ok<Object?>>());

    // Last-backup bookkeeping updated (nudge source, §12.22).
    await settleUntil(
      tester,
      () => visible(find.textContaining('Last backup: ')),
      reason: 'last-backup caption',
    );
  });

  testWidgets('cancelled save discards the backup and records nothing', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final gateway = FakeFileGateway()..cancelSave = true;
    final container = containerWith(h, [
      fileGatewayProvider.overrideWithValue(gateway),
      backupFacadeProvider.overrideWithValue(fastBackupFacade(h)),
    ]);
    addTearDown(container.dispose);
    await pumpScreenWith(tester, container, const BackupScreen());

    await tester.enterText(passphraseField(), 'correct horse battery');
    await tester.enterText(confirmField(), 'correct horse battery');
    await tester.pump();
    await tapVisible(tester, find.text('Create backup file…'));
    await settleUntil(
      tester,
      () => visible(find.textContaining("The backup file wasn't saved")),
      reason: 'cancelled-save notice',
    );

    expect(gateway.saves, isEmpty);
    expect(find.text('No backup has been saved yet.'), findsOneWidget);
    final micros = await tester.runAsync(
      () => h.read(appDatabaseProvider).settingsDao.value(lastBackupAtKey),
    );
    expect(micros, isNull);
  });
}
