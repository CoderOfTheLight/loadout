/// The closed-event "Spent" section (v7): Σ (confirmed depletion × the
/// unit price SNAPSHOTTED at confirm) over the latest revision's priced
/// lines — the money is frozen history, so a later catalog price edit must
/// never move it. Lines whose price was unknown at confirm are counted out
/// loud ('N items had no price — not counted.'); with no priced line at
/// all the section does not render (a "$0" would pretend the event was
/// free), and a never-closed event shows nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/events/presentation/event_detail_screen.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

void main() {
  testWidgets('Spent sums depletion × the SNAPSHOTTED price — a later price '
      'edit never moves it — and counts unpriced lines out loud', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final cups = await seedItem(
        h,
        name: 'Cups',
        unitPrice: Money.fromCents(200),
      );
      final napkins = await seedItem(h, name: 'Napkins');
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [cups, napkins],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [
          CloseoutFormLine(itemId: cups, depletion: Quantity.whole(30)),
          CloseoutFormLine(itemId: napkins, depletion: Quantity.whole(10)),
        ],
      );
      // The price moves AFTER confirm: the closed event's number must not.
      await unwrap(
        h
            .read(catalogServiceProvider)
            .updateItem(
              itemId: cups,
              draft: ItemDraft(name: 'Cups', unitPrice: Money.fromCents(999)),
            ),
      );
    });

    await h.pumpScreen(tester, EventDetailScreen(eventId: eventId));

    expect(find.text('Spent'), findsOneWidget);
    // 30 × $2.00 as snapshotted — NOT 30 × $9.99.
    expect(find.text(r'$60'), findsOneWidget);
    expect(find.textContaining(r'$299'), findsNothing);
    expect(
      find.text(
        'What this event used, at the prices recorded when you '
        'closed out.',
      ),
      findsOneWidget,
    );
    expect(find.text('1 item had no price — not counted.'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('a never-closed event shows no Spent section', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final cups = await seedItem(
        h,
        name: 'Cups',
        unitPrice: Money.fromCents(200),
      );
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [cups],
      );
      await activateEvent(h, eventId);
    });

    await h.pumpScreen(tester, EventDetailScreen(eventId: eventId));
    expect(find.text('Spent'), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('a closeout with no priced line shows no Spent section — '
      'never an invented \$0', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final napkins = await seedItem(h, name: 'Napkins');
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-10',
        exposure: 100,
        itemIds: [napkins],
      );
      await activateEvent(h, eventId);
      await confirmCloseout(
        h,
        eventId,
        exposure: 100,
        lines: [
          CloseoutFormLine(itemId: napkins, depletion: Quantity.whole(10)),
        ],
      );
    });

    await h.pumpScreen(tester, EventDetailScreen(eventId: eventId));
    expect(find.text('Spent'), findsNothing);
    expect(find.textContaining('had no price'), findsNothing);
    await h.flushTimers(tester);
  });
}
