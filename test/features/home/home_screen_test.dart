/// HomeScreen widget tests (design §9 `/home`, §11.3).
///
/// Covers the two states the owner actually meets — a brand-new workspace
/// that has to explain what the app is for, and a working one that has to
/// lead with what needs doing — plus forecast readiness (which now reads
/// `ForecastBasis`, so a serves-baseline line is never announced as "no
/// history"), and the 200 % text-scale pass on a 320 dp viewport.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/router.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';
import 'package:loadout/features/events/presentation/event_edit_screen.dart';
import 'package:loadout/features/home/presentation/home_screen.dart';
import 'package:loadout/features/inventory/presentation/movement_entry_screen.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/inventory/presentation/movement_display.dart';
import 'package:loadout/app/theme.dart';

import '../../support/app_harness.dart';

String _date(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Imperative pushes land beyond `currentConfiguration.uri`, which keeps
/// reporting the shell location — assert on the destination screen instead.

/// The dashboard is a phone-shaped scrolling column, and the default
/// 800x600 test window is shorter than any real phone: content below the
/// fold is never built, so finders miss it and taps land on nothing. Use a
/// phone-width, generously tall surface instead.
void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<String> _seedItem(
  AppHarness h,
  WidgetTester tester, {
  String name = 'Tortillas',
  Quantity? servesPerUnit,
  Money? unitPrice,
}) async {
  final result = await tester.runAsync(
    () => h
        .read(catalogServiceProvider)
        .createItem(
          ItemDraft(
            name: name,
            servesPerUnit: servesPerUnit,
            unitPrice: unitPrice,
          ),
        ),
  );
  return result!.fold((id) => id, (error) => throw StateError(error.code));
}

/// An upcoming event with a PERSISTED packing list over [itemIds] — the
/// only thing that gives Home a "things to bring" figure to show.
Future<String> _seedPlannedEvent(
  AppHarness h,
  WidgetTester tester, {
  required String name,
  required List<String> itemIds,
  int plannedExposure = 100,
  int inDays = 2,
  bool withSnapshot = true,
}) async {
  final eventId = await tester.runAsync(() async {
    final created = await h
        .read(eventServiceProvider)
        .createEvent(
          EventDraft(
            name: name,
            scheduledDate: _date(DateTime.now().add(Duration(days: inDays))),
            plannedExposure: plannedExposure,
            plannedItemIds: itemIds,
          ),
        );
    final id = created.fold(
      (id) => id,
      (error) => throw StateError(error.code),
    );
    if (withSnapshot) {
      await h.read(forecastServiceProvider).generateSnapshot(id);
    }
    return id;
  });
  return eventId!;
}

/// Item with −2 on hand, an active event held yesterday (closeout pending),
/// and a planned event tomorrow (the next event).
Future<void> _seedDashboard(AppHarness h, WidgetTester tester) async {
  final itemId = await _seedItem(h, tester);
  await tester.runAsync(() async {
    final inventory = h.read(inventoryServiceProvider);
    await inventory.record(
      MovementFormDraft(
        itemId: itemId,
        kind: MovementKind.waste,
        quantity: Quantity.whole(2),
      ),
    );
    final events = h.read(eventServiceProvider);
    final yesterday = await events.createEvent(
      EventDraft(
        name: 'Taco Night',
        scheduledDate: _date(DateTime.now().subtract(const Duration(days: 1))),
        plannedItemIds: [itemId],
      ),
    );
    final yesterdayId = yesterday.fold(
      (id) => id,
      (error) => throw StateError(error.code),
    );
    await events.activate(yesterdayId);
    await events.createEvent(
      EventDraft(
        name: 'Street Fair',
        scheduledDate: _date(DateTime.now().add(const Duration(days: 1))),
        plannedItemIds: [itemId],
      ),
    );
  });
}

void main() {
  testWidgets('a brand-new workspace explains what the app is for', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);

    // The promise, then the loop, in the owner's words — not one bare
    // "Add item" button with no explanation (owner feedback #5).
    expect(find.text('Bring the right amount to every event.'), findsOneWidget);
    expect(find.text('Add the things you bring'), findsOneWidget);
    expect(find.text('Plan an event'), findsWidgets);
    expect(find.text('Say how it went'), findsOneWidget);

    await tester.tap(find.text('Add my first item'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemEditScreen), findsOneWidget);
    expect(
      tester.widget<ItemEditScreen>(find.byType(ItemEditScreen)).itemId,
      isNull,
      reason: 'the first step opens the create form, not an edit form',
    );
  });

  testWidgets('the first run offers planning an event as the second step', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Plan an event'));
    await tester.pumpAndSettle();
    expect(find.byType(EventEditScreen), findsOneWidget);
  });

  testWidgets('dashboard leads with what needs doing', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    await h.pumpApp(tester);

    // The screen opens with the state of the kitchen, in numbers.
    expect(find.text('item on hand'), findsOneWidget);
    // (1) Pending closeout: ONE tight line — state word, the job, when —
    // and urgency is border + icon + word + tint, never colour alone.
    expect(
      find.text('Due soon · Close out Taco Night · Yesterday'),
      findsOneWidget,
    );
    // (2) Next-event card, dated in plain words, with packing-list
    // readiness — Home says "packing list", never "forecast".
    expect(find.text('Street Fair'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.textContaining('No packing list yet'), findsOneWidget);
    // (3) Quick actions: a 2-up grid of labeled tiles, never icon-only.
    expect(find.text('Add stock'), findsOneWidget);
    expect(find.text("Count what's there"), findsOneWidget);
    // (4) Data health: negative on-hand, signed, and with no unit — an item
    // is a name and a count now.
    expect(find.text('Tortillas is showing −2'), findsOneWidget);
    // (5) Recent movements + See all.
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.textContaining('Waste'), findsWidgets);
  });

  testWidgets('an empty calendar says so and offers the next move', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedItem(h, tester);

    await h.pumpApp(tester);

    // One item, no event: the one real figure leads, and nothing is
    // invented to keep it company.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('item on hand'), findsOneWidget);
    expect(find.textContaining('things to bring'), findsNothing);
    expect(find.textContaining('estimated cost'), findsNothing);
    expect(find.text('No event coming up'), findsOneWidget);
    expect(
      find.text(
        'Plan your next event and Loadout will work out what to '
        'bring.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the first-run guide pins the approved copy', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);

    // Proposal §4, word for word: the welcome must make ALL of her stuff —
    // cooked, bought, supplies, sold — feel welcome, not just "what you
    // sell".
    expect(
      find.text(
        'List what you bring — the food you make, the supplies you set out, '
        'the things you sell — and Loadout works out how much to take.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Cooked, bought, supplies, or things you sell. A name and a count '
        'is enough.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Set the date and roughly how many people. Loadout turns that into '
        'a packing list.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Afterwards, confirm what was used or sold. Every next list is '
        'built from what really happened.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the dashboard pins the approved copy', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    await h.pumpApp(tester);

    // Close-out nudge: one line, in the owner's order — the state, the
    // job, when it was. The paragraph explaining WHY a closeout matters
    // lives on the closeout screen this line opens, not on the dashboard.
    expect(
      find.text('Due soon · Close out Taco Night · Yesterday'),
      findsOneWidget,
    );
    expect(
      find.textContaining('the next packing list gets sharper'),
      findsNothing,
    );
    // Quick actions: "Add stock" (half of what arrives was never
    // purchased) and "Count what's there" — labeled tiles (spec §6).
    expect(find.text('Add stock'), findsOneWidget);
    expect(find.text("Count what's there"), findsOneWidget);
  });

  testWidgets('a fresh workspace never sees the tidy card', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    // Items exist, and the eight starter folders exist too (fresh
    // workspaces are born with them) — so there is nothing to tidy.
    await _seedItem(h, tester);

    await h.pumpApp(tester);

    expect(find.text('item on hand'), findsOneWidget);
    expect(find.text('Tidy your items into folders'), findsNothing);
  });

  testWidgets('closeout nudge and quick actions navigate', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    await h.pumpApp(tester);
    await tester.tap(find.text('Add stock'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MovementEntryScreen>(find.byType(MovementEntryScreen)).kind,
      'receive',
    );

    h.read(routerProvider).go('/home');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Close out Taco Night'));
    await tester.pumpAndSettle();
    expect(find.byType(CloseoutScreen), findsOneWidget);

    h.read(routerProvider).go('/home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tortillas is showing −2'), warnIfMissed: false);
    await tester.pumpAndSettle();
    final countEntry = tester.widget<MovementEntryScreen>(
      find.byType(MovementEntryScreen),
    );
    expect(countEntry.kind, 'count');
    expect(countEntry.itemId, isNotNull);
  });

  testWidgets('a serves-baseline forecast is not reported as no history', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    // "1 pizza serves 4" and no closeout anywhere: the engine has no
    // evidence, but the line still carries a number.
    final itemId = await _seedItem(
      h,
      tester,
      name: 'Pizza',
      servesPerUnit: Quantity.whole(4),
    );
    await tester.runAsync(() async {
      final events = h.read(eventServiceProvider);
      final created = await events.createEvent(
        EventDraft(
          name: 'Street Fair',
          scheduledDate: _date(DateTime.now().add(const Duration(days: 2))),
          plannedExposure: 100,
          plannedItemIds: [itemId],
        ),
      );
      final eventId = created.fold(
        (id) => id,
        (error) => throw StateError(error.code),
      );
      await h.read(forecastServiceProvider).generateSnapshot(eventId);
    });

    await h.pumpApp(tester);

    expect(
      find.text('Packing list ready · 1 amount is still a first guess'),
      findsOneWidget,
      reason: 'a baseline line has a number and must not read as no history',
    );
    expect(find.textContaining('knows nothing about'), findsNothing);
  });

  testWidgets('a line with nothing to go on is counted plainly', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    // No serves answer, no history: the line carries no number at all.
    final itemId = await _seedItem(h, tester, name: 'Mystery jam');
    await tester.runAsync(() async {
      final events = h.read(eventServiceProvider);
      final created = await events.createEvent(
        EventDraft(
          name: 'Street Fair',
          scheduledDate: _date(DateTime.now().add(const Duration(days: 2))),
          plannedExposure: 100,
          plannedItemIds: [itemId],
        ),
      );
      final eventId = created.fold(
        (id) => id,
        (error) => throw StateError(error.code),
      );
      await h.read(forecastServiceProvider).generateSnapshot(eventId);
    });

    await h.pumpApp(tester);

    expect(
      find.text('Packing list ready · 1 item Loadout knows nothing about yet'),
      findsOneWidget,
    );
  });

  testWidgets('renders at 200% text scale on a 320 dp viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    // Overflow at 200 % scale would throw and fail the test here.
    await h.pumpApp(tester);
    expect(find.textContaining('Close out Taco Night'), findsOneWidget);
  });

  testWidgets('a closeout left for days climbs to the red Overdue rung', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    await tester.runAsync(() async {
      final events = h.read(eventServiceProvider);
      final created = await events.createEvent(
        EventDraft(
          name: 'Spring Fete',
          scheduledDate: _date(
            DateTime.now().subtract(const Duration(days: 3)),
          ),
          plannedItemIds: [itemId],
        ),
      );
      final eventId = created.fold(
        (id) => id,
        (error) => throw StateError(error.code),
      );
      await events.activate(eventId);
    });

    await h.pumpApp(tester);

    // The ladder's third rung: red, with the word — never colour alone.
    expect(
      find.text('Overdue · Close out Spring Fete · 3 days ago'),
      findsOneWidget,
    );
    expect(find.textContaining('Due soon'), findsNothing);
    final card = tester.widget<Card>(
      find
          .ancestor(
            of: find.textContaining('Close out Spring Fete'),
            matching: find.byType(Card),
          )
          .first,
    );
    expect(card.color, StatusColors.derive(Brightness.light).short.container);
  });

  testWidgets('the first run also renders at 200% text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);

    await h.pumpApp(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
  testWidgets('home opens with the state of the kitchen: on hand, what the '
      'next event needs, what it will cost', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    // Two priced items the engine can put a number on ("1 serves 4" over
    // 100 people), so every figure below is measured, not invented.
    final pizza = await _seedItem(
      h,
      tester,
      name: 'Pizza',
      servesPerUnit: Quantity.whole(4),
      unitPrice: Money.fromCents(200),
    );
    final cups = await _seedItem(
      h,
      tester,
      name: 'Cups',
      servesPerUnit: Quantity.whole(1),
      unitPrice: Money.fromCents(10),
    );
    await _seedPlannedEvent(
      h,
      tester,
      name: 'Street Fair',
      itemIds: [pizza, cups],
    );

    await h.pumpApp(tester);

    // The hero: how much of a kitchen there is, in the one big figure the
    // screen is allowed.
    final heroSize = Numerals.hero(
      loadoutTheme(Brightness.light).textTheme,
    )!.fontSize;
    final heroes = tester
        .widgetList<Text>(find.byType(Text))
        .where((text) => text.style?.fontSize == heroSize)
        .toList();
    expect(heroes, hasLength(1), reason: 'one hero figure per screen');
    expect(heroes.single.data, '2');
    expect(find.text('items on hand'), findsOneWidget);

    // The next event's two figures, both read off its packing list.
    expect(find.text('things to bring to Street Fair'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    // The packing list's own loads at the items' own prices — 28 pizzas
    // at $2 and 110 cups at $0.10, buffer and all.
    expect(find.text(r'$67'), findsOneWidget);
    expect(find.text('estimated cost'), findsOneWidget);

    // And the numbers lead: the strip sits above the next-event card.
    expect(
      tester.getTopLeft(find.text('items on hand')).dy,
      lessThan(tester.getTopLeft(find.text('Street Fair')).dy),
    );
  });

  testWidgets('a stat with no data behind it is left out, never shown as a '
      'zero', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    // An event with a packing list, but nothing on it has a price.
    final pizza = await _seedItem(
      h,
      tester,
      name: 'Pizza',
      servesPerUnit: Quantity.whole(4),
    );
    await _seedPlannedEvent(h, tester, name: 'Street Fair', itemIds: [pizza]);

    await h.pumpApp(tester);

    expect(find.text('item on hand'), findsOneWidget);
    expect(find.text('thing to bring to Street Fair'), findsOneWidget);
    // No price anywhere → no cost stat at all, not "$0".
    expect(find.textContaining('estimated cost'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('a partly priced packing list says how many are not counted', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final pizza = await _seedItem(
      h,
      tester,
      name: 'Pizza',
      servesPerUnit: Quantity.whole(4),
      unitPrice: Money.fromCents(200),
    );
    final napkins = await _seedItem(
      h,
      tester,
      name: 'Napkins',
      servesPerUnit: Quantity.whole(1),
    );
    await _seedPlannedEvent(
      h,
      tester,
      name: 'Street Fair',
      itemIds: [pizza, napkins],
    );

    await h.pumpApp(tester);

    // The total is real, and what it leaves out is said out loud rather
    // than folded in as free.
    expect(find.text(r'$56'), findsOneWidget);
    expect(find.text('estimated cost · 1 not priced'), findsOneWidget);
  });

  testWidgets('an event with no packing list contributes no figures', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final pizza = await _seedItem(
      h,
      tester,
      name: 'Pizza',
      servesPerUnit: Quantity.whole(4),
      unitPrice: Money.fromCents(200),
    );
    await _seedPlannedEvent(
      h,
      tester,
      name: 'Street Fair',
      itemIds: [pizza],
      withSnapshot: false,
    );

    await h.pumpApp(tester);

    expect(find.text('item on hand'), findsOneWidget);
    expect(find.textContaining('to bring'), findsNothing);
    expect(find.textContaining('estimated cost'), findsNothing);
    // The event itself still shows, honestly, with no list yet.
    expect(find.textContaining('No packing list yet'), findsOneWidget);
  });

  testWidgets('the closeout nudge is ONE line in the pending tokens, and no '
      'longer the biggest thing on the screen', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedDashboard(h, tester);

    await h.pumpApp(tester);

    final nudge = find
        .ancestor(
          of: find.textContaining('Close out Taco Night'),
          matching: find.byType(Card),
        )
        .first;
    // One line: the whole tile is a single Text.
    expect(
      find.descendant(of: nudge, matching: find.byType(Text)),
      findsOneWidget,
    );
    // In the CLOSED state set's pending pair — amber means "not counted
    // yet" here, and nothing decorative is allowed to borrow it.
    final pending = StatusColors.derive(Brightness.light).pending;
    expect(tester.widget<Card>(nudge).color, pending.container);
    expect(
      tester
          .widget<Text>(
            find.text('Due soon · Close out Taco Night · Yesterday'),
          )
          .style
          ?.color,
      pending.foreground,
    );
    // Still the tappable thing it always was.
    await tester.tap(find.textContaining('Close out Taco Night'));
    await tester.pumpAndSettle();
    expect(find.byType(CloseoutScreen), findsOneWidget);
  });

  testWidgets('recent activity reaches the bottom of the viewport — the last '
      'row is never a clipped strip', (tester) async {
    // Regression (design review): the dashboard's bottom padding sat
    // OUTSIDE the scrollable, so the list's viewport stopped 32 dp short of
    // the screen and the last activity row was cut by it with dead paper
    // underneath — which reads as a clipped row, not as more to scroll.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final itemId = await _seedItem(h, tester);
    await tester.runAsync(() async {
      final inventory = h.read(inventoryServiceProvider);
      for (var i = 0; i < 5; i++) {
        await inventory.record(
          MovementFormDraft(
            itemId: itemId,
            kind: MovementKind.receive,
            quantity: Quantity.whole(i + 1),
          ),
        );
      }
    });

    await h.pumpApp(tester);

    // The scrollable owns every pixel down to the bottom of the body.
    final list = find.descendant(
      of: find.byType(HomeScreen),
      matching: find.byType(ListView),
    );
    expect(
      tester.getRect(list).bottom,
      tester.getRect(find.byType(HomeScreen)).bottom,
    );

    // And scrolled to the end, the last activity row is whole.
    await tester.drag(list, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final rows = find.byType(MovementRow);
    expect(rows, findsWidgets);
    final last = tester.getRect(rows.last);
    expect(last.bottom, lessThanOrEqualTo(tester.getRect(list).bottom));
  });
  testWidgets('the full stat strip survives 200% text scale on a 320 dp '
      'viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    final pizza = await _seedItem(
      h,
      tester,
      name: 'Pizza',
      servesPerUnit: Quantity.whole(4),
      unitPrice: Money.fromCents(200),
    );
    await _seedPlannedEvent(
      h,
      tester,
      name: 'Midsummer Street Fair',
      itemIds: [pizza],
    );

    // Three figures, a long event name and doubled type on a narrow phone:
    // an overflow would throw and fail the test here.
    await h.pumpApp(tester);
    expect(find.text('item on hand'), findsOneWidget);
    expect(
      find.text('thing to bring to Midsummer Street Fair'),
      findsOneWidget,
    );
    expect(find.text('estimated cost'), findsOneWidget);

    // Dark mode paints the same strip from the other ramp.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text('item on hand'), findsOneWidget);
  });
}
