/// Pinned bottom bar for a screen's primary action.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Holds the button that completes a form, pinned to the bottom of the
/// screen and — critically — kept above the software keyboard.
///
/// Flutter's `Scaffold.resizeToAvoidBottomInset` moves the BODY out of the
/// keyboard's way but leaves `bottomNavigationBar` where it is, so a save
/// button placed there is simply covered while typing, with no scrolling
/// that can reach it. Padding by the view inset lifts the whole bar above
/// the keyboard instead.
class FormActionBar extends StatelessWidget {
  const FormActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
    elevation: 3,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        // heightFactor keeps the bar as short as its content; a bare Align
        // takes every pixel the Scaffold offers it.
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth),
            child: child,
          ),
        ),
      ),
    ),
  );
}
