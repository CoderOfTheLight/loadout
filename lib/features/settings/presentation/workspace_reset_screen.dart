/// `/settings/reset` (design §9, §7.3): typed-confirmation reset. The
/// startup service archives the encrypted database to
/// `db/orphaned-<utcstamp>.db` (never deleted), RETAINS a copy of the key
/// that opens it under the archive's label, destroys the live key entry, and
/// opens a fresh, empty workspace under a new key; the screen then routes to
/// `/welcome` for naming. Failures are content-free.
///
/// The copy here says exactly that, because the screen used to say the
/// opposite: that the key was destroyed and the archive was "permanently
/// unreadable". `StartupService.startFreshFromRecovery` retains the key on
/// purpose — an archive without its key is deleted data, and a reset the
/// owner regrets should not be the end of a season's records. A reset is
/// therefore NOT an erase, and this screen must not imply that it is (see
/// docs/security/THREAT_MODEL.md §3.2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../infrastructure/startup/startup_service.dart';

/// The typed confirmation word for the reset action (§7.3).
const String resetConfirmationWord = 'RESET';

class WorkspaceResetScreen extends ConsumerStatefulWidget {
  const WorkspaceResetScreen({super.key});

  @override
  ConsumerState<WorkspaceResetScreen> createState() =>
      _WorkspaceResetScreenState();
}

class _WorkspaceResetScreenState extends ConsumerState<WorkspaceResetScreen> {
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  bool get _confirmed => _confirmation.text.trim() == resetConfirmationWord;

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final startup = ref.read(startupServiceProvider);
      // Archives the ciphertext (never deleted), destroys the key, and
      // opens a fresh workspace under a new key (§7.3).
      final db = await startup.startFreshFromRecovery();
      ref.read(startupStateProvider.notifier).state = StartupWorkspaceOpen(db);
      if (mounted) {
        // The fresh workspace still needs a name and defaults; the router
        // pins /welcome until createWorkspace runs.
        context.go('/welcome');
      }
    } catch (_) {
      // Content-free by design (§10).
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset workspace')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Start over with an empty workspace',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loadout starts again empty. Everything you have entered '
                  'stops showing up in the app: items, events, counts, '
                  'recipes, history.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'The encrypted data file is kept in an archive on this '
                  'device — it is never deleted — and the key that opens it '
                  'is kept with it, so the old workspace can still be '
                  'recovered. This is not a way to erase it from the device.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'A backup file is the copy you can open yourself, on any '
                  'device. Create one first if this data matters.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => context.push('/settings/backup'),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Create a backup first'),
                  ),
                ),
                const SizedBox(height: 24),
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
                TextField(
                  controller: _confirmation,
                  onChanged: (_) => setState(() {}),
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Type $resetConfirmationWord to confirm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Archive the data and reset this workspace',
                  button: true,
                  child: FilledButton(
                    onPressed: _busy || !_confirmed ? null : _reset,
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Archive data and reset workspace'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
