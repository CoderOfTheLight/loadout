/// §11.3 reset workflow: typed confirmation gates the danger button; the
/// reset archives the ciphertext (never deletes), destroys the old key,
/// and lands on `/welcome` for a fresh workspace.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/onboarding/presentation/welcome_screen.dart';
import 'package:loadout/features/settings/presentation/workspace_reset_screen.dart';
import 'package:path/path.dart' as p;

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

    // The copy has to match what startFreshFromRecovery actually does: the
    // key that opens the archive is RETAINED before the live entry is
    // destroyed, so the old workspace stays recoverable. The screen used to
    // promise the opposite.
    expect(find.textContaining('permanently unreadable'), findsNothing);
    expect(
      find.textContaining(
        'the key that opens it is kept with it, so the old '
        'workspace can still be recovered',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('not a way to erase it from the device'),
      findsOneWidget,
    );
    // Nothing left on the screen claims the data is gone.
    expect(find.textContaining('is lost'), findsNothing);
    expect(find.textContaining('destroy'), findsNothing);

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

    // Scrolled into view first: the screen is a long explainer, and the
    // danger button sits below the fold on a 600 px viewport.
    await tapVisible(tester, find.text('Archive data and reset workspace'));
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

    // What the screen now promises, checked against behaviour: the key that
    // opens the archive is still on this device, so the old workspace really
    // is recoverable (see startup_service_test.dart, "archived ciphertext
    // stays readable via its retained key").
    expect(
      h.keyManager.retained,
      contains(p.basenameWithoutExtension(archived.single.path)),
    );

    // A fresh key exists for the new workspace.
    final hasKey = await tester.runAsync(h.keyManager.hasDatabaseKey);
    expect(hasKey, isTrue);

    // Routed to /welcome; the redirect pins onboarding until the new
    // workspace is named.
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
