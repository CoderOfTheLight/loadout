/// Shared amber warning banner (design §9: staleness banner, negative
/// on-hand, receipt warnings). Icon + text — meaning never color-only.
/// Warnings never block.
///
/// Painted with the semantic [StatusColors] amber pair (design-spec §5):
/// the ONE amber in the app's state grammar — neutral, amber, red, green —
/// so every warning surface reads as the same word in the same voice. The
/// contrast tests in `theme_test.dart` measure the pair in both
/// brightnesses.
///
/// The action sits on its own row under the message rather than beside it:
/// side by side, a two-word button and a full sentence overflow each other
/// as soon as the system text scale goes up on a narrow phone.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class WarningBanner extends StatelessWidget {
  const WarningBanner({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    return Material(
      color: status.warning,
      borderRadius: BorderRadius.circular(Radii.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.l,
          vertical: Space.m,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: status.onWarning),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: status.onWarning,
                    ),
                  ),
                ),
              ],
            ),
            if (actionLabel != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: status.onWarning,
                  ),
                  child: Text(actionLabel!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
