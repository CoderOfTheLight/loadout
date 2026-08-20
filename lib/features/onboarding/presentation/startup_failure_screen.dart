/// The screen shown when the app could not start at all — the one state
/// `/recovery` cannot cover, because `/recovery` is a route and this happens
/// before there is a router.
///
/// `main()` resolves paths, opens the encrypted database and runs the §7.3
/// startup machine before `runApp`. Everything it anticipates ends in a
/// [StartupState]; everything it does not used to escape `main` and leave
/// the owner looking at a blank screen — the same shape as the half-applied
/// v5 migration this project already lived through. `bootstrapOrFail` turns
/// that throw into this screen.
///
/// What it offers, in the order that helps:
///
///  (a) **Try again** — re-runs the same bootstrap over the same services.
///      Free, and it is what "close it and open it again" would do anyway.
///  (b) **Restore from backup file** — the §8.2 flow, which works with no
///      database open (that is what `restoreFacadeProvider` is for). Coming
///      back from it re-runs the bootstrap, so a completed restore lands in
///      the app.
///  (c) **Save diagnostics file…** — until now the log lived behind an app
///      that would not open. Content-free either way (§10).
///
/// [BootstrapFailureKind.cipherMissing] gets none of (a) or (b) on purpose:
/// the §7.2 guard refuses to run on plain SQLite, and no amount of retrying
/// or restoring links SQLCipher into a build that shipped without it.
/// Refusing is the behaviour; this screen only makes the refusal legible.
///
/// Nothing here renders an exception, a stack trace, a path, or an internal
/// identifier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../backup/presentation/restore_screen.dart';
import '../../settings/presentation/save_diagnostics_button.dart';

class StartupFailureScreen extends ConsumerWidget {
  const StartupFailureScreen({
    super.key,
    required this.kind,
    required this.canRetry,
    required this.canRestore,
    required this.busy,
    required this.onRetry,
  });

  final BootstrapFailureKind kind;
  final bool canRetry;
  final bool canRestore;

  /// A retry is in flight; every action is inert until it lands.
  final bool busy;

  final Future<void> Function() onRetry;

  /// Pushes the §8.2 restore flow, then re-runs the bootstrap when it
  /// returns: a completed restore leaves the workspace open, and the retry
  /// is what notices.
  Future<void> _restore(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RestoreScreen()));
    if (!context.mounted) return;
    await onRetry();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final showDiagnostics = canSaveDiagnostics(ref.watch(diagProvider));
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.l),
                Icon(
                  kind == BootstrapFailureKind.cipherMissing
                      ? Icons.lock_outline
                      : Icons.error_outline,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: Space.l),
                Text(
                  'Loadout could not start.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: Space.s),
                Text(
                  _lead(kind),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: Space.s),
                Text(
                  _reassurance(kind),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.s),
                Text(
                  _guidance(kind),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.xxl),
                if (canRetry) ...[
                  Semantics(
                    label: 'Try starting Loadout again',
                    button: true,
                    child: FilledButton(
                      onPressed: busy ? null : onRetry,
                      style: FilledButton.styleFrom(
                        minimumSize: primaryButtonMinSize,
                      ),
                      child: busy
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: Space.m),
                ],
                if (canRestore) ...[
                  Semantics(
                    label: 'Restore from a Loadout backup file',
                    button: true,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _restore(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: primaryButtonMinSize,
                      ),
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('Restore from backup file'),
                    ),
                  ),
                  const SizedBox(height: Space.m),
                ],
                if (showDiagnostics) ...[
                  const Divider(height: Space.xxl),
                  Text(
                    'Ask someone to look at this',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Space.s),
                  Text(
                    'The diagnostics file records times, event codes and '
                    'numbers only — never your items, events, or notes. It '
                    'is the only record of what happened here.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Space.m),
                  const SaveDiagnosticsButton(),
                ],
                const SizedBox(height: Space.l),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One plain sentence for what went wrong. No exception, no identifier —
/// this audience knows Excel and Word.
String _lead(BootstrapFailureKind kind) => switch (kind) {
  BootstrapFailureKind.cipherMissing =>
    'This copy of Loadout is missing the part that unlocks your data.',
  BootstrapFailureKind.workspaceUnreadable =>
    'Something went wrong while it was opening your data.',
  BootstrapFailureKind.storageUnavailable =>
    'Loadout could not reach the place on this device where it keeps your '
        'data.',
};

/// The sentence that matters most, and it is true in every branch: nothing
/// was deleted.
String _reassurance(BootstrapFailureKind kind) => switch (kind) {
  BootstrapFailureKind.cipherMissing =>
    'Nothing has been changed and nothing has been deleted — your data is '
        'still on this device, locked.',
  BootstrapFailureKind.workspaceUnreadable ||
  BootstrapFailureKind.storageUnavailable =>
    'Nothing has been changed and nothing has been deleted — your data is '
        'still on this device.',
};

String _guidance(BootstrapFailureKind kind) => switch (kind) {
  BootstrapFailureKind.cipherMissing =>
    'Loadout will not open your data without that part, and it will never '
        'fall back to keeping your data unprotected instead. Installing '
        'Loadout again from where you got it is the fix.',
  BootstrapFailureKind.workspaceUnreadable =>
    'Try again first. If it keeps happening, restoring your most recent '
        'backup file replaces what is on this device with a copy that is '
        'known to work.',
  BootstrapFailureKind.storageUnavailable =>
    'Try again. If it keeps happening, restart the device and open Loadout '
        'again.',
};
