/// §9 `/production` — ProductionPlanningScreen stub test: static content,
/// clearly marked as coming in a later release; no service, no state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/production/presentation/production_planning_screen.dart';

import '../../support/app_harness.dart';

void main() {
  testWidgets('shows the coming-soon copy and readiness checklist', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await h.pumpScreen(tester, const ProductionPlanningScreen());

    expect(find.text('Production planning is coming'), findsOneWidget);
    expect(find.text('Coming in a later release'), findsOneWidget);
    expect(find.text("You're ready:"), findsOneWidget);
    expect(find.text('Recipes ✓'), findsOneWidget);
    expect(find.text('Forecasts ✓'), findsOneWidget);
  });
}
