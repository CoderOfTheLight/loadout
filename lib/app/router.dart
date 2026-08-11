/// The complete §9 screen map: one [GoRouter] built once, redirect driven
/// by a `refreshListenable` bumped from [workspaceProvider] /
/// [startupStateProvider] listeners — never by recreating the router.
/// `StatefulShellRoute.indexedStack` hosts the five-tab shell; forms and
/// detail screens push full-screen on the root navigator
/// (`parentNavigatorKey`). Bootstrap alone can route to `/recovery`.
///
/// FINAL — feature agents replace screen file contents only; this router
/// never needs touching again.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/backup/presentation/backup_screen.dart';
import '../features/backup/presentation/restore_screen.dart';
import '../features/catalog/presentation/item_detail_screen.dart';
import '../features/catalog/presentation/item_edit_screen.dart';
import '../features/catalog/presentation/item_list_screen.dart';
import '../features/closeout/presentation/closeout_screen.dart';
import '../features/events/presentation/event_detail_screen.dart';
import '../features/events/presentation/event_edit_screen.dart';
import '../features/events/presentation/event_list_screen.dart';
import '../features/forecasting/presentation/forecast_line_detail_screen.dart';
import '../features/forecasting/presentation/forecast_review_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/inventory/presentation/activity_screen.dart';
import '../features/inventory/presentation/correction_screen.dart';
import '../features/inventory/presentation/movement_detail_screen.dart';
import '../features/inventory/presentation/movement_entry_screen.dart';
import '../features/onboarding/presentation/create_workspace_screen.dart';
import '../features/onboarding/presentation/recovery_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/production/presentation/production_planning_screen.dart';
import '../features/recipes/presentation/recipe_detail_screen.dart';
import '../features/recipes/presentation/recipe_edit_screen.dart';
import '../features/recipes/presentation/recipe_list_screen.dart';
import '../features/settings/presentation/about_screen.dart';
import '../features/settings/presentation/diagnostics_screen.dart';
import '../features/settings/presentation/privacy_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/workspace_reset_screen.dart';
import '../infrastructure/startup/startup_service.dart';
import 'providers.dart';
import 'shell.dart';

/// The single router instance. Rebuilt only if the composition root itself
/// is replaced (never during normal app life).
final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  // §9: redirect driven by refreshListenable, never by recreating the
  // router. Listeners never rebuild this provider.
  final refresh = ValueNotifier(0);
  ref.onDispose(refresh.dispose);
  ref.listen<Object?>(workspaceProvider, (_, _) => refresh.value++);
  ref.listen<Object?>(startupStateProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: ref.read(initialLocationProvider),
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),

      // ----------------------------------------------- outside the shell
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (_, _) => const CreateWorkspaceScreen(),
          ),
        ],
      ),
      GoRoute(path: '/recovery', builder: (_, _) => const RecoveryScreen()),

      // ------------------------------- root-level pushes (no tab bar)
      GoRoute(
        path: '/movements/new',
        parentNavigatorKey: rootKey,
        builder: (_, state) => MovementEntryScreen(
          kind: state.uri.queryParameters['kind'],
          itemId: state.uri.queryParameters['itemId'],
        ),
      ),
      GoRoute(
        path: '/movements/:movementId',
        parentNavigatorKey: rootKey,
        builder: (_, state) => MovementDetailScreen(
          movementId: state.pathParameters['movementId']!,
        ),
        routes: [
          GoRoute(
            path: 'correct',
            parentNavigatorKey: rootKey,
            builder: (_, state) => CorrectionScreen(
              movementId: state.pathParameters['movementId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/activity',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const ActivityScreen(),
      ),
      GoRoute(
        path: '/production',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const ProductionPlanningScreen(),
      ),

      // ------------------------------------------------------- the shell
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            LoadoutShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/events',
                builder: (_, _) => const EventListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const EventEditScreen(),
                  ),
                  GoRoute(
                    path: ':eventId',
                    parentNavigatorKey: rootKey,
                    builder: (_, state) => EventDetailScreen(
                      eventId: state.pathParameters['eventId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => EventEditScreen(
                          eventId: state.pathParameters['eventId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'forecast',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => ForecastReviewScreen(
                          eventId: state.pathParameters['eventId']!,
                        ),
                        routes: [
                          GoRoute(
                            path: ':itemId',
                            parentNavigatorKey: rootKey,
                            builder: (_, state) => ForecastLineDetailScreen(
                              eventId: state.pathParameters['eventId']!,
                              itemId: state.pathParameters['itemId']!,
                            ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'closeout',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => CloseoutScreen(
                          eventId: state.pathParameters['eventId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/items',
                builder: (_, _) => const ItemListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const ItemEditScreen(),
                  ),
                  GoRoute(
                    path: ':itemId',
                    parentNavigatorKey: rootKey,
                    builder: (_, state) => ItemDetailScreen(
                      itemId: state.pathParameters['itemId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => ItemEditScreen(
                          itemId: state.pathParameters['itemId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/recipes',
                builder: (_, _) => const RecipeListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const RecipeEditScreen(),
                  ),
                  GoRoute(
                    path: ':recipeId',
                    parentNavigatorKey: rootKey,
                    builder: (_, state) => RecipeDetailScreen(
                      recipeId: state.pathParameters['recipeId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'revise',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => RecipeEditScreen(
                          recipeId: state.pathParameters['recipeId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'backup',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const BackupScreen(),
                  ),
                  GoRoute(
                    path: 'restore',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const RestoreScreen(),
                  ),
                  GoRoute(
                    path: 'privacy',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const PrivacyScreen(),
                  ),
                  GoRoute(
                    path: 'diagnostics',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const DiagnosticsScreen(),
                  ),
                  GoRoute(
                    path: 'reset',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const WorkspaceResetScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    parentNavigatorKey: rootKey,
                    builder: (_, _) => const AboutScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Startup-machine + workspace-flag redirect (§7.3, §9):
///  - a [StartupRecovery] bootstrap pins the app to `/recovery` (the
///    restore flow entry `/settings/restore` stays reachable from there);
///  - no workspace yet (null from [workspaceProvider] until
///    `createWorkspace` runs) pins onboarding to `/welcome*`;
///  - with a workspace, onboarding and recovery locations flip to `/home`.
String? _redirect(Ref ref, GoRouterState state) {
  final startup = ref.read(startupStateProvider);
  final location = state.matchedLocation;

  if (startup is StartupRecovery) {
    const allowed = {'/recovery', '/settings/restore'};
    return allowed.contains(location) ? null : '/recovery';
  }

  final workspace = ref.read(workspaceProvider);
  if (workspace.isLoading) {
    // Stay put; the refreshListenable re-runs this on the first emission.
    return null;
  }
  const onboarding = {'/welcome', '/welcome/create'};
  if (workspace.valueOrNull == null) {
    return onboarding.contains(location) ? null : '/welcome';
  }
  if (onboarding.contains(location) || location == '/recovery') {
    return '/home';
  }
  return null;
}
