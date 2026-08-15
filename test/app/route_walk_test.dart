/// Integration walk over EVERY §9 route at a real phone viewport (393×852,
/// the iPhone 15 logical size), twice: once against a brand-new empty
/// workspace and once against seeded records.
///
/// Three agents changed the domain, the forms and the theme in parallel, so
/// this is the seam test: each route must
///   1. build the screen the router promises,
///   2. lay out with no overflow and no unhandled exception at phone width,
///      both at the top of the screen and after scrolling to the bottom,
///   3. offer a way out — the tab bar or a back affordance — so no route is
///      a dead end.
///
/// An empty workspace is the interesting half: it is the state the owner
/// actually met on her phone, where "the dropdowns offer zero options and
/// explain nothing".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/router.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/unit_ratio.dart';
import 'package:loadout/features/backup/presentation/backup_screen.dart';
import 'package:loadout/features/backup/presentation/restore_screen.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/folder_management_screen.dart';
import 'package:loadout/features/catalog/presentation/item_detail_screen.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
import 'package:loadout/features/catalog/presentation/item_list_screen.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/events/presentation/event_detail_screen.dart';
import 'package:loadout/features/events/presentation/event_edit_screen.dart';
import 'package:loadout/features/events/presentation/event_list_screen.dart';
import 'package:loadout/features/forecasting/presentation/forecast_line_detail_screen.dart';
import 'package:loadout/features/forecasting/presentation/forecast_review_screen.dart';
import 'package:loadout/features/home/presentation/home_screen.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/inventory/presentation/activity_screen.dart';
import 'package:loadout/features/inventory/presentation/correction_screen.dart';
import 'package:loadout/features/inventory/presentation/movement_detail_screen.dart';
import 'package:loadout/features/inventory/presentation/movement_entry_screen.dart';
import 'package:loadout/features/onboarding/presentation/create_workspace_screen.dart';
import 'package:loadout/features/onboarding/presentation/recovery_screen.dart';
import 'package:loadout/features/onboarding/presentation/welcome_screen.dart';
import 'package:loadout/features/production/presentation/production_planning_screen.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';
import 'package:loadout/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:loadout/features/recipes/presentation/recipe_edit_screen.dart';
import 'package:loadout/features/recipes/presentation/recipe_list_screen.dart';
import 'package:loadout/features/settings/presentation/about_screen.dart';
import 'package:loadout/features/settings/presentation/diagnostics_screen.dart';
import 'package:loadout/features/settings/presentation/privacy_screen.dart';
import 'package:loadout/features/settings/presentation/settings_screen.dart';
import 'package:loadout/features/settings/presentation/workspace_reset_screen.dart';

import '../support/app_harness.dart';

/// iPhone 15 logical size — the phone the owner used.
const Size phoneViewport = Size(393, 852);

/// Routes reachable with an open workspace and NO records at all, entered
/// with `go` the way the router's own redirect and the tab bar enter them.
const Map<String, Type> recordlessGoRoutes = {
  '/home': HomeScreen,
  '/events': EventListScreen,
  '/items': ItemListScreen,
  '/recipes': RecipeListScreen,
  '/settings': SettingsScreen,
  '/events/new': EventEditScreen,
  '/items/new': ItemEditScreen,
  '/recipes/new': RecipeEditScreen,
  '/settings/backup': BackupScreen,
  '/settings/restore': RestoreScreen,
  '/settings/privacy': PrivacyScreen,
  '/settings/diagnostics': DiagnosticsScreen,
  '/settings/reset': WorkspaceResetScreen,
  '/settings/about': AboutScreen,
};

/// Root-level routes with no parent path. The app only ever `push`es these
/// (grep: every call site is `context.push`), so pushing from `/home` is
/// what the owner actually does — and the only way a back affordance is
/// meaningful. `/activity` is the exception the app also `go`es to, and it
/// is covered separately below.
const Map<String, Type> recordlessPushRoutes = {
  '/movements/new': MovementEntryScreen,
  '/activity': ActivityScreen,
  '/production': ProductionPlanningScreen,
};

