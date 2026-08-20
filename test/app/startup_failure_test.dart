/// §11.3: the app must not fail to a blank screen.
///
/// `main()` runs the §7.3 startup machine before `runApp`. These tests drive
/// the real production path — `bootstrapOrFail` over a real
/// [StartupService], key manager, scratch space and [RingFileDiag], with the
/// database open rigged to throw — and assert on what the owner is left
/// looking at:
///
///  - a throw becomes a screen with plain words, never a blank frame and
///    never the exception;
///  - the §7.2 cipher guard still refuses to run, but says so;
///  - "Try again" really re-runs the bootstrap, and restore is reachable
///    from a state where no database is open;
///  - the diagnostics log — which normally lives behind the app that will
///    not open — can be exported from here;
///  - a widget that fails to build renders words rather than the
///    framework's grey rectangle.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/app.dart';
import 'package:loadout/app/bootstrap.dart';
import 'package:loadout/app/error_handling.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/startup_failure_app.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/features/backup/presentation/file_gateway.dart';
import 'package:loadout/features/backup/presentation/restore_screen.dart';
import 'package:loadout/features/onboarding/presentation/startup_failure_screen.dart';
import 'package:loadout/infrastructure/diagnostics/diag_sink.dart';
import 'package:loadout/infrastructure/files/loadout_paths.dart';
import 'package:loadout/infrastructure/files/scratch_space.dart';
import 'package:loadout/infrastructure/security/key_manager.dart';
import 'package:loadout/infrastructure/startup/startup_service.dart';

import '../features/backup/backup_test_support.dart';

/// A production-shaped bootstrap whose database open throws.
final class FailedBoot {
  FailedBoot({
    required this.tempDir,
    required this.paths,
    required this.keyManager,
    required this.scratch,
    required this.diag,
    required this.startup,
    required this.failure,
    required this.stopThrowing,
  });

  final Directory tempDir;
  final LoadoutPaths paths;
  final InMemoryKeyManager keyManager;
  final ScratchSpace scratch;
  final RingFileDiag diag;
  final StartupService startup;
  final BootstrapFailed failure;

  /// Lets the NEXT open succeed — whatever was wrong (a restore finished, a
  /// transient failure passed) is no longer wrong.
  final void Function() stopThrowing;

  String get log => diag.logFile.readAsStringSync();

  /// Exactly what the failure screen's "Try again" runs: the same services,
  /// the same entry point.
  Future<BootstrapOutcome> retry() => bootstrapOrFail(
    startup: startup,
    keyManager: keyManager,
    scratch: scratch,
    diag: diag,
  );

  /// [failure] plus test-only overrides (the file-dialog seam has no
  /// platform channel in host tests).
  BootstrapFailed withOverrides(List<Override> extra) => BootstrapFailed(
    kind: failure.kind,
    overrides: [...failure.overrides, ...extra],
  );

