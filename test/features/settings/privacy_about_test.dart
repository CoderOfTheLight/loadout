/// Smoke coverage for the static §9 screens: the privacy explainer's key
/// claims render, and About shows name/version/method registry and opens
/// the license page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/settings/presentation/about_screen.dart';
import 'package:loadout/features/settings/presentation/privacy_screen.dart';

import '../../support/app_harness.dart';

void main() {
  testWidgets('privacy screen states the §9 guarantees', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpScreen(tester, const PrivacyScreen());

    expect(find.text('No accounts, no cloud, no analytics'), findsOneWidget);
    expect(find.text('Encrypted at rest'), findsOneWidget);
    expect(find.text('What leaves this device'), findsOneWidget);
    expect(find.text('Diagnostics are content-free'), findsOneWidget);
  });

  testWidgets('the offline claim is true on both platforms, not just Android', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpScreen(tester, const PrivacyScreen());

    // The cross-platform half leads: no network code anywhere, CI-enforced.
    // iOS has no permission model to withhold anything, so a bare "ships
    // without network permission" would be false there.
    expect(
      find.textContaining('contains code that opens a network connection'),
      findsOneWidget,
    );
    expect(
      find.textContaining('an automated release check fails the build'),
      findsOneWidget,
    );
    // The stronger, OS-enforced half is named as Android's.
    expect(
      find.textContaining(
        'On Android it goes further: the app ships without network '
        'permission at all',
      ),
      findsOneWidget,
    );
  });

  testWidgets('what-leaves-the-device covers CSV exports, not just backups', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpScreen(tester, const PrivacyScreen());

    // The old copy said "Nothing — except backup files"; /settings/export
    // writes unencrypted CSV through the same save dialog.
    expect(find.textContaining('except backup files'), findsNothing);
    expect(find.textContaining('Only files you save yourself'), findsOneWidget);
    expect(
      find.textContaining(
        'a plain CSV that opens in Excel, with no '
        'passphrase on it',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('one encrypted file protected by a passphrase'),
      findsOneWidget,
    );
  });

  testWidgets('about screen shows version, method registry, and licenses', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpScreen(tester, const AboutScreen());

    expect(find.text('Loadout'), findsOneWidget);
    expect(find.text('Version 1.0.0+1'), findsOneWidget);
    expect(find.text('direct_median — v3 — since 2026-08'), findsOneWidget);

    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
