/// §11.3 restore workflows: staged flow (pick → manifest info → passphrase
/// → verified preview → typed REPLACE → restore), wrong-passphrase vs
/// corrupt-file distinct content-free messages, and the REPLACE gate.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/backup/application/backup_facade.dart';
import 'package:loadout/features/backup/presentation/backup_providers.dart';
import 'package:loadout/features/backup/presentation/file_gateway.dart';
import 'package:loadout/features/backup/presentation/restore_screen.dart';
import 'package:path/path.dart' as p;

import '../../support/app_harness.dart';
import 'backup_test_support.dart';

void main() {
  const passphrase = 'open sesame twelve';

  FilledButton replaceButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Replace workspace with backup'),
          matching: find.byType(FilledButton),
        ),
      );

  /// Creates a real backup of the harness workspace and parks it outside
  /// scratch, ready for the fake pick dialog.
  Future<String> createFixtureBackup(
    WidgetTester tester,
    AppHarness h,
    BackupFacade facade,
  ) async {
    final path = await tester.runAsync(() async {
      final result = await facade.createBackup(passphrase: passphrase);
      final handle = (result as Ok<BackupFileHandle>).value;
      final kept = File(p.join(h.tempDir.path, 'fixture.loadout'));
      handle.file.copySync(kept.path);
      await h.read(scratchSpaceProvider).disposeSession(handle.file.parent);
      return kept.path;
    });
    return path!;
  }

  testWidgets(
    'staged flow: manifest, wrong passphrase, verified preview, REPLACE',
    (tester) async {
      final h = (await tester.runAsync(
        () => AppHarness.start(state: AppHarnessState.workspace),
      ))!;
      addTearDown(h.dispose);
      final facade = fastBackupFacade(h);
      final gateway = FakeFileGateway();
      final container = containerWith(h, [
        fileGatewayProvider.overrideWithValue(gateway),
        restoreFacadeProvider.overrideWithValue(facade),
      ]);
      addTearDown(container.dispose);
      gateway.pickResult = await createFixtureBackup(tester, h, facade);

      await pumpScreenWith(tester, container, const RestoreScreen());

      // Stage 1: pick → manifest info immediately, no passphrase.
      await tapVisible(tester, find.text('Choose backup file…'));
      await settleUntil(
        tester,
        () => visible(find.text('From the file (not verified yet)')),
        reason: 'manifest card',
      );
      expect(find.textContaining('Created: '), findsOneWidget);
      expect(
        find.textContaining('0 movements · 0 items · 0 events'),
        findsOneWidget,
      );
      // No preview and no REPLACE section yet.
      expect(find.text('Verified backup contents'), findsNothing);

      // Stage 2: wrong passphrase → distinct content-free error, no preview.
      await tester.enterText(find.byType(TextField).first, 'wrong passphrase');
      await tester.pump();
      await tapVisible(tester, find.text('Unlock and verify'));
      await settleUntil(
        tester,
        () => visible(
          find.textContaining('That passphrase does not unlock this backup.'),
        ),
        reason: 'wrong-passphrase message',
      );
      expect(find.text('Verified backup contents'), findsNothing);
      expect(
        find.textContaining('Your current data has not been changed.'),
        findsOneWidget,
      );

      // Stage 3: correct passphrase → verified counts preview.
      await tester.enterText(find.byType(TextField).first, passphrase);
      await tester.pump();
      await tapVisible(tester, find.text('Unlock and verify'));
      await settleUntil(
        tester,
        () => visible(find.text('Verified backup contents')),
        reason: 'verified preview',
      );
      expect(find.text('Schema version: 1'), findsOneWidget);

      // Stage 4: typed REPLACE gates the destructive button.
      expect(replaceButton(tester).onPressed, isNull);
      await tester.enterText(find.byType(TextField).at(1), 'replace');
      await tester.pump();
      expect(replaceButton(tester).onPressed, isNull, reason: 'exact word');
      await tester.enterText(find.byType(TextField).at(1), 'REPLACE');
      await tester.pump();
      expect(replaceButton(tester).onPressed, isNotNull);

      // Stage 5: restore. On success the database generation is bumped so
      // the provider graph rebuilds off the reopened database.
      await tapVisible(tester, find.text('Replace workspace with backup'));
      await settleUntil(
        tester,
        () => container.read(databaseGenerationProvider) > 0,
        reason: 'database generation bump',
      );
      await settleUntil(
        tester,
        () => visible(find.text('Restore complete.')),
        reason: 'success card',
      );
      expect(container.read(databaseGenerationProvider), 1);
      expect(h.startup.isOpen, isTrue);
    },
  );

  testWidgets('corrupt file gets a distinct content-free message', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final gateway = FakeFileGateway();
    final container = containerWith(h, [
      fileGatewayProvider.overrideWithValue(gateway),
      restoreFacadeProvider.overrideWithValue(fastBackupFacade(h)),
    ]);
    addTearDown(container.dispose);
    final garbage = File(p.join(h.tempDir.path, 'garbage.loadout'))
      ..writeAsStringSync('not a zip at all');
    gateway.pickResult = garbage.path;

    await pumpScreenWith(tester, container, const RestoreScreen());
    await tapVisible(tester, find.text('Choose backup file…'));
    await settleUntil(
      tester,
      () => visible(
        find.textContaining('This file is not a readable Loadout backup.'),
      ),
      reason: 'corrupt-file message',
    );
    // The flow never advances past the picker.
    expect(find.text('From the file (not verified yet)'), findsNothing);
    expect(
      find.textContaining('Your current data has not been changed.'),
      findsOneWidget,
    );
  });
}
