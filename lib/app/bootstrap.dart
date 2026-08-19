/// App bootstrap: runs the §7.3 startup machine BEFORE `runApp` and turns
/// the result into the provider overrides the composition root installs.
/// Shared by `lib/main.dart` (production wiring) and
/// `test/support/app_harness.dart` (test wiring) so both compose the app
/// identically.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics/diag.dart';
import '../features/settings/application/settings_service.dart';
import '../features/settings/domain/app_theme_choice.dart';
import '../infrastructure/files/scratch_space.dart';
import '../infrastructure/security/key_manager.dart';
import '../infrastructure/startup/startup_service.dart';
import 'providers.dart';

final class AppBootstrap {
  const AppBootstrap({
    required this.state,
    required this.initialLocation,
    required this.overrides,
  });

  final StartupState state;
  final String initialLocation;

  /// Install on the root `ProviderScope` (or `ProviderContainer`).
  final List<Override> overrides;
}

/// Runs `startup.bootstrap()` (which also sweeps scratch space) and
/// resolves where the router must start:
///
///  - recovery states → `/recovery`;
///  - fresh install → `/welcome`;
///  - open database → `/home` when the workspace_created flag is set,
///    `/welcome` otherwise (app quit between DB creation and naming).
///
/// A cipher-missing failure (plain SQLite linked) rethrows deliberately —
/// the app must crash, not route (§7.2).
Future<AppBootstrap> bootstrapLoadout({
  required StartupService startup,
  required KeyManager keyManager,
  required ScratchSpace scratch,
  required Diag diag,
}) async {
  final state = await startup.bootstrap();
  final initialLocation = switch (state) {
    StartupRecovery() => '/recovery',
    StartupFreshWorkspace() => '/welcome',
    StartupWorkspaceOpen(:final database) =>
      await DriftSettingsService(database).watchWorkspace().first != null
          ? '/home'
          : '/welcome',
  };
  // Read once here so the FIRST frame already has the chosen brightness;
  // the watch stream takes over from the same value.
  final themeChoice = switch (state) {
    StartupWorkspaceOpen(:final database) => await DriftSettingsService(
      database,
    ).themeMode(),
    _ => AppThemeChoice.system,
  };
  return AppBootstrap(
    state: state,
    initialLocation: initialLocation,
    overrides: [
      startupServiceProvider.overrideWithValue(startup),
      keyManagerProvider.overrideWithValue(keyManager),
      scratchSpaceProvider.overrideWithValue(scratch),
      diagProvider.overrideWithValue(diag),
      startupStateProvider.overrideWith((ref) => state),
      initialLocationProvider.overrideWithValue(initialLocation),
      startupThemeChoiceProvider.overrideWithValue(themeChoice),
    ],
  );
}
