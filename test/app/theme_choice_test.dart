/// The owner's appearance choice at the app root: the stored preference
/// beats the phone, "Follow phone" defers to it, the change lands without a
/// restart, and every route — including the ones that render before a
/// workspace or a database exists — inherits it from the one MaterialApp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/bootstrap.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/features/settings/domain/app_theme_choice.dart';

import '../features/backup/backup_test_support.dart' show settleUntil;
import '../support/app_harness.dart';

void main() {
  /// The brightness the app is actually painting with, read off a real
  /// screen's context rather than off the MaterialApp's arguments.
  Brightness painted(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

  Future<AppHarness> boot(
    WidgetTester tester, {
    AppHarnessState state = AppHarnessState.workspace,
    AppThemeChoice? choice,
    Brightness platform = Brightness.light,
  }) async {
    final h = (await tester.runAsync(() => AppHarness.start(state: state)))!;
    addTearDown(h.dispose);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    if (choice != null) {
      await tester.runAsync(
        () => h.read(settingsServiceProvider).setThemeMode(choice),
      );
    }
    tester.platformDispatcher.platformBrightnessTestValue = platform;
    await h.pumpApp(tester);
    return h;
  }

  testWidgets('a chosen light theme beats a dark phone', (tester) async {
    await boot(tester, choice: AppThemeChoice.light, platform: Brightness.dark);

    expect(painted(tester), Brightness.light);
  });

  testWidgets('a chosen dark theme beats a light phone', (tester) async {
    await boot(tester, choice: AppThemeChoice.dark, platform: Brightness.light);

    expect(painted(tester), Brightness.dark);
  });

  testWidgets('Follow phone lets the phone win, both ways', (tester) async {
    await boot(
      tester,
      choice: AppThemeChoice.system,
      platform: Brightness.light,
    );
    expect(painted(tester), Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(painted(tester), Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(painted(tester), Brightness.light);
  });

  testWidgets('the running app repaints on the change — no restart', (
    tester,
  ) async {
    final h = await boot(tester, platform: Brightness.light);
    expect(painted(tester), Brightness.light);

    await tester.runAsync(
      () => h.read(settingsServiceProvider).setThemeMode(AppThemeChoice.dark),
    );
    // Two waits, two reasons: the drift notification needs real event-loop
    // time to reach the root, and MaterialApp cross-fades between the two
    // themes, so the painted brightness only lands once that finishes.
    await settleUntil(
      tester,
      () => h.read(themeChoiceProvider) == AppThemeChoice.dark,
      reason: 'the choice to reach the app root',
    );
    await tester.pumpAndSettle();

    expect(painted(tester), Brightness.dark);
  });

  // No widgets, no FakeAsync: this one is about what the provider graph
  // holds the instant bootstrap hands it over, before any frame.
  test('the first frame after a cold start already has the choice', () async {
    final h = await AppHarness.start(state: AppHarnessState.workspace);
    addTearDown(h.dispose);
    await h.read(settingsServiceProvider).setThemeMode(AppThemeChoice.dark);

    // What the next launch does: bootstrap resolves the choice BEFORE
    // runApp, so nothing paints the other brightness while the watch
    // stream is still loading.
    final boot = await bootstrapLoadout(
      startup: h.startup,
      keyManager: h.keyManager,
      scratch: h.read(scratchSpaceProvider),
      diag: const NoopDiag(),
    );
    final container = ProviderContainer(overrides: boot.overrides);
    addTearDown(container.dispose);

    expect(container.read(startupThemeChoiceProvider), AppThemeChoice.dark);
    // Read synchronously: no stream value can have arrived yet.
    expect(container.read(themeChoiceProvider), AppThemeChoice.dark);
  });

  for (final state in const [
    AppHarnessState.fresh,
    AppHarnessState.recoveryKeyMissing,
  ]) {
    testWidgets('$state renders with no database open, following the phone', (
      tester,
    ) async {
      final h = await boot(tester, state: state, platform: Brightness.dark);

      // No database to read the preference from: fall back, never throw.
      expect(h.read(themeChoiceProvider), AppThemeChoice.system);
      expect(painted(tester), Brightness.dark);
      expect(tester.takeException(), isNull);
    });
  }
}