void main() {
  testWidgets('every route survives an EMPTY workspace at 393×852', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    for (final entry in recordlessGoRoutes.entries) {
      await _visit(tester, h, entry.key, entry.value);
    }
    for (final entry in recordlessPushRoutes.entries) {
      await _visit(tester, h, entry.key, entry.value, push: true);
    }
  });

  testWidgets('/activity is not a dead end when it is reached with go', (
    tester,
  ) async {
    // CorrectionScreen falls back to `context.go('/activity')` when it has
    // nothing to pop. That clears the stack, so there is no back button and
    // no tab bar: without an explicit way out the owner is stranded.
    _usePhoneViewport(tester);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    await h.go(tester, '/activity');
    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(_hasWayOut(tester), isTrue);

    await tester.tap(find.byTooltip('Home'));
    await _settle(tester);
    // Leaving /activity auto-disposes its providers; drift closes the query
    // streams behind them on a zero-duration timer (see AppHarness).
    await h.flushTimers(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('every route survives a seeded workspace at 393×852', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    final ids = (await tester.runAsync(() => _seed(h)))!;
    await h.pumpApp(tester);

    final goRoutes = <String, Type>{
      ...recordlessGoRoutes,
      '/items/${ids.itemId}': ItemDetailScreen,
      '/items/${ids.itemId}/edit': ItemEditScreen,
      '/events/${ids.eventId}': EventDetailScreen,
      '/events/${ids.eventId}/edit': EventEditScreen,
      '/events/${ids.eventId}/forecast': ForecastReviewScreen,
      '/events/${ids.eventId}/forecast/${ids.itemId}': ForecastLineDetailScreen,
      '/events/${ids.eventId}/closeout': CloseoutScreen,
      '/recipes/${ids.recipeId}': RecipeDetailScreen,
      '/recipes/${ids.recipeId}/revise': RecipeEditScreen,
    };
    final pushRoutes = <String, Type>{
      ...recordlessPushRoutes,
      '/movements/${ids.movementId}': MovementDetailScreen,
      '/movements/${ids.movementId}/correct': CorrectionScreen,
      '/movements/new?kind=count&itemId=${ids.itemId}': MovementEntryScreen,
    };

    for (final entry in goRoutes.entries) {
      await _visit(tester, h, entry.key, entry.value);
    }
    for (final entry in pushRoutes.entries) {
      await _visit(tester, h, entry.key, entry.value, push: true);
    }
  });

  testWidgets(
    'every route survives a folder-rich workspace (60+ items across the '
    '8 starter folders, sales table and per-event included) at 393×852',
    (tester) async {
      _usePhoneViewport(tester);
      final h = (await tester.runAsync(
        () => AppHarness.start(state: AppHarnessState.workspace),
      ))!;
      addTearDown(h.dispose);
      final ids = (await tester.runAsync(() => _seedDense(h)))!;
      await h.pumpApp(tester);

      final goRoutes = <String, Type>{
        ...recordlessGoRoutes,
        // A SALES-TABLE item carries the catalog detail/edit legs: the same
        // screens must read right for merch, not just food.
        '/items/${ids.salesItemId}': ItemDetailScreen,
        '/items/${ids.salesItemId}/edit': ItemEditScreen,
        '/events/${ids.eventId}': EventDetailScreen,
        '/events/${ids.eventId}/edit': EventEditScreen,
        '/events/${ids.eventId}/forecast': ForecastReviewScreen,
        // Both bases through the line-detail screen: a per-person line and
        // a per-event line (the soap) from the same persisted snapshot.
        '/events/${ids.eventId}/forecast/${ids.perPersonItemId}':
            ForecastLineDetailScreen,
        '/events/${ids.eventId}/forecast/${ids.perEventItemId}':
            ForecastLineDetailScreen,
        '/events/${ids.eventId}/closeout': CloseoutScreen,
        '/recipes/${ids.recipeId}': RecipeDetailScreen,
        '/recipes/${ids.recipeId}/revise': RecipeEditScreen,
      };
      final pushRoutes = <String, Type>{
        ...recordlessPushRoutes,
        '/movements/${ids.movementId}': MovementDetailScreen,
        '/movements/${ids.movementId}/correct': CorrectionScreen,
      };

      for (final entry in goRoutes.entries) {
        await _visit(tester, h, entry.key, entry.value);
      }
      for (final entry in pushRoutes.entries) {
        await _visit(tester, h, entry.key, entry.value, push: true);
      }

      // Folder management is Navigator-pushed from the item list's menu —
      // not a GoRoute — so walk it the way the owner reaches it.
      await h.go(tester, '/items');
      await tester.tap(find.byType(PopupMenuButton<String>));
      await _settle(tester);
      await tester.tap(find.text('Manage folders'));
      await _settle(tester);
      expect(find.byType(FolderManagementScreen), findsOneWidget);
      _expectNoOverflow(tester, '/items > Manage folders');
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.drag(scrollable.first, const Offset(0, -600));
        await _settle(tester);
        _expectNoOverflow(tester, '/items > Manage folders (scrolled)');
      }
      expect(
        _hasWayOut(tester),
        isTrue,
        reason: 'Manage folders must not be a dead end',
      );
      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      await h.flushTimers(tester);
      expect(find.byType(ItemListScreen), findsOneWidget);
    },
  );

  testWidgets('first-run routes survive at 393×852', (tester) async {
    _usePhoneViewport(tester);
    final h = (await tester.runAsync(AppHarness.start))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    // /welcome is the app's front door: it has no tab bar and nothing to go
    // back to, so it is exempt from the way-out rule and instead must offer
    // a way FORWARD.
    expect(find.byType(WelcomeScreen), findsOneWidget);
    _expectNoOverflow(tester, '/welcome');
    expect(
      _hasEnabledButton(tester),
      isTrue,
      reason: '/welcome must offer a way to start',
    );

    await h.go(tester, '/welcome/create');
    expect(find.byType(CreateWorkspaceScreen), findsOneWidget);
    _expectNoOverflow(tester, '/welcome/create');
    expect(
      _hasEnabledButton(tester),
      isTrue,
      reason: '/welcome/create must offer a way to finish',
    );
  });

  testWidgets('recovery survives at 393×852', (tester) async {
    _usePhoneViewport(tester);
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.recoveryKeyMissing),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    expect(find.byType(RecoveryScreen), findsOneWidget);
    _expectNoOverflow(tester, '/recovery');
    expect(
      _hasEnabledButton(tester),
      isTrue,
      reason: '/recovery must offer a way to recover',
    );
  });
}

