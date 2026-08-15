/// Folder identity vocabulary (design-spec §3): the eight named hues and the
/// curated icon-name grid, plus the effective-default rules for rows that
/// never chose (v3 rows ride the v4 ALTER with NULLs).
///
/// This lives in core/ like [ItemUnit] does: the DB seed, the domain entity,
/// the command validator, and the theme all read the same table, and data/
/// must not import features/. Colors are deliberately absent — the eight
/// SEEDS and the derived (tint, ink) pairs are theme concerns
/// (`FolderPalette` in `lib/app/theme.dart`); here live only names.
library;

/// The eight named hues, in the spec's table order. NOT a free color picker:
/// eight named, derivation-safe hues or the palette stops being a system
/// (Square's bounded-palette rule). Past eight folders, hues repeat —
/// identity is always color + icon + name together, so repetition is safe.
enum FolderHue {
  fern('fern', 'Fern'),
  lake('lake', 'Lake'),
  plum('plum', 'Plum'),
  berry('berry', 'Berry'),
  clay('clay', 'Clay'),
  honey('honey', 'Honey'),
  olive('olive', 'Olive'),
  stone('stone', 'Stone');

  const FolderHue(this.dbValue, this.displayName);

  /// The stored string (`folders.hue_name`), CHECK-enforced in SQL.
  final String dbValue;

  /// The name shown in the folder editor's swatch row.
  final String displayName;

  static FolderHue fromDb(String value) => values.firstWhere(
    (hue) => hue.dbValue == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'not a folder hue'),
  );

  static FolderHue? fromDbNullable(String? value) =>
      value == null ? null : fromDb(value);

  /// THE effective-hue rule for a folder that never chose (`hue_name` NULL):
  /// assign by position order, wrapping past eight.
  static FolderHue byPosition(int position) => values[position % values.length];
}

/// The next hue for a brand-new folder: the first table-order hue no live
/// folder is using, wrapping to plain rotation once all eight are taken.
/// [effectiveHuesInUse] is every live folder's EFFECTIVE hue.
FolderHue nextUnusedFolderHue(Iterable<FolderHue> effectiveHuesInUse) {
  final used = effectiveHuesInUse.toSet();
  for (final hue in FolderHue.values) {
    if (!used.contains(hue)) return hue;
  }
  return FolderHue.values[effectiveHuesInUse.length % FolderHue.values.length];
}

/// The curated ~32-glyph grid (recognition over choice), kitchen-heavy, in
/// display order. Names are Material glyph names; `folderIconChoices` in
/// `lib/app/widgets/folder_chip.dart` maps each to its IconData and a test
/// pins the two lists together. The validator accepts exactly this list.
const List<String> folderIconNames = [
  'lunch_dining',
  'bakery_dining',
  'ramen_dining',
  'set_meal',
  'kebab_dining',
  'local_pizza',
  'icecream',
  'cake',
  'egg',
  'eco',
  'grain',
  'rice_bowl',
  'fastfood',
  'outdoor_grill',
  'soup_kitchen',
  'kitchen',
  'blender',
  'flatware',
  'restaurant',
  'takeout_dining',
  'coffee',
  'local_drink',
  'liquor',
  'water_drop',
  'emoji_food_beverage',
  'storefront',
  'sell',
  'album',
  'menu_book',
  'shopping_basket',
  'cleaning_services',
  'inventory_2',
];

/// The icon a folder with no stored choice and no starter name falls back to.
const String fallbackFolderIconName = 'inventory_2';

/// The owner-approved starter set (lead reconciliation over spec §3): each of
/// the eight hues used exactly once. Seeded on workspace creation; also the
/// source of the effective-icon default for a NULL `icon_name` on a folder
/// that happens to carry a starter name (a migrated workspace's tidy-up
/// folders get the same identity the seed would have given them).
const Map<String, ({FolderHue hue, String iconName})> starterFolderAppearance =
    {
      'Cooked on site': (hue: FolderHue.clay, iconName: 'outdoor_grill'),
      'Bought ready to serve': (
        hue: FolderHue.honey,
        iconName: 'takeout_dining',
      ),
      'Fresh produce': (hue: FolderHue.fern, iconName: 'eco'),
      'Bakery': (hue: FolderHue.berry, iconName: 'bakery_dining'),
      'Drinks': (hue: FolderHue.lake, iconName: 'local_drink'),
      'Disposables': (hue: FolderHue.stone, iconName: 'flatware'),
      'Cleaning & setup': (hue: FolderHue.olive, iconName: 'cleaning_services'),
      'Sales table': (hue: FolderHue.plum, iconName: 'storefront'),
    };

final Map<String, String> _starterIconByLowerName = {
  for (final entry in starterFolderAppearance.entries)
    entry.key.toLowerCase(): entry.value.iconName,
};

/// THE effective-icon rule for a folder that never chose (`icon_name` NULL):
/// the reconciliation table's icon when the name is a starter name
/// (case-insensitively — folders are renameable), [fallbackFolderIconName]
/// otherwise.
String defaultFolderIconName(String folderName) =>
    _starterIconByLowerName[folderName.trim().toLowerCase()] ??
    fallbackFolderIconName;
