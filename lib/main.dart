/// Production entry point: install the error floor, resolve paths, wire the
/// real key manager, diagnostics ring file, and scratch space, run the §7.3
/// startup machine, then hand the resolved overrides to the ProviderScope.
///
/// Nothing here throws out of `main` any more. A bootstrap failure — a
/// corrupt key entry, an unreadable support directory, an unanticipated
/// drift error, and deliberately the §7.2 cipher-missing guard — becomes
/// [StartupFailureApp]: a screen that says what happened in plain words and
/// offers the ways out. The refusal to run on plain SQLite is unchanged; it
/// is only visible now.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/error_handling.dart';
import 'app/startup_failure_app.dart';
import 'core/diagnostics/diag.dart';
import 'infrastructure/diagnostics/diag_sink.dart';
import 'infrastructure/files/loadout_paths.dart';
import 'infrastructure/files/scratch_space.dart';
import 'infrastructure/security/key_manager.dart';
import 'infrastructure/startup/startup_service.dart';

Future<void> main() async {
  // Binding and `runApp` stay in the root zone together — see
  // `app/error_handling.dart` for why there is no `runZonedGuarded`.
  WidgetsFlutterBinding.ensureInitialized();
  installLoadoutErrorHandlers();

  final bootstrapper = LoadoutBootstrapper();
  final outcome = await bootstrapper.run();
  runApp(switch (outcome) {
    BootstrapReady(:final boot) => ProviderScope(
      overrides: boot.overrides,
      child: const LoadoutApp(),
    ),
    final BootstrapFailed failure => StartupFailureApp(
      failure: failure,
      retry: bootstrapper.run,
    ),
  });
}

/// The four services every composition root wires (see `app/bootstrap.dart`).
typedef _Services = ({
  StartupService startup,
  KeyManager keyManager,
  ScratchSpace scratch,
  Diag diag,
});

/// The production wiring, held so it can be run more than once.
///
/// The failure screen's "Try again" re-enters [run]. It must land on the
/// SAME [StartupService], key manager, scratch space and diagnostics sink as
/// the first attempt: a restore performed from the failure screen leaves the
/// database open on that instance, and a second instance would open a second
/// handle on the same file and log to a second session id.
final class LoadoutBootstrapper {
  _Services? _services;

  Future<BootstrapOutcome> run() async {
    final services = _services ?? await _wire();
    if (services == null) {
      // No paths, so no diagnostics file, no key store, no scratch space —
      // there is nothing to retry against and nothing to export.
      return const BootstrapFailed(
        kind: BootstrapFailureKind.storageUnavailable,
      );
    }
    _services = services;
    return bootstrapOrFail(
      startup: services.startup,
      keyManager: services.keyManager,
      scratch: services.scratch,
      diag: services.diag,
    );
  }

  /// Null when the support directory could not be resolved or reached.
  Future<_Services?> _wire() async {
    try {
      final paths = await LoadoutPaths.resolve();
      final diag = RingFileDiag(logFile: paths.diagLogFile);
      final keyManager = SecureStorageKeyManager();
      final scratch = AppSupportScratchSpace(
        root: paths.scratchDir,
        diag: diag,
      );
      return (
        startup: StartupService(
          paths: paths,
          keyManager: keyManager,
          scratch: scratch,
          diag: diag,
        ),
        keyManager: keyManager,
        scratch: scratch,
        diag: diag,
      );
    } catch (_) {
      // Content-free by design (§10) — and there is no sink to write to.
      return null;
    }
  }
}