// --------------------------------------------------------------- helpers

/// Bounded settle, like `AppHarness.go`: an unresolved spinner would
/// otherwise burn `pumpAndSettle`'s ten-minute default before the suite
/// reports anything at all.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = phoneViewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Opens [route], then asserts the promised screen, clean layout at the top
/// AND at the bottom of any scroll view, and a way out.
Future<void> _visit(
  WidgetTester tester,
  AppHarness h,
  String route,
  Type screen, {
  bool push = false,
}) async {
  if (push) {
    await h.go(tester, '/home');
    h.read(routerProvider).push(route);
    // Bounded like AppHarness.go: an unresolved spinner would otherwise
    // burn pumpAndSettle's ten-minute default before anything is reported.
    await _settle(tester);
  } else {
    await h.go(tester, route);
  }
  expect(
    find.byType(screen),
    findsOneWidget,
    reason: 'route $route should show $screen',
  );
  _expectNoOverflow(tester, route);

  // Content below the fold is not laid out until it scrolls in, so an
  // overflow further down would otherwise go unseen.
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isNotEmpty) {
    await tester.drag(scrollable.first, const Offset(0, -600));
    await _settle(tester);
    _expectNoOverflow(tester, '$route (scrolled)');
  }

  expect(
    _hasWayOut(tester),
    isTrue,
    reason:
        'route $route is a dead end: no tab bar and no back affordance, so '
        'the owner would be stuck here',
  );
}

