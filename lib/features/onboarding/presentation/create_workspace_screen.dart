/// `/welcome/create` (design §9): create the single local workspace.
///
/// Opens the encrypted database on first use
/// ([StartupService.createFreshWorkspace] — key generation invisible), then
/// runs [SettingsService.createWorkspace]; the router redirect flips to
/// `/home` when the workspace becomes visible. Errors surface as a
/// content-free full-width card with retry.
///
/// Owner feedback ("make the starting menus easier to handle") shaped what
/// this screen asks:
///
///  * two questions, both in plain words, both with a working default —
///    a name, and how much spare to take;
///  * the exposure label ("What do you plan against?") moved out entirely.
///    It is jargon at minute zero, it already has a sensible default, and
///    it is still editable in Settings the day she wants it;
///  * the policy control is three tappable rows instead of a
///    `SegmentedButton` of stacked two-line captions — those captions
///    crushed to two words per line on a narrow phone, and a row can carry
///    the sentence that says what the percentage means.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/policy_copy.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/form_action_bar.dart';
import '../../../infrastructure/startup/startup_service.dart';
import '../../forecasting/domain/forecast_engine.dart';

/// Prefilled name. Plain, and true for most of the people this is for.
const String defaultWorkspaceName = 'My stall';

class CreateWorkspaceScreen extends ConsumerStatefulWidget {
  const CreateWorkspaceScreen({super.key});

  @override
  ConsumerState<CreateWorkspaceScreen> createState() =>
      _CreateWorkspaceScreenState();
}

class _CreateWorkspaceScreenState extends ConsumerState<CreateWorkspaceScreen> {
  final _name = TextEditingController(text: defaultWorkspaceName);
  PlanningPolicy _policy = PlanningPolicy.balanced;
  bool _submitting = false;
  bool _failed = false;

  @override
  void dispose() {
    _name.dispose();
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
      final name = _name.text.trim();
      await settings.createWorkspace(
        name: name.isEmpty ? defaultWorkspaceName : name,
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
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_failed) ...[
                  Card(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "That didn't work. Nothing was saved — try again.",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onErrorContainer,
                            ),
                          ),
                          const SizedBox(height: Space.s),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                              onPressed: _submitting ? null : _create,
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.onErrorContainer,
                              ),
                              child: const Text('Try again'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.l),
                ],

                Text(
                  'What should we call this?',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Space.s),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: defaultWorkspaceName,
                    helperText: 'Only you see this. It names your backups too.',
                  ),
                ),

                const SizedBox(height: Space.xl),
                Text(
                  'How much spare do you like to take?',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'Loadout adds this on top of what it expects you to use. '
                  'You can change it later, and per event.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.m),
                for (final policy in PlanningPolicy.values) ...[
                  _PolicyOption(
                    policy: policy,
                    selected: policy == _policy,
                    onSelected: () => setState(() => _policy = policy),
                  ),
                  const SizedBox(height: Space.s),
                ],

                const SizedBox(height: Space.l),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline, color: scheme.primary),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Text(
                            'Your data is encrypted on this phone and never '
                            'uploaded. Keep a screen lock on and it stays '
                            'yours.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.l),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FormActionBar(
        child: FilledButton(
          onPressed: _submitting ? null : _create,
          style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
          child: _submitting
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Start', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// One tappable policy row. Not a `Radio`: the framework's radio API is
/// mid-migration to `RadioGroup`, and a row that carries a title, a
/// sentence and a reserve badge reads better standing up anyway.
class _PolicyOption extends StatelessWidget {
  const _PolicyOption({
    required this.policy,
    required this.selected,
    required this.onSelected,
  });

  final PlanningPolicy policy;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label:
          '${policyName(policy)}, plus ${policy.reservePercent} per cent '
          'reserve. ${policyBlurb(policy)}',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(Radii.control),
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${policyName(policy)}  ·  '
                        '+${policy.reservePercent} %',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        policyBlurb(policy),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
