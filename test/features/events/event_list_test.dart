/// EventListScreen (§9, §11.3): status filter segments, All view sectioned
/// by status (cancelled appears there only), empty state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

void main() {
  testWidgets('filters by status; All is sectioned and shows cancelled', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await tester.runAsync(() async {
      await seedEvent(
        h,
        name: 'Planned market',
        date: '2026-09-01',
        exposure: 100,
      );
      final active = await seedEvent(
        h,
        name: 'Active fair',
        date: '2026-08-10',
      );
      await activateEvent(h, active);
      final closed = await seedEvent(
        h,
        name: 'Closed festival',
        date: '2026-08-01',
        exposure: 90,
      );
      await activateEvent(h, closed);
      await confirmCloseout(h, closed, exposure: 80);
      final cancelled = await seedEvent(
        h,
        name: 'Cancelled popup',
        date: '2026-08-20',
      );
      await cancelEvent(h, cancelled);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events');

    // Default filter: Upcoming (= planned).
    expect(find.text('Planned market'), findsOneWidget);
    expect(find.text('Active fair'), findsNothing);
    expect(find.text('Closed festival'), findsNothing);
    expect(find.text('Cancelled popup'), findsNothing);
    // Card shows date + planned exposure with the workspace label.
    expect(find.text('2026-09-01 · 100 attendance planned'), findsOneWidget);

    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text('Active fair'), findsOneWidget);
    expect(find.text('Planned market'), findsNothing);

    await tester.tap(find.text('Closed'));
    await tester.pumpAndSettle();
    expect(find.text('Closed festival'), findsOneWidget);
    expect(find.text('Active fair'), findsNothing);
    expect(find.text('Cancelled popup'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Planned market'), findsOneWidget);
    expect(find.text('Active fair'), findsOneWidget);
    expect(find.text('Closed festival'), findsOneWidget);
    // The cancelled section sits last; scroll it into the lazy list's
    // viewport before asserting.
    await tester.scrollUntilVisible(find.text('Cancelled popup'), 100);
    expect(find.text('Cancelled popup'), findsOneWidget);
    // Sectioned: 'Cancelled' appears as a section header AND a status chip.
    expect(find.text('Cancelled'), findsNWidgets(2));
  });

  testWidgets('zero-depletion closeout still closes (seed sanity)', (
    tester,
  ) async {
    // §5: a confirmed zero is a legal label but deltas are never zero —
    // seeded here through the real service so the list shows it Closed.
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await tester.runAsync(() async {
      final item = await seedItem(h, name: 'Buns');
      final event = await seedEvent(
        h,
        name: 'Quiet day',
        date: '2026-08-02',
        itemIds: [item],
      );
      await activateEvent(h, event);
      await confirmCloseout(
        h,
        event,
        exposure: 10,
        lines: [
          CloseoutFormLine(itemId: item, depletion: Quantity.fromMicros(0)),
        ],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events');
    await tester.tap(find.text('Closed'));
    await tester.pumpAndSettle();
    expect(find.text('Quiet day'), findsOneWidget);
  });

  testWidgets('empty list shows the planning prompt', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    await h.pumpApp(tester);
    await h.go(tester, '/events');
    expect(
      find.text('Plan your first event to get a load list.'),
      findsOneWidget,
    );
  });
}
