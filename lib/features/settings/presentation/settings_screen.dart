/// `/settings` (design §9): workspace preferences and the doors to the
/// data/privacy/diagnostics/about/reset sub-screens.
///
/// Groups: Workspace (name, then the three preferences under the plain
/// names they were renamed to for a spreadsheet-literate owner — "How much
/// extra to bring" (default policy), "What you count" (exposure label),
/// "How far back to look" (history window); all plain upserts through
/// [SettingsService.updatePreferences], values and behaviour unchanged);
/// Appearance (Follow phone / Light / Dark — three radio rows rather than a
/// `SegmentedButton`, because "Follow phone" beside two more segments stops
/// fitting one line well before 200 % text scale, and rows are already this
/// screen's grammar);
/// Data (Backup, Restore) with the §12.22 in-app backup nudge banner;
/// Privacy; Diagnostics; About; danger zone (Reset workspace). The OS-lock
/// advisory card is shown unconditionally (§12.18).
///
/// Visually each group is now one outlined card of rows rather than a run of
/// loose tiles: on a long settings screen the grouping is what tells you
/// where one subject ends and the next begins. Every subtitle says what the
/// setting does, not what it is called.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/policy_copy.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/section_header.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../backup/presentation/backup_providers.dart';
import '../../forecasting/domain/forecast_engine.dart';
import '../application/settings_service.dart';
import '../domain/app_theme_choice.dart';

/// Kept exported from here: this screen was the original home of the shared
/// policy caption, and other screens import it from this library.
export '../../../app/policy_copy.dart' show policyCaption;

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
    final themeChoice = ref.watch(themeChoiceProvider);
    final lastBackup = ref.watch(lastBackupProvider);
    final showBackupNudge =
        lastBackup.hasValue && lastBackup.valueOrNull == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            padding: const EdgeInsets.fromLTRB(
              Space.l,
              Space.l,
              Space.l,
              Space.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showBackupNudge) ...[
                  WarningBanner(
                    message:
                        "You haven't saved a backup yet. One encrypted file "
                        'protects everything in this workspace.',
                    actionLabel: 'Back up now',
                    onAction: () => context.push('/settings/backup'),
                  ),
                ],

                const SectionHeader('Workspace'),
                _Group(
                  children: [
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
                      title: const Text('How much extra to bring'),
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
                                  (s) => s.updatePreferences(
                                    defaultPolicy: policy,
                                  ),
                                );
                              }
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: const Text('What you count (people, plates…)'),
                      subtitle: Text(workspace?.exposureLabel ?? '—'),
                      onTap: workspace == null
                          ? null
                          : () async {
                              final label = await _promptText(
                                context,
                                title: 'What you count',
                                initial: workspace.exposureLabel,
                                helper:
                                    'Your word for how many people you are '
                                    'planning for — "attendance", "covers", '
                                    '"orders".',
                              );
                              if (label != null && label.isNotEmpty) {
                                if (!context.mounted) return;
                                await _save(
                                  context,
                                  ref,
                                  (s) =>
                                      s.updatePreferences(exposureLabel: label),
                                );
                              }
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.history_toggle_off),
                      title: const Text('How far back to look'),
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
                                  (s) => s.updatePreferences(
                                    historyWindow: window,
                                  ),
                                );
                              }
                            },
                    ),
                  ],
                ),

                const SizedBox(height: Space.m),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Loadout's data is encrypted on this device. "
                                "Protect it with your phone's screen lock.",
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: Space.xs),
                              Text(
                                'Nothing is uploaded, ever.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SectionHeader('Appearance'),
                RadioGroup<AppThemeChoice>(
                  groupValue: themeChoice,
                  onChanged: (choice) async {
                    if (choice == null) return;
                    await _save(context, ref, (s) => s.setThemeMode(choice));
                  },
                  child: _Group(
                    children: [
                      for (final choice in AppThemeChoice.values)
                        RadioListTile<AppThemeChoice>(
                          value: choice,
                          selected: choice == themeChoice,
                          title: Text(choice.displayName),
                          subtitle: choice == AppThemeChoice.system
                              ? const Text(
                                  "Match the phone's own light or dark setting",
                                )
                              : null,
                        ),
                    ],
                  ),
                ),

                const SectionHeader('Data'),
                _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.save_outlined),
                      title: const Text('Back up'),
                      subtitle: const Text(
                        'Save everything as one encrypted file',
                      ),
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
                    ListTile(
                      leading: const Icon(Icons.table_chart_outlined),
                      title: const Text('Export a spreadsheet'),
                      subtitle: const Text(
                        'Save your lists as files Excel can open',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/export'),
                    ),
                  ],
                ),

                const SectionHeader('App'),
                _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Privacy'),
                      subtitle: const Text('What stays on this phone, and why'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/privacy'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Diagnostics'),
                      subtitle: const Text(
                        'Content-free log of what the app did',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/diagnostics'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('About'),
                      subtitle: const Text(
                        'Version, forecast method, licences',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/about'),
                    ),
                  ],
                ),

                SectionHeader('Danger zone', color: theme.colorScheme.error),
                _Group(
                  borderColor: theme.colorScheme.error.withValues(alpha: 0.4),
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Reset workspace',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.error,
                        ),
                      ),
                      subtitle: const Text(
                        'Archive the encrypted data and start over',
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.error,
                      ),
                      onTap: () => context.push('/settings/reset'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One settings group: rows in a single outlined card, hairline-separated.
class _Group extends StatelessWidget {
  const _Group({required this.children, this.borderColor});

  final List<Widget> children;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: borderColor ?? scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: Space.l),
            children[i],
          ],
        ],
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
      title: 'How far back to look',
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
    title: const Text('How much extra to bring'),
    children: [
      for (final policy in PlanningPolicy.values)
        ListTile(
          leading: Icon(
            policy == current
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          title: Text(policyCaption(policy)),
          subtitle: Text(policyBlurb(policy)),
          selected: policy == current,
          onTap: () => Navigator.of(dialogContext).pop(policy),
        ),
    ],
  ),
);
