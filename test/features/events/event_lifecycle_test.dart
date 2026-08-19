/// Event lifecycle workflow (§11.3): create/edit through the form,
/// activate, cancel blocked once active (entry hidden), cancel with reason
/// pre-activation, and the closed-event detail (revisions summary + revise
/// entry + edit lock).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

void main() {
  testWidgets('create, edit, activate; cancel entry hidden once active', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() => seedItem(h, name: 'Tortillas'));

    await h.pumpApp(tester);
    await h.go(tester, '/events');

    // Create through the form (date prefilled with today).
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('New event'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Farmers market',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Expected attendance'),
      '150',
    );

    // Planned-items multi-select over the live catalog.
    await tester.ensureVisible(find.text('Add items'));
    await tester.tap(find.text('Add items'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tortillas'));
    await tester.pump();
    // The docked tally reports the selection; Done is a real button.
    expect(find.text('1 item · 1 folder'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Tortillas'), findsOneWidget);

    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();

    // Landed on the detail screen.
    expect(find.text('Farmers market'), findsOneWidget);
    expect(find.text('Planned'), findsOneWidget);
    expect(find.text('150 attendance planned'), findsOneWidget);
    expect(find.text('Planned items (1)'), findsOneWidget);

    // Edit while planned.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Farmers market (moved)',
    );
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(find.text('Farmers market (moved)'), findsOneWidget);

    // Start this event: planned → active; the cancel entry disappears
    // (§12.15: an activated event must be closed out, never cancelled).
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await tester.tap(find.text('Start this event'));
    await tester.pumpAndSettle();
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Start this event'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    // Close out becomes available.
    expect(find.text('Close out'), findsOneWidget);
  });

  testWidgets('the detail screen speaks plainly: a Packing list nobody has '
      'to decode, a button that says what it does, and no dead ends', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    late String forecastEventId;
    await tester.runAsync(() async {
      final item = await seedItem(h, name: 'Tortillas');
      eventId = await seedEvent(
        h,
        name: 'Community dinner',
        date: '2026-09-12',
        exposure: 150,
        itemIds: [item],
      );
      forecastEventId = await seedEvent(
        h,
        name: 'Harvest supper',
        date: '2026-09-19',
        exposure: 150,
        itemIds: [item],
      );
      await h.read(forecastServiceProvider).generateSnapshot(forecastEventId);
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId');

    // The tile is named for the thing it produces, and its caption says
    // whether it exists — never `direct_median v3 · for 150 attendance`.
    expect(find.text('Packing list'), findsOneWidget);
    expect(find.text('Not made yet'), findsOneWidget);
    expect(find.text('Forecast & load list'), findsNothing);
    expect(find.textContaining('direct_median'), findsNothing);

    // The lifecycle action says what it does to THIS event.
    expect(find.text('Start this event'), findsOneWidget);

    // The Production tile is gone: a disabled "Coming soon" row that never
    // navigated anywhere is a dead end, not a feature.
    expect(find.text('Production plan'), findsNothing);
    expect(find.text('Coming soon'), findsNothing);

    // Once a forecast exists the caption says who it is for, in words.
    await h.go(tester, '/events/$forecastEventId');
    expect(find.text('Packing list'), findsOneWidget);
    expect(find.text('For 150 attendance'), findsOneWidget);
    expect(find.text('Not made yet'), findsNothing);
    expect(find.textContaining('direct_median'), findsNothing);
  });

  testWidgets('cancel pre-activation requires a reason', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      eventId = await seedEvent(h, name: 'Rainy popup', date: '2026-08-20');
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId');
    expect(find.text('Planned'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel event…'));
    await tester.pumpAndSettle();

    // The confirm action is disabled until a reason is entered.
    final confirmButton = find.widgetWithText(TextButton, 'Cancel event');
    expect(tester.widget<TextButton>(confirmButton).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'rained out',
    );
    await tester.pump();
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Start this event'), findsNothing);
  });

  testWidgets('closed event: revisions summary, revise entry, edit lock', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final item = await seedItem(h, name: 'Salsa', packSize: null);
      eventId = await seedEvent(
        h,
        name: 'Night market',
        date: '2026-08-01',
        exposure: 120,
        itemIds: [item],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [
          CloseoutFormLine(
            itemId: item,
            loaded: Quantity.fromMicros(10000000),
            returned: Quantity.fromMicros(2000000),
            waste: Quantity.fromMicros(1000000),
            depletion: Quantity.fromMicros(7000000),
          ),
        ],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId');

    expect(find.text('Closed'), findsOneWidget);
    expect(find.textContaining('Closed on'), findsOneWidget);
    expect(find.text('Revise closeout'), findsOneWidget);
    expect(find.text('Closeout revisions'), findsOneWidget);
    expect(find.text('Revision 1'), findsOneWidget);
    expect(find.textContaining('100 attendance confirmed'), findsOneWidget);
    expect(find.text('Accuracy review'), findsOneWidget);
    // No lifecycle actions remain.
    expect(find.text('Start this event'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    // The edit route is locked for closed events (§12.14).
    await h.go(tester, '/events/$eventId/edit');
    expect(
      find.text('This event is closed and can no longer be edited.'),
      findsOneWidget,
    );
  });
}
