/// `/welcome` (design §9): privacy-first value proposition. No commands.
///
/// Owner feedback: "make the starting menus easier to handle". So: one
/// promise, one sentence of how, one line about privacy, one button. Every
/// other word was cut. The column scrolls rather than centring rigidly, so
/// a large system text size on a small phone still reaches the button.
///
/// The sentence of how is proposal §4 verbatim: it has to make ALL of her
/// stuff feel welcome — the food she makes, the supplies she sets out, the
/// things she sells — before the app asks her for anything.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.xxl,
                      vertical: Space.xl,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: Container(
                            padding: const EdgeInsets.all(Space.xl),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              size: 40,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.xxl),
                        Text(
                          'Bring the right amount.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: Space.m),
                        Text(
                          'List what you bring — the food you make, the '
                          'supplies you set out, the things you sell — and '
                          'Loadout works out how much to take.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Space.xxl),
                        Semantics(
                          label: 'Get started and set up your workspace',
                          button: true,
                          child: FilledButton(
                            onPressed: () => context.go('/welcome/create'),
                            style: FilledButton.styleFrom(
                              minimumSize: primaryButtonMinSize,
                            ),
                            child: const Text(
                              'Get started',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.xl),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: Space.s),
                            Flexible(
                              child: Text(
                                'Everything stays on this phone. '
                                'Nothing is uploaded, ever.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
