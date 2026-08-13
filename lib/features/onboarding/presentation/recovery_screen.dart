/// `/recovery` (design §7.3, §9): shown when bootstrap found workspace data
/// this device cannot open where it expects it — either an existing database
/// it cannot unlock (key missing, or the stored key no longer matches), or a
/// workspace parked somewhere other than `db/loadout.db`.
///
/// Ways out, all explicit:
///
///  (a) Put a parked workspace back — [StartupParkedWorkspace] only. An
///      interrupted restore (§8.2) renames the live workspace to
///      `db/loadout.db.pre-restore` while it re-encrypts the restored
///      payload; a process death in that window leaves nothing at
///      `loadout.db` and the whole workspace parked beside it.
///      [StartupService.recoverParkedWorkspace] validates it and renames it
///      back. Before this screen offered it, only a developer with a
///      debugger could get that data back.
///  (b) Restore from a Loadout backup file — routes into the §8 restore
///      flow (`/settings/restore`).
///  (c) Start fresh — typed confirmation word, then
///      [StartupService.startFreshFromRecovery] archives the orphaned
///      ciphertext to `db/orphaned-<utcstamp>.db` (never deleted), destroys
///      the old key, and creates a new workspace under a new key.
///
/// Nothing on this screen deletes anything, in any branch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../infrastructure/startup/startup_service.dart';

/// The typed confirmation word for the start-fresh action.
const String recoveryConfirmationWord = 'FRESH';

