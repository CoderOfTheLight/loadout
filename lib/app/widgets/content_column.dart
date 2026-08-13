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
      child: Padding(
        // Reserve the software keyboard's height at the bottom so whatever
        // sits at the end of a form — nearly always the button that saves
        // it — can still be scrolled into view while typing. Without this
        // the keyboard simply covers it and there is nothing left to
        // scroll.
        padding: padding.add(
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        ),
        child: child,
      ),
    ),
  );
}
