/// Smoke test: every §9 route builds and renders its screen.
///
/// Routes carrying an id are exercised against REAL seeded records, so this
/// also proves the router's parameter plumbing reaches each screen. Detail
/// routes are additionally probed with an unknown id: a screen may show a
/// not-found state, but it must never leave an unhandled exception behind.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/core/units.dart';
import 'package:loadout/features/backup/presentation/backup_screen.dart';
import 'package:loadout/features/backup/presentation/restore_screen.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/item_detail_screen.dart';
import 'package:loadout/features/catalog/presentation/item_edit_screen.dart';
import 'package:loadout/features/catalog/presentation/item_list_screen.dart';
import 'package:loadout/features/closeout/presentation/closeout_screen.dart';
import 'package:loadout/features/events/presentation/event_detail_screen.dart';
import 'package:loadout/features/events/presentation/event_edit_screen.dart';
import 'package:loadout/features/events/presentation/event_list_screen.dart';
import 'package:loadout/features/forecasting/presentation/forecast_line_detail_screen.dart';
import 'package:loadout/features/forecasting/presentation/forecast_review_screen.dart';
import 'package:loadout/features/home/presentation/home_screen.dart';
import 'package:loadout/features/inventory/presentation/activity_screen.dart';
import 'package:loadout/features/inventory/presentation/correction_screen.dart';
import 'package:loadout/features/inventory/presentation/movement_detail_screen.dart';
import 'package:loadout/features/inventory/presentation/movement_entry_screen.dart';
import 'package:loadout/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:loadout/features/recipes/presentation/recipe_edit_screen.dart';
import 'package:loadout/features/recipes/presentation/recipe_list_screen.dart';
import 'package:loadout/features/settings/presentation/about_screen.dart';
import 'package:loadout/features/settings/presentation/diagnostics_screen.dart';
import 'package:loadout/features/settings/presentation/privacy_screen.dart';
import 'package:loadout/features/settings/presentation/settings_screen.dart';
import 'package:loadout/features/settings/presentation/workspace_reset_screen.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/onboarding/presentation/create_workspace_screen.dart';
import 'package:loadout/features/onboarding/presentation/recovery_screen.dart';
import 'package:loadout/features/onboarding/presentation/welcome_screen.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../support/app_harness.dart';

/// Static routes reachable with an open workspace → the screen each must show.
final Map<String, Type> staticRoutes = {
  '/home': HomeScreen,
  '/events': EventListScreen,
  '/items': ItemListScreen,
  '/recipes': RecipeListScreen,
  '/settings': SettingsScreen,
  '/events/new': EventEditScreen,
  '/items/new': ItemEditScreen,
  '/movements/new': MovementEntryScreen,
  '/activity': ActivityScreen,
  '/recipes/new': RecipeEditScreen,
  '/settings/backup': BackupScreen,
  '/settings/restore': RestoreScreen,
  '/settings/privacy': PrivacyScreen,
  '/settings/diagnostics': DiagnosticsScreen,
  '/settings/reset': WorkspaceResetScreen,
  '/settings/about': AboutScreen,
};

void main() {
  testWidgets('every static route builds under an open workspace', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    for (final entry in staticRoutes.entries) {
      await h.go(tester, entry.key);
      expect(
        find.byType(entry.value),
        findsOneWidget,
        reason: 'route ${entry.key} should show ${entry.value}',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'route ${entry.key} threw while building',
      );
    }
  });

  testWidgets('every id-carrying route builds against real records', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);

    final ids = (await tester.runAsync(() => _seedWorkspace(h)))!;
    await h.pumpApp(tester);

    final routes = <String, Type>{
      '/items/${ids.itemId}': ItemDetailScreen,
      '/items/${ids.itemId}/edit': ItemEditScreen,
      '/events/${ids.eventId}': EventDetailScreen,
      '/events/${ids.eventId}/edit': EventEditScreen,
      '/events/${ids.eventId}/forecast': ForecastReviewScreen,
      '/events/${ids.eventId}/forecast/${ids.itemId}': ForecastLineDetailScreen,
      '/events/${ids.eventId}/closeout': CloseoutScreen,
      '/movements/${ids.movementId}': MovementDetailScreen,
      '/movements/${ids.movementId}/correct': CorrectionScreen,
      '/movements/new?kind=receive&itemId=${ids.itemId}': MovementEntryScreen,
      '/recipes/${ids.recipeId}': RecipeDetailScreen,
      '/recipes/${ids.recipeId}/revise': RecipeEditScreen,
    };

    for (final entry in routes.entries) {
      await h.go(tester, entry.key);
      expect(
        find.byType(entry.value),
        findsOneWidget,
        reason: 'route ${entry.key} should show ${entry.value}',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'route ${entry.key} threw while building',
      );
    }
  });

  testWidgets('detail routes survive an unknown id without crashing', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    const missing = [
      '/items/nope',
      '/events/nope',
      '/movements/nope',
      '/recipes/nope',
    ];
    for (final route in missing) {
      await h.go(tester, route);
      expect(
        tester.takeException(),
        isNull,
        reason: '$route left an unhandled exception for an unknown id',
      );
      // Back to safety so the next probe starts from a good state.
      await h.go(tester, '/home');
    }
  });

  testWidgets('onboarding routes build on a fresh install', (tester) async {
    final h = (await tester.runAsync(AppHarness.start))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    expect(find.byType(WelcomeScreen), findsOneWidget);
    await h.go(tester, '/welcome/create');
    expect(find.byType(CreateWorkspaceScreen), findsOneWidget);
  });

  testWidgets('recovery route builds in a recovery state', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.recoveryKeyMissing),
    ))!;
    addTearDown(h.dispose);
    await h.pumpApp(tester);

    expect(find.byType(RecoveryScreen), findsOneWidget);
  });
}

typedef _SeededIds = ({
  String itemId,
  String eventId,
  String movementId,
  String recipeId,
});

T _ok<T>(Result<T> result) => result.fold(
  (value) => value,
  (error) => throw StateError('seed failed: $error'),
);

/// Seeds one of everything the id-carrying routes need, through the real
/// application services.
Future<_SeededIds> _seedWorkspace(AppHarness h) async {
  final itemId = _ok(
    await h
        .read(catalogServiceProvider)
        .createItem(
          ItemDraft(
            name: 'Tortillas',
            unit: ItemUnit.each,
            packSize: Quantity.whole(12),
            category: 'Dry goods',
          ),
        ),
  );

  // A second item so the recipe's ingredient differs from its output.
  final flourId = _ok(
    await h
        .read(catalogServiceProvider)
        .createItem(
          ItemDraft(
            name: 'Flour',
            unit: ItemUnit.g,
            packSize: Quantity.whole(1000),
          ),
        ),
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
            name: 'Tortilla batch',
            outputItemId: itemId,
            yieldQuantity: Quantity.whole(24),
            yieldLabel: '24 tortillas',
            lines: [
              RecipeFormLine(
                itemId: flourId,
                quantityPerBatch: Quantity.whole(900),
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
