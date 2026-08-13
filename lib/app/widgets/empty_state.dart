/// Shared empty-state scaffolding (design §9: every list/detail screen has
/// a specified empty state with a message and often one action).
///
/// The icon sits in a tinted disc rather than floating loose, the message
/// can carry a short [title] above it, and a [secondaryLabel] gives screens
/// a second way forward without inventing their own layout. The original
/// `message` / `icon` / `actionLabel` / `onAction` API is unchanged, so
/// every existing caller keeps working — including the `const` ones.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.inventory_2_outlined,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  /// The sentence that explains the emptiness. Always present.
  final String message;

  /// Optional short line above [message], for screens where the emptiness
  /// deserves a heading rather than only an explanation.
  final String? title;

  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      // Scrollable, not just centered: an empty state with a title, a
      // sentence and two buttons is taller than a short screen at a large
      // system text size, and centring alone would overflow it.
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.xxl,
              vertical: Space.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(Space.l),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 30,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: Space.xl),
                if (title != null) ...[
                  Text(
                    title!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: Space.s),
                ],
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: Space.xl),
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                    ),
                    child: Text(actionLabel!, textAlign: TextAlign.center),
                  ),
                ],
                if (secondaryLabel != null) ...[
                  const SizedBox(height: Space.m),
                  OutlinedButton(
                    onPressed: onSecondary,
                    style: OutlinedButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                    ),
                    child: Text(secondaryLabel!, textAlign: TextAlign.center),
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
