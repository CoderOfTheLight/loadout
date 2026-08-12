/// `/settings/backup` (design §9, §8.1): create one encrypted backup file.
///
/// Passphrase entered twice — hard minimum 8 characters, advisory meter
/// recommending 12+ (§12.20) — then [BackupFacade.createBackup] produces the
/// container in a backup scratch session, the file is handed to the
/// save-file dialog through the [FileGateway] seam (save-file-only egress,
/// §12.19), and the scratch session is disposed whatever happens. Every
/// failure message is content-free.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../core/result.dart';
import '../application/backup_facade.dart';
import 'backup_providers.dart';
import 'file_gateway.dart';
import 'passphrase_meter.dart';

/// Hard minimum passphrase length (§12.20). The meter recommends 12+.
const int minBackupPassphraseLength = 8;

enum _BackupOutcome { none, saved, notSaved, failed }

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  _BackupOutcome _outcome = _BackupOutcome.none;
  String _failureMessage = '';

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _meetsMinimum =>
      _passphrase.text.length >= minBackupPassphraseLength;

  bool get _matches => _passphrase.text == _confirm.text;

  bool get _canCreate => _meetsMinimum && _matches && !_busy;

  Future<void> _create() async {
    final facade = ref.read(backupFacadeProvider);
    final gateway = ref.read(fileGatewayProvider);
    final scratch = ref.read(scratchSpaceProvider);
    setState(() {
      _busy = true;
      _outcome = _BackupOutcome.none;
    });
    final result = await facade.createBackup(passphrase: _passphrase.text);
    switch (result) {
      case Err(:final error):
        _finish(_BackupOutcome.failed, message: error.message);
      case Ok(:final value):
        final Directory session = value.file.parent;
        var outcome = _BackupOutcome.failed;
        var message = '';
        try {
          final savedTo = await gateway.saveFile(
            sourcePath: value.file.path,
            suggestedName: value.suggestedFileName,
          );
          if (savedTo == null) {
            outcome = _BackupOutcome.notSaved;
          } else {
            await recordBackupSaved(ref.read(appDatabaseProvider));
            outcome = _BackupOutcome.saved;
          }
        } catch (_) {
          // Content-free by design (§10): no dialog/plugin detail surfaces.
          message = "The backup file couldn't be saved. Nothing was changed.";
        }
        // Dispose the scratch session BEFORE reporting: the container must
        // be gone from app storage whatever the dialog outcome was.
        try {
          await scratch.disposeSession(session);
        } catch (_) {
          // Swept on next start (§10).
        }
        _finish(outcome, message: message);
    }
  }

  void _finish(_BackupOutcome outcome, {String message = ''}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
      _failureMessage = message;
      if (outcome == _BackupOutcome.saved) {
        _passphrase.clear();
        _confirm.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastBackup = ref.watch(lastBackupProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'One encrypted file',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your entire workspace becomes a single encrypted '
                          'file, protected by the passphrase you choose '
                          'below. Anyone with the file and the passphrase '
                          'can read everything in it — keep both safe.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'If you forget the passphrase, the backup cannot '
                          'be opened. It cannot be recovered.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    lastBackup == null
                        ? 'No backup has been saved yet.'
                        : 'Last backup: ${formatLocalStamp(lastBackup)}',
                  ),
                ),
                const SizedBox(height: 8),
                if (_outcome == _BackupOutcome.saved) ...[
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Backup file saved.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_outcome == _BackupOutcome.notSaved) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "The backup file wasn't saved, so it was discarded. "
                        'Nothing was changed.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_outcome == _BackupOutcome.failed) ...[
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _failureMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Backup passphrase',
                    helperText: 'At least 8 characters. 12 or more is safer.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                PassphraseMeter(passphrase: _passphrase.text),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Repeat passphrase',
                    border: const OutlineInputBorder(),
                    errorText: _confirm.text.isNotEmpty && !_matches
                        ? 'Passphrases do not match.'
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                if (_busy) ...[
                  Row(
                    children: [
                      const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Creating encrypted backup…',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: _canCreate ? _create : null,
                  style: FilledButton.styleFrom(
                    minimumSize: primaryButtonMinSize,
                  ),
                  child: const Text('Create backup file…'),
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

/// `2026-08-11 14:03` in device-local time (no intl dependency in v1).
String formatLocalStamp(DateTime utc) {
  final t = utc.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
