/// The picker's running money (owner request: "it will tell you when you
/// add all the items"). The tally bar carries the count it always did and,
/// under it, what the SELECTION costs at today's prices — climbing on the
/// tick, before anything is saved.
///
/// The honesty rules are the ones the rest of the app plays by: an unpriced
/// selection contributes nothing and is counted out loud ("· 1 not priced"),
/// and with nothing priced at all there is no money line rather than a total
/// that quietly leaves half the list out, or a "$0" pretending the trolley
/// is free.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/features/events/presentation/planned_items_picker.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

/// The sheet, mounted on its own: these tests are about the tally bar's
/// arithmetic, not about the route that opens it.
Widget sheet() => const Scaffold(body: PlannedItemsSheet(initialSelection: []));

void main() {
  testWidgets('the total climbs as priced items are ticked, admits the '
      'unpriced ones without inflating, and falls again on deselect', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final drinks = await folderIdByName(h, 'Drinks');
      final disposables = await folderIdByName(h, 'Disposables');
      await seedItem(
        h,
        name: 'Lemonade',
        folderId: drinks,
        unitPrice: Money.fromCents(250),
      );
      await seedItem(
        h,
        name: 'Cola',
        folderId: drinks,
        unitPrice: Money.fromCents(125),
      );
      await seedItem(h, name: 'Napkins', folderId: disposables);
    });

    await h.pumpScreen(tester, sheet());

    // Nothing ticked: the bar is exactly what it always was. No $0.
    expect(find.text('0 items · 0 folders'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);

    await tester.tap(find.text('Lemonade'));
    await tester.pump();
    expect(find.text('1 item · 1 folder'), findsOneWidget);
    expect(find.text(r'$2.50'), findsOneWidget);

    await tester.tap(find.text('Cola'));
    await tester.pump();
    expect(find.text('2 items · 1 folder'), findsOneWidget);
    expect(find.text(r'$3.75'), findsOneWidget);

    // The unpriced tick is counted and SAID — never folded into the money.
    await tester.tap(find.text('Napkins'));
    await tester.pump();
    expect(find.text('3 items · 2 folders'), findsOneWidget);
    expect(find.text(r'$3.75'), findsOneWidget);
    expect(find.textContaining('1 not priced'), findsOneWidget);

    // Untick a priced one: the money comes back down, the note stays.
    await tester.tap(find.text('Cola'));
    await tester.pump();
    expect(find.text('2 items · 2 folders'), findsOneWidget);
    expect(find.text(r'$2.50'), findsOneWidget);
    expect(find.textContaining('1 not priced'), findsOneWidget);

    // And searching does not re-cost the selection: the total is what she
    // ticked, not what is currently on screen.
    await tester.enterText(
      find.descendant(
        of: find.byType(PlannedItemsSheet),
        matching: find.byType(TextField),
      ),
      'nap',
    );
    await tester.pump();
    expect(find.text('Lemonade'), findsNothing);
    expect(find.text(r'$2.50'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('with nothing priced selected the bar is the count alone — no '
      'total, no note, never a \$0', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final disposables = await folderIdByName(h, 'Disposables');
      await seedItem(h, name: 'Napkins', folderId: disposables);
      await seedItem(h, name: 'Cups', folderId: disposables);
    });

    await h.pumpScreen(tester, sheet());
    await tester.tap(find.text('Napkins'));
    await tester.pump();
    await tester.tap(find.text('Cups'));
    await tester.pump();

    expect(find.text('2 items · 1 folder'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
    expect(find.textContaining('not priced'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('the tally bar carries its money at 200 % text scale, in both '
      'brightnesses', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      final drinks = await folderIdByName(h, 'Drinks');
      await seedItem(
        h,
        name: 'Lemonade',
        folderId: drinks,
        unitPrice: Money.fromCents(250),
      );
      await seedItem(h, name: 'Cola', folderId: drinks);
    });

    // An overflow at 200 % scale throws and fails the test here.
    await h.pumpScreen(tester, sheet());
    await tester.tap(find.text('Lemonade'));
    await tester.pump();
    await tester.tap(find.text('Cola'));
    await tester.pump();
    expect(find.text('2 items · 1 folder'), findsOneWidget);
    expect(find.text(r'$2.50'), findsOneWidget);
    expect(find.textContaining('1 not priced'), findsOneWidget);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text(r'$2.50'), findsOneWidget);
    await h.flushTimers(tester);
  });
}
