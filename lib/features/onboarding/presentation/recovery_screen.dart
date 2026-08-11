/// `/recovery` (design §7.3, §9): shown only when bootstrap found an
/// existing database this device cannot unlock (key missing, or the stored
/// key no longer matches). Two ways out, both explicit:
///
///  (a) Restore from a Loadout backup file — routes into the §8 restore
///      flow (`/settings/restore`).
///  (b) Start fresh — typed confirmation word, then
///      [StartupService.startFreshFromRecovery] archives the orphaned
///      ciphertext to `db/orphaned-<utcstamp>.db` (never deleted), destroys
///      the old key, and creates a new workspace under a new key.
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

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  bool get _confirmed => _confirmation.text.trim() == recoveryConfirmationWord;

  Future<void> _startFresh() async {
    setState(() {
      _submitting = true;
      _failed = false;
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
    final reason = state is StartupRecovery ? state.reason : null;
    final detail = switch (reason) {
      RecoveryReason.keyMissing =>
        'The encryption key for the existing data is no longer in this '
            "device's secure storage, so the data cannot be read.",
      RecoveryReason.wrongKey =>
        'The key stored on this device does not unlock the existing data, '
            'so the data cannot be read.',
      null =>
        'The existing data on this device cannot be read with the stored '
            'key.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.key_off_outlined,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  "This device can't unlock the existing data.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Nothing has been deleted. You can restore a backup made '
                  'with your passphrase, or start fresh.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                if (_failed) ...[
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "That didn't work. Nothing was changed — try again.",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Semantics(
                  label: 'Restore from a Loadout backup file',
                  button: true,
                  child: FilledButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => context.push('/settings/restore'),
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                    ),
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('Restore from backup file'),
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
                    'The unreadable data is kept in an archived file on this '
                    'device — it is never deleted — and a new, empty '
                    'workspace is created with a new key. '
                    'Type $recoveryConfirmationWord to confirm.',
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
