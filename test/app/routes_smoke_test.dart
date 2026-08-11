/// Smoke test: every §9 route builds. Stub screens render an AppBar title
/// plus "Not built yet"; the three real onboarding/recovery screens render
/// their widgets. Feature agents replace stub contents — this test proves
/// the router itself never needs touching.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/onboarding/presentation/create_workspace_screen.dart';
import 'package:loadout/features/onboarding/presentation/recovery_screen.dart';
import 'package:loadout/features/onboarding/presentation/welcome_screen.dart';

import '../support/app_harness.dart';

/// Route → AppBar title for every stub route reachable with a workspace.
const Map<String, String> stubRoutes = {
  '/home': 'Home',
  '/events': 'Events',
  '/items': 'Items',
  '/recipes': 'Recipes',
  '/settings': 'Settings',
  '/events/new': 'Event',
  '/events/e1': 'Event',
  '/events/e1/edit': 'Event',
  '/events/e1/forecast': 'Forecast',
  '/events/e1/forecast/i1': 'Forecast line',
  '/events/e1/closeout': 'Close out',
  '/items/new': 'Item',
  '/items/i1': 'Item',
  '/items/i1/edit': 'Item',
  '/movements/new': 'Record movement',
  '/movements/new?kind=receive&itemId=i1': 'Record movement',
  '/movements/m1': 'Movement',
  '/movements/m1/correct': 'Correct entry',
  '/activity': 'Activity',
  '/production': 'Production',
  '/recipes/new': 'Recipe',
  '/recipes/r1': 'Recipe',
  '/recipes/r1/revise': 'Recipe',
  '/settings/backup': 'Backup',
  '/settings/restore': 'Restore',
  '/settings/privacy': 'Privacy',
  '/settings/diagnostics': 'Diagnostics',
  '/settings/reset': 'Reset workspace',
  '/settings/about': 'About',
};

void main() {
  testWidgets('every stub route builds under an open workspace', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    for (final entry in stubRoutes.entries) {
      await h.go(tester, entry.key);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
        reason: 'route ${entry.key} should show the ${entry.value} screen',
      );
      expect(
        find.text('Not built yet'),
        findsOneWidget,
        reason: 'route ${entry.key} should render its stub body',
      );
    }
  });

  testWidgets('onboarding routes build on a fresh install', (tester) async {
    final h = (await tester.runAsync(AppHarness.start))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    expect(find.byType(WelcomeScreen), findsOneWidget);
    await h.go(tester, '/welcome/create');
    expect(find.byType(CreateWorkspaceScreen), findsOneWidget);
  });

  testWidgets('recovery route builds in a recovery state', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.recoveryKeyMissing),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    expect(find.byType(RecoveryScreen), findsOneWidget);
  });
}
