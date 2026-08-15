/// Event lifecycle workflow (§11.3): create/edit through the form,
/// activate, cancel blocked once active (entry hidden), cancel with reason
/// pre-activation, and the closed-event detail (revisions summary + revise
/// entry + edit lock).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    // The rebuilt picker's pinned tally doubles as the Done button.
    await tester.tap(find.text('1 item picked · Done'));
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

    // Activate: planned → active; the cancel entry disappears (§12.15:
    // an activated event must be closed out, never cancelled).
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await tester.tap(find.text('Activate event'));
    await tester.pumpAndSettle();
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Activate event'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    // Close out becomes available.
    expect(find.text('Close out'), findsOneWidget);
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
    expect(find.text('Activate event'), findsNothing);
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
    expect(find.text('Activate event'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    // The edit route is locked for closed events (§12.14).
    await h.go(tester, '/events/$eventId/edit');
    expect(
      find.text('This event is closed and can no longer be edited.'),
      findsOneWidget,
    );
  });
}
