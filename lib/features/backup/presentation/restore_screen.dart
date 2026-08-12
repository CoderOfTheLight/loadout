/// `/settings/restore` (design §9, §8.2): staged whole-workspace restore.
///
/// Pick file (through the [FileGateway] seam) → manifest info immediately
/// (`describeBackup`, no passphrase) → passphrase → `validateBackup` →
/// verified-counts preview → typed "REPLACE" → `restoreBackup`. On success
/// the screen bumps [databaseGenerationProvider] (the provider graph
/// rebuilds off the reopened database) and routes home. Every failure is
/// content-free and leaves the current workspace untouched — the service
/// guarantees it, the copy says it. Also reachable from `/recovery` (§7.3
/// action a), where no database is open — [restoreFacadeProvider] handles
/// that state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../core/result.dart';
import '../../../infrastructure/files/scratch_space.dart';
import '../../../infrastructure/startup/startup_service.dart';
import '../domain/backup_service.dart';
import 'backup_providers.dart';
import 'backup_screen.dart' show formatLocalStamp;
import 'file_gateway.dart';

/// The typed confirmation word (§8.2, §12).
const String restoreConfirmationWord = 'REPLACE';

class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();

  String? _path;
  BackupDescription? _description;
  RestorePreview? _preview;
  bool _busy = false;
  bool _restored = false;
  String? _error;

  /// Captured when a preview is staged so [dispose] can clean up without
  /// touching [ref] after unmount.
  ScratchSpace? _scratch;

  @override
  void dispose() {
    final preview = _preview;
    if (preview != null && !_restored && !_busy) {
      // Abandoned mid-flow: best-effort staging cleanup (§10 sweep is the
      // backstop). Never while busy — a restore in flight owns the staging.
      _scratch?.disposeSession(preview.stagingDir).catchError((_) {});
    }
    _passphrase.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _discardPreview() async {
    final preview = _preview;
    _preview = null;
    if (preview != null && !_restored) {
      try {
        await _scratch?.disposeSession(preview.stagingDir);
      } catch (_) {
        // Swept on next start.
      }
    }
  }

  Future<void> _pickFile() async {
    final gateway = ref.read(fileGatewayProvider);
    final facade = ref.read(restoreFacadeProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    await _discardPreview();
    final picked = await gateway.pickFile();
    if (picked == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final described = await facade.describeBackup(picked);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _passphrase.clear();
      _confirmation.clear();
      switch (described) {
        case Ok(:final value):
          _path = picked;
          _description = value;
        case Err(:final error):
          _path = null;
          _description = null;
          _error = error.message;
      }
    });
  }

  Future<void> _verify() async {
    final path = _path;
    if (path == null) return;
    final facade = ref.read(restoreFacadeProvider);
    _scratch = ref.read(scratchSpaceProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    await _discardPreview();
    final validated = await facade.validateBackup(
      path: path,
      passphrase: _passphrase.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (validated) {
        case Ok(:final value):
          _preview = value;
          _confirmation.clear();
        case Err(:final error):
          _error = error.message;
      }
    });
  }

  Future<void> _restore() async {
    final preview = _preview;
    if (preview == null) return;
    final facade = ref.read(restoreFacadeProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await facade.restoreBackup(preview);
    if (!mounted) {
      if (result is Ok) _restored = true;
      return;
    }
    switch (result) {
      case Err(:final error):
        setState(() {
          _busy = false;
          _error = error.message;
        });
      case Ok():
        setState(() {
          _busy = false;
          _restored = true;
        });
        final startup = ref.read(startupServiceProvider);
        if (startup.isOpen) {
          // Restore from a §7.3 recovery state must also unpin the router;
          // with an already-open workspace this just refreshes the handle.
          ref.read(startupStateProvider.notifier).state = StartupWorkspaceOpen(
            startup.database,
          );
        }
        // §8.2/§9.1 contract: the reopen flow bumps the generation so every
        // service and projection rebuilds off the restored database.
        ref.read(databaseGenerationProvider.notifier).state++;
        GoRouter.maybeOf(context)?.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = _description;
    final preview = _preview;
    final confirmed = _confirmation.text.trim() == restoreConfirmationWord;
    return Scaffold(
      appBar: AppBar(title: const Text('Restore')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Restoring replaces everything in this workspace with the '
                  'contents of a backup file. Your current data is only '
                  'touched after the backup is fully verified and you '
                  'confirm.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '$_error\nYour current data has not been changed.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_restored) ...[
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Restore complete.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                OutlinedButton.icon(
                  onPressed: _busy || _restored ? null : _pickFile,
                  style: OutlinedButton.styleFrom(
                    minimumSize: primaryButtonMinSize,
                  ),
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(
                    description == null
                        ? 'Choose backup file…'
                        : 'Choose a different file…',
                  ),
                ),
                if (description != null && !_restored) ...[
                  const SizedBox(height: 16),
                  _ManifestCard(description: description),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passphrase,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Backup passphrase',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _busy || _passphrase.text.isEmpty
                        ? null
                        : _verify,
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                    ),
                    child: const Text('Unlock and verify'),
                  ),
                ],
                if (preview != null && !_restored) ...[
                  const SizedBox(height: 16),
                  _PreviewCard(preview: preview),
                  const SizedBox(height: 16),
                  Text(
                    'Replacing cannot be undone. Everything currently in '
                    'this workspace will be replaced by the backup above. '
                    'Type $restoreConfirmationWord to confirm.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmation,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Type $restoreConfirmationWord to confirm',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy || !confirmed ? null : _restore,
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    child: const Text('Replace workspace with backup'),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 12),
                      Text('Working…', style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManifestCard extends StatelessWidget {
  const _ManifestCard({required this.description});

  final BackupDescription description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = DateTime.tryParse(description.createdAtUtc);
    final counts = description.counts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From the file (not verified yet)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Created: '
              '${created == null ? description.createdAtUtc : formatLocalStamp(created)}',
            ),
            Text('App version: ${description.appVersion}'),
            Text(
              'Contents: ${counts.movements} movements · '
              '${counts.items} items · ${counts.events} events',
            ),
            Text('Size: ${_formatBytes(description.containerSizeBytes)}'),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final RestorePreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = DateTime.tryParse(preview.description.createdAtUtc);
    final counts = preview.verifiedCounts;
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Verified backup contents',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Created: '
              '${created == null ? preview.description.createdAtUtc : formatLocalStamp(created)}',
            ),
            Text(
              '${counts.movements} movements · ${counts.items} items · '
              '${counts.events} events',
            ),
            Text('Schema version: ${preview.payloadUserVersion}'),
            const SizedBox(height: 8),
            Text(
              'Verified without touching your current data.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