class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  final _confirmation = TextEditingController();
  bool _showStartFresh = false;
  bool _submitting = false;
  bool _failed = false;

  /// Why the last put-it-back attempt could not proceed; null when none has
  /// failed. Drives an honest, specific message instead of a shrug.
  ParkedRecoveryFailure? _parkedFailure;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  bool get _confirmed => _confirmation.text.trim() == recoveryConfirmationWord;

  Future<void> _recoverParked(ParkedWorkspace parked) async {
    setState(() {
      _submitting = true;
      _failed = false;
      _parkedFailure = null;
    });
    try {
      final startup = ref.read(startupServiceProvider);
      final db = await startup.recoverParkedWorkspace(parked);
      ref.read(startupStateProvider.notifier).state = StartupWorkspaceOpen(db);
      if (mounted) {
        // The workspace is back and open; the redirect sends the owner on to
        // /welcome/create instead if it was never named.
        context.go('/home');
      }
    } on ParkedRecoveryException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _parkedFailure = e.failure;
        });
      }
    } catch (_) {
      // Content-free by design (§10).
      if (mounted) {
        setState(() {
          _submitting = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _startFresh() async {
    setState(() {
      _submitting = true;
      _failed = false;
      _parkedFailure = null;
    });
    try {
      final startup = ref.read(startupServiceProvider);
      final db = await startup.startFreshFromRecovery();
      ref.read(startupStateProvider.notifier).state = StartupWorkspaceOpen(db);
      if (mounted) {
        // The old ciphertext is archived; the fresh workspace still needs a
        // name and defaults.
        context.go('/welcome/create');
      }
    } catch (_) {
      // Content-free by design (§10).
      if (mounted) {
        setState(() {
          _submitting = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(startupStateProvider);
    final recovery = state is StartupRecovery ? state : null;
    final parked = recovery?.parked ?? const <ParkedWorkspace>[];
    // Putting a copy back is offered only when there is nowhere else for it
    // to go. With a live `db/loadout.db` on disk the live one wins (§8.2: the
    // swap completed) and the parked copy is kept as an archive instead.
    final candidate = state is StartupParkedWorkspace ? state.candidate : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Recovery')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  candidate == null
                      ? Icons.key_off_outlined
                      : Icons.restore_page_outlined,
                  size: 56,
                  color: candidate == null
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  candidate == null
                      ? "This device can't unlock the existing data."
                      : 'Your workspace is still on this device.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _detailFor(recovery?.reason),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  candidate == null
                      ? 'Nothing has been deleted. You can restore a backup '
                            'made with your passphrase, or start fresh.'
                      : 'Nothing has been deleted. Put it back, and carry on '
                            'where you left off.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (candidate == null && parked.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _keptCopiesNote(parked.length),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 32),
                if (_failed) ...[
                  const _ErrorCard(
                    "That didn't work. Nothing was changed — try again.",
                  ),
                  const SizedBox(height: 16),
                ],
                if (_parkedFailure case final failure?) ...[
                  _ErrorCard(_parkedFailureText(failure)),
                  const SizedBox(height: 16),
                ],
                if (candidate != null) ...[
                  Semantics(
                    label: 'Put the parked workspace back and open it',
                    button: true,
                    child: FilledButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => _recoverParked(candidate),
                      style: FilledButton.styleFrom(
                        minimumSize: primaryButtonMinSize,
                      ),
                      icon: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.unarchive_outlined),
                      label: const Text('Put my workspace back'),
                    ),
                  ),
                  if (parked.length > 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${parked.length} copies are kept on this device. The '
                      'most recent one is offered here; the others stay '
                      'exactly where they are.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                // Demoted to the secondary style when a parked workspace is
                // on offer: restoring a backup file replaces what is on the
                // device, and putting the workspace back is strictly better.
                Semantics(
                  label: 'Restore from a Loadout backup file',
                  button: true,
                  child: _RestoreButton(
                    primary: candidate == null,
                    onPressed: _submitting
                        ? null
                        : () => context.push('/settings/restore'),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_showStartFresh)
                  Semantics(
                    label: 'Start fresh with an empty workspace',
                    button: true,
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _showStartFresh = true),
                      style: OutlinedButton.styleFrom(
                        minimumSize: primaryButtonMinSize,
                      ),
                      child: const Text('Start fresh'),
                    ),
                  )
                else ...[
                  const Divider(height: 32),
                  Text('Start fresh', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '${candidate == null ? 'The unreadable data' : 'The '
                              'workspace that was set aside'} is kept in an '
                    'archived file on this device — it is never deleted '
                    '— and a new, empty workspace is created with a new '
                    'key. Type $recoveryConfirmationWord to confirm.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmation,
                    onChanged: (_) => setState(() {}),
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Type $recoveryConfirmationWord to confirm',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Archive the old data and start fresh',
                    button: true,
                    child: FilledButton(
                      onPressed: _submitting || !_confirmed
                          ? null
                          : _startFresh,
                      style: FilledButton.styleFrom(
                        minimumSize: primaryButtonMinSize,
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Archive old data and start fresh'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-state explanation. The interrupted-restore wording is deliberately
/// concrete about what happened: "something went wrong" is what sent people
/// looking for a developer in the first place.
String _detailFor(RecoveryReason? reason) => switch (reason) {
  RecoveryReason.keyMissing =>
    'The encryption key for the existing data is no longer in this '
        "device's secure storage, so the data cannot be read.",
  RecoveryReason.wrongKey =>
    'The key stored on this device does not unlock the existing data, '
        'so the data cannot be read.',
  RecoveryReason.interruptedRestore =>
    'A restore was interrupted. Your original workspace is still here, '
        'set aside where the restore left it — every item, event, and '
        'movement intact.',
  RecoveryReason.archivedWorkspace =>
    'An earlier reset set your workspace aside instead of deleting it. '
        'It is still here, and it can be opened again.',
  null =>
    'The existing data on this device cannot be read with the stored key.',
};

String _keptCopiesNote(int count) => count == 1
    ? 'An earlier copy of your workspace is also kept on this device. It has '
          'not been touched.'
    : '$count earlier copies of your workspace are also kept on this device. '
          'None of them has been touched.';

/// Honest, specific, and content-free. Every branch ends the same way,
/// because it is true in every branch: the copy is still there.
String _parkedFailureText(ParkedRecoveryFailure failure) => switch (failure) {
  ParkedRecoveryFailure.liveWorkspacePresent =>
    'A workspace is already open on this device, so the set-aside copy was '
        'left alone. It is still here.',
  ParkedRecoveryFailure.missing =>
    'That copy is no longer where it was. Nothing was changed.',
  ParkedRecoveryFailure.noKeyOnDevice =>
    'There is no encryption key on this device to open that copy with. It '
        'has not been deleted — restoring a backup file is the way in.',
  ParkedRecoveryFailure.noMatchingKey =>
    'None of the keys on this device opens that copy. It has not been '
        'deleted — restoring a backup file is the way in.',
  ParkedRecoveryFailure.damaged =>
    'That copy opens, but it did not pass its integrity checks, so it was '
        'left where it is rather than put back. It has not been deleted.',
  ParkedRecoveryFailure.openFailed =>
    'That copy could not be opened as a workspace. It was put back exactly '
        'where it was — nothing was changed.',
};

class _RestoreButton extends StatelessWidget {
  const _RestoreButton({required this.primary, required this.onPressed});

  final bool primary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.settings_backup_restore);
    const label = Text('Restore from backup file');
    return primary
        ? FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            icon: icon,
            label: label,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(minimumSize: primaryButtonMinSize),
            icon: icon,
            label: label,
          );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
