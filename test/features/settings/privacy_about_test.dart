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
    expect(
      find.textContaining('except backup files you explicitly save'),
      findsOneWidget,
    );
    expect(
      find.textContaining('ships without network permission'),
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
    expect(find.text('direct_median — v2 — since 2026-08'), findsOneWidget);

    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
