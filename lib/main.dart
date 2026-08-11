/// Production entry point: resolve paths, wire the real key manager,
/// diagnostics ring file, and scratch space, run the §7.3 startup machine,
/// then hand the resolved overrides to the ProviderScope. A cipher-missing
/// bootstrap failure rethrows out of `main` on purpose (§7.2: refuse to run
/// on plain SQLite).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'infrastructure/diagnostics/diag_sink.dart';
import 'infrastructure/files/loadout_paths.dart';
import 'infrastructure/files/scratch_space.dart';
import 'infrastructure/security/key_manager.dart';
import 'infrastructure/startup/startup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await LoadoutPaths.resolve();
  final diag = RingFileDiag(logFile: paths.diagLogFile);
  final keyManager = SecureStorageKeyManager();
  final scratch = AppSupportScratchSpace(root: paths.scratchDir, diag: diag);
  final startup = StartupService(
    paths: paths,
    keyManager: keyManager,
    scratch: scratch,
    diag: diag,
  );
  final boot = await bootstrapLoadout(
    startup: startup,
    keyManager: keyManager,
    scratch: scratch,
    diag: diag,
  );
  runApp(ProviderScope(overrides: boot.overrides, child: const LoadoutApp()));
}
