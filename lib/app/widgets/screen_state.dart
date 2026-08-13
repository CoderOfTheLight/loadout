/// Designed loading and error states (design §9 cross-cutting UX).
///
/// A bare `CircularProgressIndicator` and a bare error sentence are the two
/// places an otherwise-considered app looks unfinished. Both states here get
/// the same content column, the same rhythm, and — for errors — a way out.
/// Error copy stays content-free (§10): no exception text ever reaches the
/// screen.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  /// Optional line under the spinner. Omit it for waits under a second.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            width: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: Space.l),
            Text(
              label!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.retryLabel = 'Try again',
    this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      // Same reasoning as EmptyState: never overflow a short screen.
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
                    color: theme.colorScheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    size: 28,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: Space.l),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: Space.xl),
                  OutlinedButton(
                    onPressed: onRetry,
                    child: Text(retryLabel, textAlign: TextAlign.center),
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