  Future<void> dispose() async {
    await startup.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

/// Wires the real services over a temp directory, plants present/present
/// (ciphertext on disk, key in the store) so bootstrap takes the normal open
/// path, and rigs that open to throw [error].
Future<FailedBoot> bootThatThrows(Object error) async {
  final tempDir = Directory.systemTemp.createTempSync('loadout_startup_fail');
  final paths = LoadoutPaths(tempDir);
  final keyManager = InMemoryKeyManager();
  final diag = RingFileDiag(logFile: paths.diagLogFile);
  final scratch = AppSupportScratchSpace(root: paths.scratchDir, diag: diag);
  var explode = true;
  final startup = StartupService(
    paths: paths,
    keyManager: keyManager,
    scratch: scratch,
    diag: diag,
    databaseFactory: (_) {
      if (explode) throw error;
      // In-memory once it stops throwing: the file executor is discarded
      // unopened, exactly as in AppHarness.
      return AppDatabase.forTesting(NativeDatabase.memory());
    },
  );
  paths.dbDir.createSync(recursive: true);
  paths.databaseFile.writeAsStringSync('ciphertext placeholder');
  await keyManager.getOrCreateDatabaseKey();

  final outcome = await bootstrapOrFail(
    startup: startup,
    keyManager: keyManager,
    scratch: scratch,
    diag: diag,
  );
  return FailedBoot(
    tempDir: tempDir,
    paths: paths,
    keyManager: keyManager,
    scratch: scratch,
    diag: diag,
    startup: startup,
    failure: outcome as BootstrapFailed,
    stopThrowing: () => explode = false,
  );
}

/// The §7.2 guard's own error: plain SQLite linked into the build.
Object get cipherMissingError =>
    StateError('SQLCipher not linked; refusing plain SQLite');

/// Anything else that stops the open — a migration above all.
Object get migrationError => StateError('migration halted at v6');

Future<void> pumpFailure(
  WidgetTester tester,
  BootstrapFailed failure, {
  Future<BootstrapOutcome> Function()? retry,
}) async {
  await tester.pumpWidget(
    StartupFailureApp(failure: failure, retry: retry ?? () async => failure),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a bootstrap that throws renders a screen, not a blank app', (
    tester,
  ) async {
    final boot = (await tester.runAsync(() => bootThatThrows(migrationError)))!;
    addTearDown(boot.dispose);
    expect(boot.failure.kind, BootstrapFailureKind.workspaceUnreadable);

    await pumpFailure(tester, boot.failure);

    expect(find.byType(StartupFailureScreen), findsOneWidget);
    expect(find.text('Loadout could not start.'), findsOneWidget);
    expect(
      find.textContaining(
        'Something went wrong while it was opening your '
        'data.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('nothing has been deleted'),
      findsOneWidget,
      reason: 'the sentence that matters most, and it is true',
    );

    // Both ways out, and the way to get the log off the device.
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Restore from backup file'), findsOneWidget);
    expect(find.text('Save diagnostics file…'), findsOneWidget);

    // §10: never the exception, the stack, or an internal identifier.
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('migration halted'), findsNothing);
    expect(find.textContaining(boot.paths.databaseFile.path), findsNothing);
  });

  testWidgets('the failure is in the log before the screen is shown', (
    tester,
  ) async {
    final boot = (await tester.runAsync(() => bootThatThrows(migrationError)))!;
    addTearDown(boot.dispose);

    final log = boot.log;
    // The startup machine's own line, plus the "and the app did not come
    // up" line the exported file needs to be useful.
    expect(log, contains('E migrationFail'));
    expect(log, contains('E startupFailed'));
    expect(log, contains('err=StateError'));
    // Content-free (§10): the message never reaches the file.
    expect(log, isNot(contains('migration halted')));
    expect(log, isNot(contains(boot.paths.databaseFile.path)));
  });

  testWidgets('a missing cipher refuses onto the screen and stays refusing', (
    tester,
  ) async {
    final boot = (await tester.runAsync(
      () => bootThatThrows(cipherMissingError),
    ))!;
    addTearDown(boot.dispose);
    expect(boot.failure.kind, BootstrapFailureKind.cipherMissing);

    await pumpFailure(tester, boot.failure);

    expect(find.text('Loadout could not start.'), findsOneWidget);
    expect(
      find.textContaining('missing the part that unlocks your data'),
      findsOneWidget,
    );
    expect(
      find.textContaining('never fall back to keeping your data unprotected'),
      findsOneWidget,
    );

    // §7.2 unchanged: it does NOT proceed, and it offers nothing that would
    // pretend it could. Retrying or restoring cannot link SQLCipher.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Restore from backup file'), findsNothing);
    expect(boot.failure.canRetry, isFalse);
    expect(boot.failure.canRestore, isFalse);
    expect(boot.startup.isOpen, isFalse);

    // Nothing was written over the workspace, and the refusal is logged.
    expect(
      boot.paths.databaseFile.readAsStringSync(),
      'ciphertext placeholder',
    );
    expect(boot.log, contains('E dbCipherMissing'));
    expect(boot.log, contains('E startupFailed'));

    // Still exportable — this is the only screen that can hand over the log.
    expect(find.text('Save diagnostics file…'), findsOneWidget);
  });

  testWidgets('try again re-runs the bootstrap and hands over to the app', (
    tester,
  ) async {
    final boot = (await tester.runAsync(() => bootThatThrows(migrationError)))!;
    addTearDown(boot.dispose);

    var attempts = 0;
    await pumpFailure(
      tester,
      boot.failure,
      retry: () {
        attempts++;
        return boot.retry();
      },
    );

    // A retry that fails again stays put — and does not stack a second
    // screen or lose the ways out. (settleUntil, not pumpAndSettle: a real
    // bootstrap does real file IO, and the busy spinner never settles.)
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(
      find.text('Try again'),
      findsNothing,
      reason: 'the button goes busy while the bootstrap is in flight',
    );
    await settleUntil(
      tester,
      () => visible(find.text('Try again')),
      reason: 'the failed retry lands back on the screen',
    );
    expect(attempts, 1);
    expect(find.byType(StartupFailureScreen), findsOneWidget);

    // Whatever was wrong is no longer wrong: the SAME services boot, and the
    // app takes over in place — no force-quit, no second database handle.
    boot.stopThrowing();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await settleUntil(
      tester,
      () => visible(find.byType(LoadoutApp)),
      reason: 'the app after a successful retry',
    );
    expect(attempts, 2);
    expect(find.byType(StartupFailureScreen), findsNothing);
    expect(find.byType(LoadoutApp), findsOneWidget);
    expect(boot.startup.isOpen, isTrue);

    // Tear the tree down inside the body: disposing the ProviderScope closes
    // drift's query streams on a zero-duration timer, and a test that ends
    // first fails with "a Timer is still pending".
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('restore is reachable, and coming back re-runs the bootstrap', (
    tester,
  ) async {
    final boot = (await tester.runAsync(() => bootThatThrows(migrationError)))!;
    addTearDown(boot.dispose);

    var attempts = 0;
    await pumpFailure(
      tester,
      boot.withOverrides([
        fileGatewayProvider.overrideWithValue(FakeFileGateway()),
      ]),
      retry: () async {
        attempts++;
        return boot.failure;
      },
    );

    await tester.tap(find.text('Restore from backup file'));
    await tester.pumpAndSettle();
    // The §8.2 flow builds with no database open (restoreFacadeProvider's
    // whole reason for existing).
    expect(find.byType(RestoreScreen), findsOneWidget);
    expect(find.text('Choose backup file…'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      attempts,
      1,
      reason: 'a finished restore must land in the app without a force-quit',
    );
    expect(find.byType(StartupFailureScreen), findsOneWidget);
    await tester.pump(Duration.zero);
  });

  testWidgets('the diagnostics log can be exported from the failure screen', (
    tester,
  ) async {
    final boot = (await tester.runAsync(() => bootThatThrows(migrationError)))!;
    addTearDown(boot.dispose);
    final gateway = FakeFileGateway();

    await pumpFailure(
      tester,
      boot.withOverrides([fileGatewayProvider.overrideWithValue(gateway)]),
    );

    await tapVisible(tester, find.text('Save diagnostics file…'));
    await tester.pumpAndSettle();

    final save = gateway.saves.single;
    expect(save.suggestedName, 'loadout-diagnostics.log');
    expect(save.sourcePath, boot.diag.logFile.path);
    expect(String.fromCharCodes(save.bytes), contains('startupFailed'));
    expect(find.text('Diagnostics file saved.'), findsOneWidget);
  });

  testWidgets('with no storage at all there is no dead button on the screen', (
    tester,
  ) async {
    // Paths never resolved: no diagnostics file, no key store, no restore.
    const failure = BootstrapFailed(
      kind: BootstrapFailureKind.storageUnavailable,
    );
    await pumpFailure(tester, failure);

    expect(find.text('Loadout could not start.'), findsOneWidget);
    expect(
      find.textContaining('could not reach the place on this device'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Restore from backup file'), findsNothing);
    expect(find.text('Save diagnostics file…'), findsNothing);
  });

  testWidgets('the failure screen holds up at 200 % text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final boot = (await tester.runAsync(() => bootThatThrows(migrationError)))!;
    addTearDown(boot.dispose);

    await pumpFailure(tester, boot.failure);

    for (final label in const [
      'Try again',
      'Restore from backup file',
      'Save diagnostics file…',
    ]) {
      final text = find.text(label);
      await tester.ensureVisible(text);
      await tester.pump();
      expect(text, findsOneWidget);
      final button = find
          .ancestor(
            of: text,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first;
      expect(
        tester.getSize(button).height,
        greaterThanOrEqualTo(48),
        reason: '$label must stay a thumb-sized target',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a widget that fails to build renders words, not a grey box', (
    tester,
  ) async {
    // flutter_test asserts ErrorWidget.builder is back to its own before the
    // body returns, so this is restored here rather than in a tearDown.
    final previousBuilder = ErrorWidget.builder;
    try {
      installLoadoutErrorHandlers();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (_) => throw StateError('kaboom in build')),
        ),
      );

      expect(tester.takeException(), isA<StateError>());
      expect(find.textContaining('could not be shown'), findsOneWidget);
      expect(find.textContaining('Nothing has been changed'), findsOneWidget);
      expect(find.textContaining('kaboom'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    } finally {
      ErrorWidget.builder = previousBuilder;
      ui.PlatformDispatcher.instance.onError = null;
    }
  });

  testWidgets('the error widget survives 200 % text scale and no theme', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // No MaterialApp, no Theme, no Directionality above it — exactly where
    // ErrorWidget.builder can be called from.
    await tester.pumpWidget(
      loadoutErrorWidget(
        FlutterErrorDetails(exception: StateError('no theme here')),
      ),
    );

    expect(find.textContaining('could not be shown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the ways out offered match what could possibly help', () {
    final wired = [diagProvider.overrideWithValue(const NoopDiag())];
    expect(
      BootstrapFailed(
        kind: BootstrapFailureKind.workspaceUnreadable,
        overrides: wired,
      ).canRestore,
      isTrue,
    );
    expect(
      BootstrapFailed(
        kind: BootstrapFailureKind.cipherMissing,
        overrides: wired,
      ).canRestore,
      isFalse,
      reason:
          'a restore re-encrypts the payload with the cipher that is '
          'missing',
    );
    expect(
      const BootstrapFailed(
        kind: BootstrapFailureKind.workspaceUnreadable,
      ).canRestore,
      isFalse,
      reason: 'restore needs the services that were never wired',
    );
    expect(
      BootstrapFailed(
        kind: BootstrapFailureKind.cipherMissing,
        overrides: wired,
      ).canRetry,
      isFalse,
      reason: 'nothing about a retry links SQLCipher into this build',
    );
    expect(
      const BootstrapFailed(
        kind: BootstrapFailureKind.storageUnavailable,
      ).canRetry,
      isTrue,
    );
  });
}
