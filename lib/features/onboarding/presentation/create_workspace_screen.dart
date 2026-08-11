/// `/welcome/create` (design §9): create the single local workspace.
///
/// Opens the encrypted database on first use
/// ([StartupService.createFreshWorkspace] — key generation invisible), then
/// runs [SettingsService.createWorkspace]; the router redirect flips to
/// `/home` when the workspace becomes visible. Errors surface as a
/// content-free full-width card with retry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../infrastructure/startup/startup_service.dart';
import '../../forecasting/domain/forecast_engine.dart';

class CreateWorkspaceScreen extends ConsumerStatefulWidget {
  const CreateWorkspaceScreen({super.key});

  @override
  ConsumerState<CreateWorkspaceScreen> createState() =>
      _CreateWorkspaceScreenState();
}

class _CreateWorkspaceScreenState extends ConsumerState<CreateWorkspaceScreen> {
  final _name = TextEditingController(text: 'My workspace');
  final _exposureLabel = TextEditingController(text: 'attendance');
  PlanningPolicy _policy = PlanningPolicy.balanced;
  bool _submitting = false;
  bool _failed = false;

  @override
  void dispose() {
    _name.dispose();
    _exposureLabel.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _submitting = true;
      _failed = false;
    });
    try {
      final startup = ref.read(startupServiceProvider);
      // Resumed create (app closed between open and naming) reuses the
      // already-open database instead of refusing to create over it.
      final db = startup.isOpen
          ? startup.database
          : await startup.createFreshWorkspace();
      ref.read(startupStateProvider.notifier).state = StartupWorkspaceOpen(db);
      final settings = ref.read(settingsServiceProvider);
      final label = _exposureLabel.text.trim();
      if (label.isNotEmpty && label != 'attendance') {
        await settings.updatePreferences(exposureLabel: label);
      }
      final name = _name.text.trim();
      await settings.createWorkspace(
        name: name.isEmpty ? 'My workspace' : name,
        defaultPolicy: _policy,
      );
      // The workspaceProvider emission bumps the router's refreshListenable;
      // the redirect moves this route to /home. Nothing to navigate here.
    } catch (_) {
      // Content-free by design (§10): no exception text reaches the UI.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create workspace')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_failed) ...[
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "The workspace couldn't be created. Nothing was "
                            'saved.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _submitting ? null : _create,
                              child: const Text('Try again'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Workspace name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Default planning policy',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<PlanningPolicy>(
                  segments: [
                    for (final policy in PlanningPolicy.values)
                      ButtonSegment(
                        value: policy,
                        label: Text(
                          '${_policyLabel(policy)}\n'
                          '+${policy.reservePercent} % reserve',
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                  selected: {_policy},
                  onSelectionChanged: (selection) =>
                      setState(() => _policy = selection.first),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _exposureLabel,
                  decoration: const InputDecoration(
                    labelText: 'What do you plan against?',
                    helperText:
                        'The word Loadout uses for expected crowd size — '
                        '"attendance", "covers", "orders".',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text(
                      "Loadout's data is encrypted on this device. Protect it "
                      "with your phone's screen lock.",
                    ),
                    subtitle: const Text('Nothing is uploaded, ever.'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth),
            child: FilledButton(
              onPressed: _submitting ? null : _create,
              style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
              child: _submitting
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Create workspace'),
            ),
          ),
        ),
      ),
    );
  }

  static String _policyLabel(PlanningPolicy policy) => switch (policy) {
    PlanningPolicy.lean => 'Lean',
    PlanningPolicy.balanced => 'Balanced',
    PlanningPolicy.cautious => 'Cautious',
  };
}
