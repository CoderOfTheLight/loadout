/// The one section label used across Loadout: a small wide-tracked eyebrow
/// with an optional trailing action ("See all").
///
/// Screens got their hierarchy from ad-hoc `titleSmall` Texts before, which
/// drifted in padding and colour. This is the single shape.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.color,
    this.padding = const EdgeInsets.fromLTRB(4, Space.xl, 4, Space.s),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Overrides the label colour — the danger zone uses `error`.
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.titleSmall?.copyWith(
                color: color ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
