/// Widget-test harness for the Gate 3 app shell and every feature screen.
///
/// Composes the app EXACTLY like production (`lib/app/bootstrap.dart`), but
/// over test doubles: an in-memory database (`AppDatabase.forTesting` over
/// `NativeDatabase.memory()` — synchronous, FakeAsync-friendly),
/// [InMemoryKeyManager], temp-dir [LoadoutPaths], and [NoopDiag].
///
/// ## Usage (feature agents: copy this pattern)
///
/// ```dart
/// testWidgets('item list shows items', (tester) async {
///   // Harness setup does real file IO -> ALWAYS create it inside
///   // tester.runAsync (or in setUp, which runs outside FakeAsync).
///   final h = await tester.runAsync(
///     () => AppHarness.start(state: AppHarnessState.workspace),
///   );
///   addTearDown(h!.dispose);
///
///   // Seed data through the real services:
///   await tester.runAsync(
///     () => h.read(catalogServiceProvider).createItem(...),
///   );
///
///   // EITHER pump the full app and navigate ...
///   await h.pumpApp(tester);
///   await h.go(tester, '/items');
///
///   // ... OR pump one screen without the router (no context.push here):
///   await h.pumpScreen(tester, const ItemListScreen());
///
///   expect(find.text('Tortillas'), findsOneWidget);
/// });
/// ```
///
/// Anything that awaits real IO or drift work outside a pump must go
/// through `tester.runAsync`; widget interactions (taps on screens that
/// call services) work with plain `tester.pumpAndSettle()` because the
/// in-memory database completes on microtasks.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/app.dart';
import 'package:loadout/app/bootstrap.dart';
import 'package:loadout/app/router.dart';
import 'package:loadout/app/theme.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/settings/application/settings_service.dart';
import 'package:loadout/infrastructure/files/loadout_paths.dart';
import 'package:loadout/infrastructure/files/scratch_space.dart';
import 'package:loadout/infrastructure/security/hex.dart';
import 'package:loadout/infrastructure/security/key_manager.dart';
import 'package:loadout/infrastructure/startup/startup_service.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

/// Which §7.3 startup state the app boots into.
enum AppHarnessState {
  /// No database, no key → `/welcome`.
  fresh,

  /// Open database with a created (named) workspace → shell `/home`.
  workspace,

  /// Database file present, key absent → `/recovery` (keyMissing).
  recoveryKeyMissing,

  /// Database file present, stored key does not unlock it → `/recovery`
  /// (wrongKey).
  recoveryWrongKey,

  /// No database file, but the workspace is parked at
  /// `db/loadout.db.pre-restore` where an interrupted restore left it, and
  /// the device key still opens it → `/recovery` (interruptedRestore) with
  /// the put-it-back action live.
  recoveryParked,

  /// Same, but the parked bytes are not a database any key on this device
  /// opens → the put-it-back action must refuse honestly and keep the file.
  recoveryParkedUnreadable,
}

final class AppHarness {
  AppHarness._({
    required this.tempDir,
    required this.paths,
    required this.keyManager,
    required this.startup,
    required this.boot,
    required this.container,
  });

  final Directory tempDir;
  final LoadoutPaths paths;
  final InMemoryKeyManager keyManager;

  /// The real [StartupService] / [DatabaseHost] the app is wired to.
  final StartupService startup;

  /// The resolved bootstrap (state + initial location + overrides).
  final AppBootstrap boot;

  /// The container behind the pumped widgets. `read`/`listen` providers
  /// here to seed data or assert state.
  final ProviderContainer container;

