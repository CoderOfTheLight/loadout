/// Closeout draft autosave (§11.3): debounced 500 ms into
/// `closeout_drafts` via the real CloseoutService, and the draft survives
/// process death — a freshly pumped screen restores every field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';

import '../../support/app_harness.dart';
import '../events/feature_seeds.dart';

void main() {
  testWidgets('autosave debounces 500 ms and survives a restart', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final item = await seedItem(h);
      eventId = await seedEvent(
        h,
        name: 'Market',
        date: '2026-08-10',
        exposure: 150,
        itemIds: [item],
      );
      await activateEvent(h, eventId);
    });

    // No router needed: the screen only navigates on confirm.
    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));

    // Prefill alone never writes a draft.
    var draft = await tester.runAsync<CloseoutFormDraft?>(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft, isNull);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Depletion'),
      '5',
    );
    // 200 ms in: still inside the debounce window — nothing saved yet.
    await tester.pump(const Duration(milliseconds: 200));
    draft = await tester.runAsync<CloseoutFormDraft?>(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft, isNull);

    // 600 ms in: the debounced save has fired.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    draft = await tester.runAsync<CloseoutFormDraft?>(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft, isNotNull);
    expect(draft!.lines.single.depletion!.micros, 5000000);
    expect(draft.confirmedExposure, 150);

    // More edits: flags and exposure ride the same debounced save.
    await tester.ensureVisible(find.text('Ran out'));
    await tester.tap(find.text('Ran out'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmed attendance'),
      '140',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    draft = await tester.runAsync<CloseoutFormDraft?>(
      () => h.read(closeoutServiceProvider).loadDraft(eventId),
    );
    expect(draft!.confirmedExposure, 140);
    expect(draft.lines.single.stockout, isTrue);

    // Process death: tear the widget tree down, then pump a fresh screen —
    // every field comes back from the draft.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await h.pumpScreen(tester, CloseoutScreen(eventId: eventId));
    expect(find.text('140'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ran out'))
          .selected,
      isTrue,
    );
  });
}
