/// The Unfiled identity chip: the same tinted-square language as
/// [FolderChip], in neutral — `surfaceContainerHigh` under an inbox glyph in
/// `onSurfaceVariant` — because Unfiled is a real place items live, not a
/// folder. It marks unfiled item rows in the sectioned list, the fixed
/// Unfiled row in folder management, and anywhere an unfiled item shows its
/// (non-)folder outside its own section.
///
/// Like [FolderChip] it is decorative beside a name and excluded from
/// semantics; the word "Unfiled" always carries the meaning.
library;

import 'package:flutter/material.dart';

import '../../../app/widgets/folder_chip.dart';

class UnfiledChip extends StatelessWidget {
  const UnfiledChip({super.key, this.size = FolderChipSize.large});

  final FolderChipSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size.box,
        height: size.box,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(size.radius),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.inbox_outlined,
          size: size.icon,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
