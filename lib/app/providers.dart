/// The §9.1 provider graph (Riverpod 2.x).
///
/// Composition roots override the four "wired at bootstrap" providers
/// ([startupServiceProvider], [keyManagerProvider], [scratchSpaceProvider],
/// [diagProvider]) plus [startupStateProvider] and [initialLocationProvider]
/// — see `lib/app/bootstrap.dart` (production) and
/// `test/support/app_harness.dart` (tests). Everything else derives from
/// those.
///
/// Database lifecycle: [StartupService] owns the live [AppDatabase] handle
/// (it IS the [DatabaseHost]). [appDatabaseProvider] re-reads
/// `DatabaseHost.database` whenever [startupStateProvider] or
/// [databaseGenerationProvider] changes, so every service and projection
/// below rebuilds after the restore flow closes/reopens the DB (§8.2) or
/// after `/welcome/create` / recovery start-fresh opens a fresh one. Flows
/// that reopen the database MUST bump [databaseGenerationProvider] (restore)
/// or set [startupStateProvider] (workspace creation / start-fresh).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics/diag.dart';
// The drift row class EventCloseout is hidden: the domain read model of the
// same name (features/closeout/domain/closeout.dart) is the public one.
import '../data/db/app_database.dart' hide EventCloseout;
import '../features/approval/domain/approval_service.dart';
import '../features/approval/infrastructure/drift_command_applier.dart';
import '../features/backup/application/backup_facade.dart';
import '../features/backup/domain/backup_service.dart';
import '../features/catalog/application/catalog_service.dart';
import '../features/closeout/application/closeout_service.dart';
import '../features/closeout/domain/closeout.dart';
import '../features/events/application/event_service.dart';
import '../features/forecasting/application/event_cost_service.dart';
import '../features/forecasting/application/forecast_service.dart';
import '../features/forecasting/domain/event_cost.dart';
import '../features/forecasting/domain/forecast_engine.dart';
import '../features/forecasting/domain/snapshot.dart';
import '../features/inventory/application/inventory_service.dart';
import '../features/inventory/domain/ledger_math.dart';
import '../features/inventory/infrastructure/drift_inventory_ledger.dart';
import '../features/catalog/application/barcode_scan_service.dart';
import '../features/recipes/application/recipe_ocr_service.dart';
import '../features/recipes/application/recipe_service.dart';
import '../features/settings/application/settings_service.dart';
import '../features/settings/domain/app_theme_choice.dart';
import '../infrastructure/backup/backup_service_impl.dart';
import '../infrastructure/files/loadout_paths.dart';
import '../infrastructure/files/scratch_space.dart';
import '../infrastructure/security/key_manager.dart';
import '../infrastructure/startup/startup_service.dart';

// --------------------------------------------------- wired at bootstrap

/// The resolved [StartupService] (also the [DatabaseHost]). Overridden by
/// the composition root; unusable before then by design.
final startupServiceProvider = Provider<StartupService>(
  (_) => throw UnimplementedError('overridden at bootstrap'),
);

final keyManagerProvider = Provider<KeyManager>(
  (_) => throw UnimplementedError('overridden at bootstrap'),
);

final scratchSpaceProvider = Provider<ScratchSpace>(
  (_) => throw UnimplementedError('overridden at bootstrap'),
);

/// Content-free diagnostics sink. In production this is the [RingFileDiag]
/// whose `bufferedLines` / `logFile` feed `/settings/diagnostics`.
final diagProvider = Provider<Diag>((_) => const NoopDiag());

/// Canonical on-disk layout (db/, scratch/, diag/).
final loadoutPathsProvider = Provider<LoadoutPaths>(
  (ref) => ref.watch(startupServiceProvider).paths,
);

// ----------------------------------------------------- startup & routing

/// The §7.3 state resolved by `StartupService.bootstrap()` before `runApp`.
/// Mutated (to [StartupWorkspaceOpen]) by the create-workspace and
/// recovery start-fresh flows; drives the router redirect.
final startupStateProvider = StateProvider<StartupState>(
  (_) => throw UnimplementedError('overridden at bootstrap'),
);

/// Where the router starts. Computed at bootstrap from the startup state
/// plus the workspace_created flag, so the first frame is already correct.
final initialLocationProvider = Provider<String>((_) => '/welcome');

/// The stored appearance preference as bootstrap read it, before `runApp`.
/// [themeChoiceProvider] paints with this until the watch stream produces
/// its first value, so a cold start never flashes the other brightness.
/// Stays `system` in the states with no open database (fresh, recovery).
final startupThemeChoiceProvider = Provider<AppThemeChoice>(
  (_) => AppThemeChoice.system,
);

/// Bumped by the restore flow after `DatabaseHost` closes and reopens the
/// authoritative DB (§8.2) so [appDatabaseProvider] rebuilds.
final databaseGenerationProvider = StateProvider<int>((_) => 0);