  /// Shorthand for `container.read`.
  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  /// Boots the app exactly like `main()` does, in [state]. Call inside
  /// `tester.runAsync` (or `setUp`) — never directly in a `testWidgets`
  /// body, where FakeAsync deadlocks real file IO.
  ///
  /// [overrides] are installed AFTER the bootstrap's own, so a test can
  /// swap a device-only service (the OCR channel, say) for a fake.
  static Future<AppHarness> start({
    AppHarnessState state = AppHarnessState.fresh,
    Diag diag = const NoopDiag(),
    List<Override> overrides = const [],
  }) async {
    final tempDir = Directory.systemTemp.createTempSync('loadout_app_harness');
    final paths = LoadoutPaths(tempDir);
    final keyManager = InMemoryKeyManager();
    final scratch = AppSupportScratchSpace(root: paths.scratchDir, diag: diag);
    final startup = StartupService(
      paths: paths,
      keyManager: keyManager,
      scratch: scratch,
      diag: diag,
      // In-memory database: the file executor is discarded unopened. The
      // wrong-key state throws the same SqliteException(26) a real
      // mismatched SQLCipher open produces — but only while the (dummy)
      // ciphertext file exists, so recovery start-fresh can proceed after
      // archiving it.
      databaseFactory: (executor) {
        if (state == AppHarnessState.recoveryWrongKey &&
            paths.databaseFile.existsSync()) {
          throw SqliteException(
            extendedResultCode: 26,
            message: 'file is not a database',
          );
        }
        return AppDatabase.forTesting(NativeDatabase.memory());
      },
    );

    switch (state) {
      case AppHarnessState.fresh:
        break;
      case AppHarnessState.workspace:
        // Open + name the workspace, then plant a dummy ciphertext file so
        // bootstrap sees present/present and reuses the open handle.
        final db = await startup.open();
        await DriftSettingsService(db).createWorkspace(
          name: 'Test workspace',
          defaultPolicy: PlanningPolicy.balanced,
        );
        _plantDatabaseFile(paths);
      case AppHarnessState.recoveryKeyMissing:
        _plantDatabaseFile(paths); // file present, key absent
      case AppHarnessState.recoveryWrongKey:
        _plantDatabaseFile(paths);
        await keyManager.getOrCreateDatabaseKey(); // present/present
      case AppHarnessState.recoveryParked:
        _plantParkedWorkspace(paths, await keyManager.getOrCreateDatabaseKey());
      case AppHarnessState.recoveryParkedUnreadable:
        await keyManager.getOrCreateDatabaseKey();
        paths.dbDir.createSync(recursive: true);
        File(
          '${paths.databaseFile.path}$preRestoreSuffix',
        ).writeAsStringSync('harness ciphertext placeholder');
    }

    final boot = await bootstrapLoadout(
      startup: startup,
      keyManager: keyManager,
      scratch: scratch,
      diag: diag,
    );
    final container = ProviderContainer(
      overrides: [...boot.overrides, ...overrides],
    );
    return AppHarness._(
      tempDir: tempDir,
      paths: paths,
      keyManager: keyManager,
      startup: startup,
      boot: boot,
      container: container,
    );
  }

  static void _plantDatabaseFile(LoadoutPaths paths) {
    paths.dbDir.createSync(recursive: true);
    paths.databaseFile.writeAsStringSync('harness ciphertext placeholder');
  }

  /// A real (if minimal) SQLCipher workspace at `db/loadout.db.pre-restore`,
  /// exactly where `restoreBackup` renames the live one before it re-encrypts
  /// a restored payload. Written with raw sqlite3 rather than drift so the
  /// widget harness stays synchronous: the recovery probe checks the cipher
  /// key, both integrity sweeps, `user_version`, and the `workspace_meta`
  /// singleton, and this file satisfies all four.
  static void _plantParkedWorkspace(LoadoutPaths paths, Uint8List key) {
    paths.dbDir.createSync(recursive: true);
    final db = sqlite3.open('${paths.databaseFile.path}$preRestoreSuffix');
    try {
      db.execute('PRAGMA key = "x\'${hexEncode(key)}\'";');
      db.execute(
        'CREATE TABLE workspace_meta ('
        'id INTEGER NOT NULL PRIMARY KEY, workspace_uid TEXT NOT NULL);',
      );
      db.execute(
        "INSERT INTO workspace_meta (id, workspace_uid) VALUES (1, 'harness');",
      );
      db.execute('PRAGMA user_version = 1;');
    } finally {
      db.close();
    }
  }

  /// Pumps the FULL app (router, redirect, shell) at the bootstrap-resolved
  /// initial location.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LoadoutApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Navigates the pumped app ([pumpApp] first) and settles.
  ///
  /// Bounded on purpose: a screen that never stops animating (an unresolved
  /// spinner, say) otherwise burns `pumpAndSettle`'s ten-minute default
  /// before the suite reports anything.
  Future<void> go(
    WidgetTester tester,
    String location, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      timeout,
    );
    // Leaving a route auto-disposes its providers, and drift closes the
    // query streams behind them on a zero-duration timer. Flush it, or the
    // test ends with a pending timer.
    await tester.pump(Duration.zero);
  }

  /// Pumps a zero-duration frame so that drift's stream-close timers fire.
  ///
  /// Auto-disposing a provider (leaving a route, popping a form) closes the
  /// query stream behind it on a `Timer(Duration.zero)`. A test that ends
  /// before that timer runs fails with "A Timer is still pending even after
  /// the widget tree was disposed". [go] already does this; call it by hand
  /// after any interaction that pops or disposes a screen.
  Future<void> flushTimers(WidgetTester tester) => tester.pump(Duration.zero);

  /// Pumps ONE screen with the full provider graph but no router — for
  /// screens under test that do not navigate. Navigation calls
  /// (`context.go/push`) would throw here; use [pumpApp] + [go] for those.
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: loadoutTheme(Brightness.light),
          darkTheme: loadoutTheme(Brightness.dark),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Register via `addTearDown(harness.dispose)` (runs outside FakeAsync).
  Future<void> dispose() async {
    container.dispose();
    await startup.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
