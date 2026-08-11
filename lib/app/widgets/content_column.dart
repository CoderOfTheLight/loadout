/// Shared content column (design §9: content columns `maxWidth: 640`).
/// Wrap a screen body in this to get the centered, width-capped, padded
/// column every Loadout screen uses.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: contentMaxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}