final databaseHostProvider = Provider<DatabaseHost>(
  (ref) => ref.watch(startupServiceProvider),
);

/// The live database. Throws [StateError] while no database is open
/// (fresh install before `/welcome/create`, recovery) — screens reachable
/// in those states must not read it.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  ref.watch(startupStateProvider);
  ref.watch(databaseGenerationProvider);
  return ref.watch(databaseHostProvider).database;
});

// -------------------------------------------------------- infrastructure

final forecastEngineProvider = Provider<ForecastEngine>(
  (_) => const DeterministicForecastEngine(),
);

/// The ONE shared applier (idempotency cache + recordedAt monotonic state
/// live here). Every mutation goes through this instance; it is rebuilt
/// only when the database handle itself changes.
final approvalServiceProvider = Provider<ApprovalService>(
  (ref) => DriftCommandApplier(
    ref.watch(appDatabaseProvider),
    diag: ref.watch(diagProvider),
  ),
);

// -------------------------------------------------- application services

/// Concrete type on purpose: [DriftForecastService] requires the concrete
/// [DriftSettingsService] (typed settings accessors).
final settingsServiceProvider = Provider<DriftSettingsService>(
  (ref) => DriftSettingsService(ref.watch(appDatabaseProvider)),
);

final catalogServiceProvider = Provider<CatalogService>(
  (ref) => DriftCatalogService(
    ref.watch(appDatabaseProvider),
    ref.watch(approvalServiceProvider),
  ),
);

final eventServiceProvider = Provider<EventService>(
  (ref) => DriftEventService(
    ref.watch(appDatabaseProvider),
    ref.watch(approvalServiceProvider),
  ),
);

final inventoryLedgerProvider = Provider<DriftInventoryLedger>(
  (ref) => DriftInventoryLedger(ref.watch(appDatabaseProvider)),
);

final inventoryServiceProvider = Provider<InventoryService>(
  (ref) => DriftInventoryService(
    ref.watch(appDatabaseProvider),
    ref.watch(approvalServiceProvider),
    ledger: ref.watch(inventoryLedgerProvider),
  ),
);

final forecastServiceProvider = Provider<ForecastService>(
  (ref) => DriftForecastService(
    ref.watch(appDatabaseProvider),
    ref.watch(approvalServiceProvider),
    ref.watch(settingsServiceProvider),
    engine: ref.watch(forecastEngineProvider),
  ),
);

/// Money over quantities: the frozen engine's numbers priced at today's
/// prices, and confirmed closeouts priced at the cents they recorded.
final eventCostServiceProvider = Provider<EventCostService>(
  (ref) => DriftEventCostService(
    ref.watch(appDatabaseProvider),
    ref.watch(forecastServiceProvider),
    ref.watch(settingsServiceProvider),
  ),
);

final closeoutServiceProvider = Provider<CloseoutService>(
  (ref) => DriftCloseoutService(
    ref.watch(appDatabaseProvider),
    ref.watch(approvalServiceProvider),
    forecastService: ref.watch(forecastServiceProvider),
  ),
);

final recipeServiceProvider = Provider<RecipeService>(
  (ref) => DriftRecipeService(
    ref.watch(appDatabaseProvider),
    ref.watch(approvalServiceProvider),
  ),
);

/// Overridden with a fake in widget tests; the real channel needs a device.
final recipeOcrServiceProvider = Provider<RecipeOcrService>(
  (ref) => const MethodChannelRecipeOcrService(),
);

/// Overridden with a fake in widget tests; the real channel needs a device.
final barcodeScanServiceProvider = Provider<BarcodeScanService>(
  (ref) => const MethodChannelBarcodeScanService(),
);

final backupServiceProvider = Provider<BackupService>((ref) {
  final startup = ref.watch(startupServiceProvider);
  return BackupServiceImpl(
    host: startup,
    keyManager: ref.watch(keyManagerProvider),
    scratch: ref.watch(scratchSpaceProvider),
    databaseFile: startup.paths.databaseFile,
    appSchemaVersion: ref.watch(appDatabaseProvider).schemaVersion,
    diag: ref.watch(diagProvider),
  );
});

final backupFacadeProvider = Provider<BackupFacade>(
  (ref) => DefaultBackupFacade(ref.watch(backupServiceProvider)),
);

// ------------------------------------------------------------ projections
// Drift watch() streams; autoDispose below workspace level (§9.1).

/// Null until `/welcome/create` finished (workspace_created settings flag)
/// — this drives the router redirect. Safe to watch in every startup state.
final workspaceProvider = StreamProvider<Workspace?>((ref) {
  ref.watch(startupStateProvider);
  ref.watch(databaseGenerationProvider);
  if (!ref.watch(databaseHostProvider).isOpen) {
    return Stream<Workspace?>.value(null);
  }
  return ref.watch(settingsServiceProvider).watchWorkspace();
});

