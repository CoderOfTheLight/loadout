/// Router + startup-machine integration (§7.3, §9): each bootstrap state
/// lands on its screen, the redirect pins onboarding/recovery, and the two
/// shell-owned flows (create workspace, recovery start-fresh) run end to
/// end against the real services.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/backup/presentation/restore_screen.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/home/presentation/home_screen.dart';
import 'package:loadout/features/onboarding/presentation/create_workspace_screen.dart';
import 'package:loadout/features/onboarding/presentation/recovery_screen.dart';
import 'package:loadout/features/onboarding/presentation/welcome_screen.dart';
import 'package:loadout/infrastructure/startup/startup_service.dart';

import '../support/app_harness.dart';

Future<AppHarness> _start(WidgetTester tester, AppHarnessState state) async {
  final h = (await tester.runAsync(() => AppHarness.start(state: state)))!;
  addTearDown(h.dispose);
  return h;
}

void main() {
  testWidgets('fresh install boots to /welcome', (tester) async {
    final h = await _start(tester, AppHarnessState.fresh);
    await h.pumpApp(tester);

    expect(h.boot.state, isA<StartupFreshWorkspace>());
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('fresh install: deep locations redirect to /welcome', (
    tester,
  ) async {
    final h = await _start(tester, AppHarnessState.fresh);
    await h.pumpApp(tester);

    await h.go(tester, '/items');
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('existing workspace boots to the shell at /home', (tester) async {
    final h = await _start(tester, AppHarnessState.workspace);
    await h.pumpApp(tester);

    expect(h.boot.state, isA<StartupWorkspaceOpen>());
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // The five tab names are part of the product's vocabulary: "Items" is
    // the owner's own word, so none of them were renamed. Pin them.
    for (final tab in ['Home', 'Events', 'Items', 'Recipes', 'Settings']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(tab),
        ),
        findsOneWidget,
        reason: 'tab $tab should be labelled',
      );
    }
    // Onboarding is closed once a workspace exists.
    await h.go(tester, '/welcome');
    expect(find.byType(HomeScreen), findsOneWidget);
    await h.go(tester, '/recovery');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('missing key boots to /recovery and stays pinned', (
    tester,
  ) async {
    final h = await _start(tester, AppHarnessState.recoveryKeyMissing);
    await h.pumpApp(tester);

    expect(
      h.boot.state,
      isA<StartupRecovery>().having(
        (s) => s.reason,
        'reason',
        RecoveryReason.keyMissing,
      ),
    );
    expect(find.byType(RecoveryScreen), findsOneWidget);

    // Pinned: the shell is unreachable ...
    await h.go(tester, '/home');
    expect(find.byType(RecoveryScreen), findsOneWidget);
    // ... but the restore flow entry stays reachable.
    await h.go(tester, '/settings/restore');
    expect(find.byType(RestoreScreen), findsOneWidget);
  });

  testWidgets('wrong key boots to /recovery', (tester) async {
    final h = await _start(tester, AppHarnessState.recoveryWrongKey);
    await h.pumpApp(tester);

    expect(
      h.boot.state,
      isA<StartupRecovery>().having(
        (s) => s.reason,
        'reason',
        RecoveryReason.wrongKey,
      ),
    );
    expect(find.byType(RecoveryScreen), findsOneWidget);
  });

  testWidgets('create-workspace flow lands on /home with a named workspace', (
    tester,
  ) async {
    // The 800x600 default surface is shorter than any phone: the setup form
    // would sit half below the fold, and a tap aimed at a row down the page
    // would land on the pinned action bar instead.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final h = await _start(tester, AppHarnessState.fresh);
    await h.pumpApp(tester);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateWorkspaceScreen), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, defaultWorkspaceName),
      'Taco cart',
    );
    // The policy is chosen from plain-language rows, not a segmented
    // control of stacked percentages.
    final cautious = find.text('Take plenty spare — running out is the worst.');
    await tester.ensureVisible(cautious);
    await tester.pumpAndSettle();
    await tester.tap(cautious);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    final workspace = await tester.runAsync(
      () => h.read(settingsServiceProvider).watchWorkspace().first,
    );
    expect(workspace!.displayName, 'Taco cart');
    expect(workspace.defaultPolicy, PlanningPolicy.cautious);
    expect(h.startup.isOpen, isTrue);
  });

  testWidgets(
    'recovery start-fresh archives the ciphertext behind a typed word',
    (tester) async {
      final h = await _start(tester, AppHarnessState.recoveryKeyMissing);
      await h.pumpApp(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Start fresh'));
      await tester.pumpAndSettle();

      final confirm = find.widgetWithText(
        FilledButton,
        'Archive old data and start fresh',
      );
      // Disabled until the exact confirmation word is typed.
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'fresh-ish');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'FRESH');
      await tester.pumpAndSettle();
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      // Old ciphertext archived (never deleted), new workspace to name.
      expect(find.byType(CreateWorkspaceScreen), findsOneWidget);
      expect(h.paths.databaseFile.existsSync(), isFalse);
      final archived = h.paths.dbDir
          .listSync()
          .map((e) => e.path)
          .where((path) => path.contains('orphaned-'));
      expect(archived, isNotEmpty);
      expect(h.startup.isOpen, isTrue, reason: 'new workspace is open');
    },
  );
}
