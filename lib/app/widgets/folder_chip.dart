/// The folder identity chip (design-spec §3): ONE widget, two sizes, used
/// everywhere a folder appears — item rows, section headers, jump chips, the
/// picker, folder management. A tinted rounded square with the folder's icon
/// in the folder's ink; the repetition of the same chip across screens is
/// what makes the app feel organized.
///
/// Color appears ONLY on this chip and on selected-state tints — never as a
/// row background, never as a header fill. Identity is always color + icon +
/// name together; the chip is decorative beside the name and is excluded
/// from semantics.
library;

import 'package:flutter/material.dart';

import '../../core/folder_appearance.dart';
import '../theme.dart';
import '../../features/catalog/domain/folder.dart';

/// The two sanctioned chip sizes; nothing in between.
enum FolderChipSize {
  /// 40 dp, icon 22, radius [Radii.small] — item rows' leading slot,
  /// folder-management rows, event-detail groupings, editor previews.
  large(box: 40, icon: 22, radius: Radii.small),

  /// 24 dp, icon 14, radius 8 — section headers, jump chips, breadcrumbs,
  /// picker headers.
  small(box: 24, icon: 14, radius: 8);

  const FolderChipSize({
    required this.box,
    required this.icon,
    required this.radius,
  });

  final double box;
  final double icon;
  final double radius;
}

class FolderChip extends StatelessWidget {
  const FolderChip({
    super.key,
    required this.hue,
    required this.iconName,
    this.size = FolderChipSize.large,
  });

  /// The chip for a [Folder], using its effective hue and icon.
  FolderChip.forFolder(
    Folder folder, {
    super.key,
    this.size = FolderChipSize.large,
  }) : hue = folder.effectiveHue,
       iconName = folder.effectiveIconName;

  final FolderHue hue;
  final String iconName;
  final FolderChipSize size;

  @override
  Widget build(BuildContext context) {
    final colors = FolderPalette.of(context).pair(hue);
    return ExcludeSemantics(
      child: Container(
        width: size.box,
        height: size.box,
        decoration: BoxDecoration(
          color: colors.tint,
          borderRadius: BorderRadius.circular(size.radius),
        ),
        alignment: Alignment.center,
        child: Icon(
          folderIconData(iconName),
          size: size.icon,
          color: colors.ink,
        ),
      ),
    );
  }
}

/// One cell of the folder editor's icon grid.
typedef FolderIconChoice = ({String name, IconData icon});

/// The curated grid (spec §3), in display order: rows of food, kitchen,
/// sales, and generic glyphs. Names mirror [folderIconNames] exactly — a
/// theme test pins the two lists together so the validator and the renderer
/// can never drift apart.
const List<FolderIconChoice> folderIconChoices = [
  (name: 'lunch_dining', icon: Icons.lunch_dining),
  (name: 'bakery_dining', icon: Icons.bakery_dining),
  (name: 'ramen_dining', icon: Icons.ramen_dining),
  (name: 'set_meal', icon: Icons.set_meal),
  (name: 'kebab_dining', icon: Icons.kebab_dining),
  (name: 'local_pizza', icon: Icons.local_pizza),
  (name: 'icecream', icon: Icons.icecream),
  (name: 'cake', icon: Icons.cake),
  (name: 'egg', icon: Icons.egg),
  (name: 'eco', icon: Icons.eco),
  (name: 'grain', icon: Icons.grain),
  (name: 'rice_bowl', icon: Icons.rice_bowl),
  (name: 'fastfood', icon: Icons.fastfood),
  (name: 'outdoor_grill', icon: Icons.outdoor_grill),
  (name: 'soup_kitchen', icon: Icons.soup_kitchen),
  (name: 'kitchen', icon: Icons.kitchen),
  (name: 'blender', icon: Icons.blender),
  (name: 'flatware', icon: Icons.flatware),
  (name: 'restaurant', icon: Icons.restaurant),
  (name: 'takeout_dining', icon: Icons.takeout_dining),
  (name: 'coffee', icon: Icons.coffee),
  (name: 'local_drink', icon: Icons.local_drink),
  (name: 'liquor', icon: Icons.liquor),
  (name: 'water_drop', icon: Icons.water_drop),
  (name: 'emoji_food_beverage', icon: Icons.emoji_food_beverage),
  (name: 'storefront', icon: Icons.storefront),
  (name: 'sell', icon: Icons.sell),
  (name: 'album', icon: Icons.album),
  (name: 'menu_book', icon: Icons.menu_book),
  (name: 'shopping_basket', icon: Icons.shopping_basket),
  (name: 'cleaning_services', icon: Icons.cleaning_services),
  (name: 'inventory_2', icon: Icons.inventory_2),
];

/// The glyph for a stored icon name; unknown names fall back to
/// `inventory_2` so a chip can always draw (the validator refuses unknown
/// names on the way in, but stored data must never crash a build).
IconData folderIconData(String name) {
  for (final choice in folderIconChoices) {
    if (choice.name == name) return choice.icon;
  }
  return Icons.inventory_2;
}