/// The appearance preference, watched. Independent of [workspaceProvider]:
/// `/welcome` and `/recovery` render a MaterialApp before any workspace
/// exists, and both must honour the choice.
final _themeChoiceStreamProvider = StreamProvider<AppThemeChoice>((ref) {
  ref.watch(startupStateProvider);
  ref.watch(databaseGenerationProvider);
  if (!ref.watch(databaseHostProvider).isOpen) {
    return Stream<AppThemeChoice>.value(AppThemeChoice.system);
  }
  return ref.watch(settingsServiceProvider).watchThemeMode();
});

/// What the app root paints with. Never throws and never hangs: while the
/// stream is loading (or has errored, or there is no database to read) this
/// falls back to [startupThemeChoiceProvider].
final themeChoiceProvider = Provider<AppThemeChoice>(
  (ref) =>
      ref.watch(_themeChoiceStreamProvider).valueOrNull ??
      ref.watch(startupThemeChoiceProvider),
);

final itemListProvider = StreamProvider.autoDispose
    .family<List<ItemSummary>, ItemFilter>(
      (ref, filter) => ref.watch(catalogServiceProvider).watchItems(filter),
    );

/// Throws [StateError] through the stream for unknown ids — guard routes.
final itemDetailProvider = StreamProvider.autoDispose
    .family<ItemDetail, String>(
      (ref, itemId) => ref.watch(catalogServiceProvider).watchItem(itemId),
    );

final stockPositionProvider = StreamProvider.autoDispose
    .family<StockPosition, String>(
      (ref, itemId) =>
          ref.watch(inventoryServiceProvider).watchPosition(itemId),
    );

final eventListProvider = StreamProvider.autoDispose
    .family<List<EventSummary>, EventStatusFilter>(
      (ref, filter) =>
          ref.watch(eventServiceProvider).watchEvents(filter: filter),
    );

/// Throws [StateError] through the stream for unknown ids — guard routes.
final eventDetailProvider = StreamProvider.autoDispose
    .family<EventDetail, String>(
      (ref, eventId) => ref.watch(eventServiceProvider).watchEvent(eventId),
    );

final movementLogProvider = StreamProvider.autoDispose
    .family<List<MovementView>, MovementFilter>(
      (ref, filter) =>
          ref.watch(inventoryServiceProvider).watchMovements(filter),
    );

/// Monotonic ledger version: any movement append bumps it.
final ledgerVersionProvider = StreamProvider<int>(
  (ref) => ref.watch(inventoryServiceProvider).watchVersion(),
);

// Forecast: read PERSISTED snapshots; staleness is explicit, never silent.

final latestSnapshotProvider = StreamProvider.autoDispose
    .family<ForecastSnapshotView?, String>(
      (ref, eventId) =>
          ref.watch(forecastServiceProvider).watchLatestSnapshot(eventId),
    );

final forecastStalenessProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, eventId) {
      ref.watch(eventDetailProvider(eventId)); // exposure/policy/item changes
      ref.watch(ledgerVersionProvider); // on-hand + history changes
      ref.watch(latestSnapshotProvider(eventId));
      return ref.watch(forecastServiceProvider).isStale(eventId);
    });

/// What this event is about to cost, at today's prices — live as items are
/// added, removed, repriced, or their forecast load overridden. Never empty
/// of an answer: with nothing priced it emits a [PlannedCost] whose
/// `isEmpty` is true, and the surface shows no total rather than a $0.
final plannedCostProvider = StreamProvider.autoDispose
    .family<PlannedCost, String>(
      (ref, eventId) =>
          ref.watch(eventCostServiceProvider).watchPlannedCost(eventId),
    );

/// What events like this one usually cost, from confirmed closeouts alone.
/// Null — no card at all — when no confirmed history backs the question.
final eventCostPredictionProvider = StreamProvider.autoDispose
    .family<EventCostPrediction?, String>(
      (ref, eventId) =>
          ref.watch(eventCostServiceProvider).watchCostPrediction(eventId),
    );

final accuracyReviewProvider = FutureProvider.autoDispose
    .family<AccuracyReview, String>(
      (ref, eventId) =>
          ref.watch(forecastServiceProvider).accuracyReview(eventId),
    );

final closeoutRevisionsProvider = StreamProvider.autoDispose
    .family<List<EventCloseout>, String>(
      (ref, eventId) =>
          ref.watch(closeoutServiceProvider).watchRevisions(eventId),
    );

final recipeListProvider = StreamProvider.autoDispose<List<RecipeSummary>>(
  (ref) => ref.watch(recipeServiceProvider).watchRecipes(),
);

/// Throws [StateError] through the stream for unknown ids — guard routes.
final recipeDetailProvider = StreamProvider.autoDispose
    .family<RecipeDetail, String>(
      (ref, recipeId) => ref.watch(recipeServiceProvider).watchRecipe(recipeId),
    );
