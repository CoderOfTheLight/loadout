/// §11.3 reset workflow: typed confirmation gates the danger button; the
/// reset archives the ciphertext (never deletes), destroys the old key,
/// and lands on `/welcome` for a fresh workspace.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/onboarding/presentation/welcome_screen.dart';
import 'package:loadout/features/settings/presentation/workspace_reset_screen.dart';

import '../../support/app_harness.dart';
import '../backup/backup_test_support.dart';

void main() {
  testWidgets('typed confirmation gates the reset; reset archives and '
      'routes to welcome', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);
    await h.go(tester, '/settings/reset');

    expect(find.byType(WorkspaceResetScreen), findsOneWidget);
    expect(find.textContaining('it is never deleted'), findsOneWidget);

    FilledButton dangerButton() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Archive data and reset workspace'),
        matching: find.byType(FilledButton),
      ),
    );

    // Gated until the exact word is typed.
    expect(dangerButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'reset please');
    await tester.pump();
    expect(dangerButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField), resetConfirmationWord);
    await tester.pump();
    expect(dangerButton().onPressed, isNotNull);

    final hadDbFile = h.paths.databaseFile.existsSync();
    expect(hadDbFile, isTrue, reason: 'harness plants ciphertext');

    await tester.tap(find.text('Archive data and reset workspace'));
    await settleUntil(
      tester,
      () => visible(find.byType(WelcomeScreen)),
      reason: 'welcome screen after reset',
    );

    // Ciphertext archived (never deleted), authoritative file gone.
    final archived = h.paths.dbDir
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('orphaned-'))
        .toList();
    expect(archived, hasLength(1));
    expect(h.paths.databaseFile.existsSync(), isFalse);

    // A fresh key exists for the new workspace.
    final hasKey = await tester.runAsync(h.keyManager.hasDatabaseKey);
    expect(hasKey, isTrue);

    // Routed to /welcome; the redirect pins onboarding until the new
    // workspace is named.
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
