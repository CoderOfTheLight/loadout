/// `/settings/privacy` (design §9, §10): static explainer — no accounts, no
/// cloud, no analytics, no network permission (CI-enforced); encryption at
/// rest; what a backup contains; content-free diagnostics.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy')),
    body: SafeArea(
      child: SingleChildScrollView(
        child: ContentColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              _PrivacySection(
                icon: Icons.cloud_off_outlined,
                title: 'No accounts, no cloud, no analytics',
                body:
                    'Loadout works entirely on this device. There is no '
                    'sign-in, no sync, and no tracking of any kind. The app '
                    'ships without network permission, so it cannot send '
                    'anything anywhere — and an automated release check '
                    'enforces that.',
              ),
              _PrivacySection(
                icon: Icons.lock_outline,
                title: 'Encrypted at rest',
                body:
                    'Everything you enter is stored in a single encrypted '
                    'database on this device. The encryption key lives in '
                    "the device's secure storage, never appears in any "
                    'file or log, and never leaves this device.',
              ),
              _PrivacySection(
                icon: Icons.save_outlined,
                title: 'What leaves this device',
                body:
                    'Nothing — except backup files you explicitly save '
                    'through the save dialog. A backup is one encrypted '
                    'file protected by a passphrase you choose; without '
                    'that passphrase it cannot be read. There is no share '
                    'sheet and no automatic upload.',
              ),
              _PrivacySection(
                icon: Icons.receipt_long_outlined,
                title: 'Diagnostics are content-free',
                body:
                    'Diagnostic lines carry timestamps, event codes, and '
                    'numbers only. Item names, quantities, event names, and '
                    'notes physically cannot appear in them. Logs stay on '
                    'this device unless you export them yourself from the '
                    'Diagnostics screen.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(Space.s),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: Space.m),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
