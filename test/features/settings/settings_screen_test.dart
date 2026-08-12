/// §11.3 settings workflows: preference edits persist through
/// `SettingsService.updatePreferences`; the OS-lock advisory card is
/// unconditional; the backup nudge banner shows while no backup exists;
/// all sub-screen doors are present.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';

import '../../support/app_harness.dart';
import '../backup/backup_test_support.dart';

void main() {
  Future<AppHarness> boot(WidgetTester tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);
    await h.go(tester, '/settings');
    return h;
  }

  Future<void> openTile(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.pump();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> saveDialogText(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders groups, advisory card, nudge banner, and doors', (
    tester,
  ) async {
    await boot(tester);

    // Workspace group with current values.
    expect(find.text('Test workspace'), findsOneWidget);
    expect(find.text('Balanced (+10 % reserve)'), findsOneWidget);
    expect(find.text('attendance'), findsOneWidget);
    expect(find.text('12 closed events'), findsOneWidget);

    // Unconditional OS-lock advisory card (§12.18).
    expect(
      find.textContaining("Protect it with your phone's screen lock."),
      findsOneWidget,
    );

    // Backup nudge banner (§12.22): no backup exists yet.
    expect(
      find.textContaining("You haven't saved a backup yet."),
      findsOneWidget,
    );

    // Doors to every sub-screen, including the danger zone.
    for (final door in [
      'Back up',
      'Restore',
      'Privacy',
      'Diagnostics',
      'About',
      'Reset workspace',
    ]) {
      await tester.ensureVisible(find.text(door));
      expect(find.text(door), findsOneWidget);
    }
  });

  testWidgets('workspace name edit persists', (tester) async {
    final h = await boot(tester);

    await openTile(tester, 'Workspace name');
    await saveDialogText(tester, 'Taco Ops');

    // The drift stream notification needs real event-loop time.
    await settleUntil(
      tester,
      () => visible(find.text('Taco Ops')),
      reason: 'renamed workspace subtitle',
    );
    final db = h.read(appDatabaseProvider);
    final row = await tester.runAsync(
      () => db.select(db.workspaceMeta).getSingle(),
    );
    expect(row!.displayName, 'Taco Ops');
  });

  testWidgets('policy, exposure label, and history window edits persist', (
    tester,
  ) async {
    final h = await boot(tester);

    await openTile(tester, 'Default planning policy');
    await tester.tap(find.text('Cautious (+20 % reserve)'));
    await tester.pumpAndSettle();
    await settleUntil(
      tester,
      () => visible(find.text('Cautious (+20 % reserve)')),
      reason: 'policy subtitle',
    );

    await openTile(tester, 'Exposure label');
    await saveDialogText(tester, 'covers');
    await settleUntil(
      tester,
      () => visible(find.text('covers')),
      reason: 'exposure label subtitle',
    );

    await openTile(tester, 'History window');
    await saveDialogText(tester, '6');
    await settleUntil(
      tester,
      () => visible(find.text('6 closed events')),
      reason: 'history window subtitle',
    );

    final service = h.read(settingsServiceProvider);
    final (policy, label, window) = (await tester.runAsync(
      () async => (
        await service.defaultPolicy(),
        await service.exposureLabel(),
        await service.historyWindow(),
      ),
    ))!;
    expect(policy, PlanningPolicy.cautious);
    expect(label, 'covers');
    expect(window, 6);
  });
}