/// A RenderFlex/RenderBox overflow is reported as a FlutterError, which the
/// test binding surfaces through `takeException`.
void _expectNoOverflow(WidgetTester tester, String route) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'route $route overflowed or threw at 393×852',
  );
}

bool _hasWayOut(WidgetTester tester) =>
    find.byType(NavigationBar).evaluate().isNotEmpty ||
    find.byType(BackButton).evaluate().isNotEmpty ||
    find.byType(CloseButton).evaluate().isNotEmpty ||
    find.byTooltip('Home').evaluate().isNotEmpty;

/// `find.byType` matches the EXACT runtime type, so it never finds a
/// `FilledButton` through `ButtonStyleButton`. Predicate matching does.
bool _hasEnabledButton(WidgetTester tester) => find
    .byWidgetPredicate(
      (widget) => widget is ButtonStyleButton && widget.onPressed != null,
    )
    .evaluate()
    .isNotEmpty;

typedef _SeededIds = ({
  String itemId,
  String eventId,
  String movementId,
  String recipeId,
});

typedef _DenseIds = ({
  String salesItemId,
  String perPersonItemId,
  String perEventItemId,
  String eventId,
  String movementId,
  String recipeId,
});

T _ok<T>(Result<T> result) => result.fold(
  (value) => value,
  (error) => throw StateError('seed failed: ${error.code}: ${error.message}'),
);

/// Seeds one of everything, shaped the way the app shapes records NOW: an
/// item is a name, a count, and optionally how many people one serves. No
/// unit, no pack size.
Future<_SeededIds> _seed(AppHarness h) async {
  final catalog = h.read(catalogServiceProvider);
  final itemId = _ok(
    await catalog.createItem(
      ItemDraft(
        name: 'Pizzas',
        servesPerUnit: Quantity.whole(4),
        category: 'Hot food',
      ),
      openingCount: Quantity.whole(20),
    ),
  );
  // A second item so the recipe's ingredient differs from its output.
  final doughId = _ok(
    await catalog.createItem(const ItemDraft(name: 'Dough balls')),
  );

  final eventId = _ok(
    await h
        .read(eventServiceProvider)
        .createEvent(
          EventDraft(
            name: 'Saturday market',
            scheduledDate: '2026-09-05',
            plannedExposure: 120,
            plannedItemIds: [itemId],
          ),
        ),
  );

  final receipt = _ok(
    await h
        .read(inventoryServiceProvider)
        .record(
          MovementFormDraft(
            itemId: itemId,
            kind: MovementKind.receive,
            quantity: Quantity.whole(48),
          ),
        ),
  );

  final recipeId = _ok(
    await h
        .read(recipeServiceProvider)
        .createRecipe(
          RecipeFormDraft(
            name: 'Pizza batch',
            outputItemId: itemId,
            yieldQuantity: Quantity.whole(24),
            yieldLabel: '24 pizzas',
            lines: [
              RecipeFormLine(
                itemId: doughId,
                quantityPerBatch: Quantity.whole(24),
              ),
            ],
          ),
        ),
  );

  return (
    itemId: itemId,
    eventId: eventId,
    movementId: receipt.createdRecordIds.first,
    recipeId: recipeId,
  );
}

