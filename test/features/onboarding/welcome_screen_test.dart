/// `/welcome` widget test (design §9): the front door pins the approved
/// copy.
///
/// Proposal §4, word for word: the one sentence of how must make ALL of the
/// owner's stuff feel welcome — cooked, bought, supplies, sold — never just
/// "what you sell". The promise and the privacy line stay put, and the one
/// button leads on to workspace creation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/onboarding/presentation/create_workspace_screen.dart';
import 'package:loadout/features/onboarding/presentation/welcome_screen.dart';

import '../../support/app_harness.dart';

void main() {
  testWidgets('the welcome screen pins the approved copy', (tester) async {
    final h = (await tester.runAsync(() => AppHarness.start()))!;
    addTearDown(h.dispose);

    await h.pumpApp(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);

    // The promise, kept — true for soup and CDs alike.
    expect(find.text('Bring the right amount.'), findsOneWidget);
    // The sentence of how, proposal §4 verbatim.
    expect(
      find.text(
        'List what you bring — the food you make, the supplies you set out, '
        'the things you sell — and Loadout works out how much to take.',
      ),
      findsOneWidget,
    );
    // The privacy line the whole app is built around.
    expect(
      find.text('Everything stays on this phone. Nothing is uploaded, ever.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateWorkspaceScreen), findsOneWidget);
  });
}
