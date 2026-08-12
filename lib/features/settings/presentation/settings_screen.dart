/// `/settings` (design §9): workspace preferences and the doors to the
/// data/privacy/diagnostics/about/reset sub-screens.
///
/// Groups: Workspace (name, default policy, exposure label, history
/// window — plain upserts through [SettingsService.updatePreferences]);
/// Data (Backup, Restore) with the §12.22 in-app backup nudge banner;
/// Privacy; Diagnostics; About; danger zone (Reset workspace). The OS-lock
/// advisory card is shown unconditionally (§12.18).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../backup/presentation/backup_providers.dart';
import '../../forecasting/domain/forecast_engine.dart';
import '../application/settings_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(SettingsService service) change,
  ) async {
    try {
      await change(ref.read(settingsServiceProvider));
    } catch (_) {
      // Content-free by design (§9 cross-cutting UX).
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save this change. Try again."),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final workspace = ref.watch(workspaceProvider).valueOrNull;
    final lastBackup = ref.watch(lastBackupProvider);
    final showBackupNudge =
        lastBackup.hasValue && lastBackup.valueOrNull == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showBackupNudge) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: WarningBanner(
                      message:
                          "You haven't saved a backup yet. One encrypted "
                          'file protects everything in this workspace.',
                      actionLabel: 'Back up now',
                      onAction: () => context.push('/settings/backup'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _GroupHeader('Workspace'),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Workspace name'),
                  subtitle: Text(workspace?.displayName ?? '—'),
                  onTap: workspace == null
                      ? null
                      : () async {
                          final name = await _promptText(
                            context,
                            title: 'Workspace name',
                            initial: workspace.displayName,
                          );
                          if (name != null && name.isNotEmpty) {
                            if (!context.mounted) return;
                            await _save(
                              context,
                              ref,
                              (s) => s.updatePreferences(name: name),
                            );
                          }
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Default planning policy'),
                  subtitle: Text(
                    workspace == null
                        ? '—'
                        : policyCaption(workspace.defaultPolicy),
                  ),
                  onTap: workspace == null
                      ? null
                      : () async {
                          final policy = await _promptPolicy(
                            context,
                            current: workspace.defaultPolicy,
                          );
                          if (policy != null) {
                            if (!context.mounted) return;
                            await _save(
                              context,
                              ref,
                              (s) => s.updatePreferences(defaultPolicy: policy),
                            );
                          }
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Exposure label'),
                  subtitle: Text(workspace?.exposureLabel ?? '—'),
                  onTap: workspace == null
                      ? null
                      : () async {
                          final label = await _promptText(
                            context,
                            title: 'Exposure label',
                            initial: workspace.exposureLabel,
                            helper:
                                'The word Loadout uses for expected crowd '
                                'size — "attendance", "covers", "orders".',
                          );
                          if (label != null && label.isNotEmpty) {
                            if (!context.mounted) return;
                            await _save(
                              context,
                              ref,
                              (s) => s.updatePreferences(exposureLabel: label),
                            );
                          }
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.history_toggle_off),
                  title: const Text('History window'),
                  subtitle: Text(
                    workspace == null
                        ? '—'
                        : '${workspace.historyWindow} closed events',
                  ),
                  onTap: workspace == null
                      ? null
                      : () async {
                          final window = await _promptHistoryWindow(
                            context,
                            initial: workspace.historyWindow,
                          );
                          if (window != null) {
                            if (!context.mounted) return;
                            await _save(
                              context,
                              ref,
                              (s) => s.updatePreferences(historyWindow: window),
                            );
                          }
                        },
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text(
                        "Loadout's data is encrypted on this device. Protect "
                        "it with your phone's screen lock.",
                      ),
                      subtitle: Text('Nothing is uploaded, ever.'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _GroupHeader('Data'),
                ListTile(
                  leading: const Icon(Icons.save_outlined),
                  title: const Text('Back up'),
                  subtitle: const Text('Create one encrypted backup file'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/backup'),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('Restore'),
                  subtitle: const Text(
                    'Replace this workspace from a backup file',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/restore'),
                ),
                const SizedBox(height: 8),
                _GroupHeader('App'),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Privacy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/privacy'),
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Diagnostics'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/diagnostics'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/about'),
                ),
                const SizedBox(height: 8),
                _GroupHeader('Danger zone', color: theme.colorScheme.error),
                ListTile(
                  leading: Icon(
                    Icons.warning_amber_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Reset workspace',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: const Text(
                    'Archive the encrypted data and start over',
                  ),
                  onTap: () => context.push('/settings/reset'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Balanced (+10 % reserve)" — shared caption shape.
String policyCaption(PlanningPolicy policy) {
  final name = switch (policy) {
    PlanningPolicy.lean => 'Lean',
    PlanningPolicy.balanced => 'Balanced',
    PlanningPolicy.cautious => 'Cautious',
  };
  return '$name (+${policy.reservePercent} % reserve)';
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: color ?? theme.colorScheme.primary,
        ),
      ),
    );
  }
}

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String initial,
  String? helper,
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _TextPromptDialog(title: title, initial: initial, helper: helper),
);

/// Owns its [TextEditingController]: disposal happens with the dialog's
/// State, safely after the pop animation.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    this.helper,
    this.digitsOnly = false,
  });

  final String title;
  final String initial;
  final String? helper;
  final bool digitsOnly;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: widget.digitsOnly ? TextInputType.number : null,
      inputFormatters: [
        if (widget.digitsOnly) FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        helperText: widget.helper,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

Future<int?> _promptHistoryWindow(
  BuildContext context, {
  required int initial,
}) async {
  final raw = await showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: 'History window',
      initial: '$initial',
      helper: 'How many recent closed events forecasts learn from. At least 1.',
      digitsOnly: true,
    ),
  );
  if (raw == null) return null;
  final value = int.tryParse(raw);
  return value == null || value < 1 ? null : value;
}

Future<PlanningPolicy?> _promptPolicy(
  BuildContext context, {
  required PlanningPolicy current,
}) => showDialog<PlanningPolicy>(
  context: context,
  builder: (dialogContext) => SimpleDialog(
    title: const Text('Default planning policy'),
    children: [
      for (final policy in PlanningPolicy.values)
        ListTile(
          leading: Icon(
            policy == current
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          title: Text(policyCaption(policy)),
          selected: policy == current,
          onTap: () => Navigator.of(dialogContext).pop(policy),
        ),
    ],
  ),
);