/// The proposal's stress shape: 60+ items spread across the eight starter
/// folders a fresh workspace is born with — the sales table and the
/// per-event "Cleaning & setup" included — plus two Unfiled stragglers,
/// one event planning ALL of them at 200 people, and a persisted forecast
/// snapshot so the review and line-detail routes render real lines on
/// both bases.
Future<_DenseIds> _seedDense(AppHarness h) async {
  final catalog = h.read(catalogServiceProvider);
  final folders = await catalog.watchFolders().first;
  expect(
    folders,
    hasLength(8),
    reason: 'a fresh workspace starts with the eight starter folders',
  );

  final allItemIds = <String>[];
  Future<String> item(ItemDraft draft, {Quantity? opening}) async {
    final id = _ok(
      await catalog.createItem(draft, openingCount: opening ?? Quantity.zero),
    );
    allItemIds.add(id);
    return id;
  }

  String folderId(String name) =>
      folders.firstWhere((f) => f.name == name).id.value;

  // The named characters from the proposal.
  final perPersonItemId = await item(
    ItemDraft(
      name: 'Vegetable soup',
      servesPerUnit: Quantity.whole(4),
      folderId: folderId('Cooked on site'),
    ),
    opening: Quantity.whole(10),
  );
  final salesItemId = await item(
    ItemDraft(
      name: 'CDs',
      perPersonRatio: UnitRatio(1, 4),
      folderId: folderId('Sales table'),
    ),
    opening: Quantity.whole(40),
  );
  final perEventItemId = await item(
    ItemDraft(
      name: 'Soap',
      perEventBaseline: Quantity.whole(2),
      folderId: folderId('Cleaning & setup'),
    ),
    opening: Quantity.whole(2),
  );
  // A per-item OVERRIDE against a per-person folder's default.
  await item(
    ItemDraft(
      name: 'Water urn',
      demandBasis: DemandBasis.perEvent,
      perEventBaseline: Quantity.whole(1),
      folderId: folderId('Drinks'),
    ),
    opening: Quantity.whole(1),
  );
  final produceId = await item(
    ItemDraft(name: 'Carrots', folderId: folderId('Fresh produce')),
    opening: Quantity.whole(30),
  );

  // Fill every folder to eight items so the list, picker and closeout all
  // section past sixty items at phone width.
  final perFolderSoFar = <String, int>{
    'Cooked on site': 1,
    'Sales table': 1,
    'Cleaning & setup': 1,
    'Drinks': 1,
    'Fresh produce': 1,
  };
  for (final folder in folders) {
    final have = perFolderSoFar[folder.name] ?? 0;
    for (var i = have + 1; i <= 8; i++) {
      await item(
        ItemDraft(name: '${folder.name} item $i', folderId: folder.id.value),
        opening: Quantity.whole(i),
      );
    }
  }
  // Unfiled stragglers: the migrated-workspace shape inside a foldered one.
  await item(const ItemDraft(name: 'Mystery box'));
  await item(const ItemDraft(name: 'Raffle tickets'));
  expect(allItemIds.length, greaterThanOrEqualTo(60));

  final eventId = _ok(
    await h
        .read(eventServiceProvider)
        .createEvent(
          EventDraft(
            name: 'Autumn fair',
            scheduledDate: '2026-10-03',
            plannedExposure: 200,
            plannedItemIds: allItemIds,
          ),
        ),
  );

  final receipt = _ok(
    await h
        .read(inventoryServiceProvider)
        .record(
          MovementFormDraft(
            itemId: perPersonItemId,
            kind: MovementKind.receive,
            quantity: Quantity.whole(48),
          ),
        ),
  );

  final recipeId = _ok(
    await h
        .read(recipeServiceProvider)
        .createRecipe(
          RecipeFormDraft(
            name: 'Soup batch',
            outputItemId: perPersonItemId,
            yieldQuantity: Quantity.whole(10),
            yieldLabel: '10 portions',
            lines: [
              RecipeFormLine(
                itemId: produceId,
                quantityPerBatch: Quantity.whole(6),
              ),
            ],
          ),
        ),
  );

  // Persist the snapshot the forecast routes will render.
  _ok(await h.read(forecastServiceProvider).generateSnapshot(eventId));

  return (
    salesItemId: salesItemId,
    perPersonItemId: perPersonItemId,
    perEventItemId: perEventItemId,
    eventId: eventId,
    movementId: receipt.createdRecordIds.first,
    recipeId: recipeId,
  );
}
