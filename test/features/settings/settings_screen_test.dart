/// §11.3 settings workflows: preference edits persist through
/// `SettingsService.updatePreferences`; the Appearance rows switch the whole
/// app between Follow phone / Light / Dark; the OS-lock advisory card is
/// unconditional; the backup nudge banner shows while no backup exists;
/// all sub-screen doors are present.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/settings/domain/app_theme_choice.dart';
import 'package:loadout/features/settings/presentation/settings_screen.dart';

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

  /// The appearance option the control currently reads as chosen.
  AppThemeChoice? selectedChoice(WidgetTester tester) => tester
      .widget<RadioGroup<AppThemeChoice>>(
        find.byType(RadioGroup<AppThemeChoice>),
      )
      .groupValue;

  Finder choiceTile(AppThemeChoice choice) =>
      find.widgetWithText(RadioListTile<AppThemeChoice>, choice.displayName);

  /// A themed colour the screen is actually painting with.
  Color surface(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SettingsScreen))).colorScheme.surface;

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

    // Plain names, unchanged behaviour: the rows no longer say "Default
    // planning policy" / "Exposure label" / "History window".
    expect(find.text('Default planning policy'), findsNothing);
    expect(find.text('Exposure label'), findsNothing);
    expect(find.text('History window'), findsNothing);

    await openTile(tester, 'How much extra to bring');
    await tester.tap(find.text('Cautious (+20 % reserve)'));
    await tester.pumpAndSettle();
    await settleUntil(
      tester,
      () => visible(find.text('Cautious (+20 % reserve)')),
      reason: 'policy subtitle',
    );

    await openTile(tester, 'What you count (people, plates…)');
    await saveDialogText(tester, 'covers');
    await settleUntil(
      tester,
      () => visible(find.text('covers')),
      reason: 'exposure label subtitle',
    );

    await openTile(tester, 'How far back to look');
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

  testWidgets('appearance offers three named options, the current one chosen', (
    tester,
  ) async {
    await boot(tester);

    for (final choice in AppThemeChoice.values) {
      await tester.ensureVisible(find.text(choice.displayName));
      expect(find.text(choice.displayName), findsOneWidget);
    }
    expect(selectedChoice(tester), AppThemeChoice.system);
    expect(
      tester
          .widget<RadioListTile<AppThemeChoice>>(
            choiceTile(AppThemeChoice.system),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<RadioListTile<AppThemeChoice>>(
            choiceTile(AppThemeChoice.dark),
          )
          .selected,
      isFalse,
    );
  });

  testWidgets('choosing Dark persists and repaints the app immediately', (
    tester,
  ) async {
    final h = await boot(tester);
    final before = surface(tester);
    expect(
      before.computeLuminance(),
      greaterThan(0.5),
      reason: 'the test phone is light, so the app starts light',
    );

    await tapVisible(tester, find.text('Dark'));
    await settleUntil(
      tester,
      () => h.read(themeChoiceProvider) == AppThemeChoice.dark,
      reason: 'the choice to reach the app root',
    );
    // MaterialApp cross-fades between the two themes; let it land.
    await tester.pumpAndSettle();
    expect(surface(tester), isNot(before));

    // A themed colour changed — no restart, no navigation.
    expect(surface(tester).computeLuminance(), lessThan(0.1));
    expect(selectedChoice(tester), AppThemeChoice.dark);
    expect(
      tester
          .widget<RadioListTile<AppThemeChoice>>(
            choiceTile(AppThemeChoice.dark),
          )
          .selected,
      isTrue,
    );

    final stored = await tester.runAsync(
      () => h.read(settingsServiceProvider).themeMode(),
    );
    expect(stored, AppThemeChoice.dark);
  });

  testWidgets('the appearance rows hold up at 200 % text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await boot(tester);

    for (final choice in AppThemeChoice.values) {
      final tile = choiceTile(choice);
      await tester.ensureVisible(tile);
      await tester.pump();
      expect(find.text(choice.displayName), findsOneWidget);
      expect(
        tester.getSize(tile).height,
        greaterThanOrEqualTo(48),
        reason: '${choice.displayName} must stay a thumb-sized target',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
