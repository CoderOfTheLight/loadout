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
import '../infrastructure/db/open_database.dart';
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
/// A cipher-missing failure (plain SQLite linked) throws out of here
/// deliberately — the app must refuse to run, not route (§7.2). The refusal
/// is presented by [bootstrapOrFail], not swallowed by it.
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

// ------------------------------------------------------ failing to start

/// Why the app could not start. Deliberately coarse: each member is a
/// different thing to SAY to the owner, not a different exception. The
/// exception itself never reaches the screen (§10).
enum BootstrapFailureKind {
  /// The §7.2 cipher guard fired — this build has plain SQLite linked. The
  /// app keeps refusing to run rather than write an unencrypted workspace;
  /// it just refuses onto a screen now.
  cipherMissing,

  /// Bootstrap threw for any other reason: an unreadable key entry, a drift
  /// or migration failure, a `workspace_meta` that would not answer.
  workspaceUnreadable,

  /// The support directory itself could not be resolved or reached, so
  /// nothing — not even the diagnostics log — was ever wired.
  storageUnavailable,
}

/// The result of trying to start: either a wired app or a presentable
/// failure.
sealed class BootstrapOutcome {
  const BootstrapOutcome();
}

final class BootstrapReady extends BootstrapOutcome {
  const BootstrapReady(this.boot);
  final AppBootstrap boot;
}

final class BootstrapFailed extends BootstrapOutcome {
  const BootstrapFailed({required this.kind, this.overrides = const []});

  final BootstrapFailureKind kind;

  /// Whatever the failure screen's `ProviderScope` can still install —
  /// empty when the failure happened before the services existed
  /// ([BootstrapFailureKind.storageUnavailable]), in which case no in-app
  /// action can run at all.
  final List<Override> overrides;

  /// The §8.2 restore flow reads the four bootstrap-wired services and no
  /// database, so it is reachable from the failure screen — but only when
  /// those services exist, and never on [BootstrapFailureKind.cipherMissing],
  /// where re-encrypting a restored payload would hit the same missing
  /// SQLCipher.
  bool get canRestore =>
      kind == BootstrapFailureKind.workspaceUnreadable && overrides.isNotEmpty;

  /// Retrying is only honest where the failure could be transient.
  bool get canRetry => kind != BootstrapFailureKind.cipherMissing;
}

/// [bootstrapLoadout] with a floor under it: a throw becomes a screen.
///
/// Records [DiagEvent.startupFailed] BEFORE returning, so the log the owner
/// exports from the failure screen says the app failed to start and with
/// what exception *type* — the sink cannot carry more than that (§10).
/// `StartupService.bootstrap` has usually already logged the specific cause
/// (`dbCipherMissing`, `migrationFail`); this line is what ties it to "and
/// the app did not come up".
///
/// Safe to call again on the same services: that is the failure screen's
/// "Try again", and after a restore it is what opens the restored
/// workspace.
Future<BootstrapOutcome> bootstrapOrFail({
  required StartupService startup,
  required KeyManager keyManager,
  required ScratchSpace scratch,
  required Diag diag,
}) async {
  try {
    return BootstrapReady(
      await bootstrapLoadout(
        startup: startup,
        keyManager: keyManager,
        scratch: scratch,
        diag: diag,
      ),
    );
  } catch (e) {
    diag.event(DiagEvent.startupFailed, errorType: e.runtimeType.toString());
    return BootstrapFailed(
      kind: isCipherMissingError(e)
          ? BootstrapFailureKind.cipherMissing
          : BootstrapFailureKind.workspaceUnreadable,
      overrides: [
        startupServiceProvider.overrideWithValue(startup),
        keyManagerProvider.overrideWithValue(keyManager),
        scratchSpaceProvider.overrideWithValue(scratch),
        diagProvider.overrideWithValue(diag),
        // Nothing renders this value — there is no router in the failure
        // scope. It exists because the restore flow WRITES the state
        // provider when it reopens the database, and a StateProvider has to
        // be readable before it can be written. Any non-open state does; a
        // recovery state is the truthful shape of "there is data here we
        // could not open".
        startupStateProvider.overrideWith(
          (ref) => const StartupRecovery(RecoveryReason.wrongKey),
        ),
      ],
    );
  }
}
