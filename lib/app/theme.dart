/// Visual language (design §9): Material 3, `ColorScheme.fromSeed(0xff356859)`,
/// light + dark with `ThemeMode.system`, content columns `maxWidth: 640`,
/// primary buttons at least 56 dp tall.
///
/// This file is the whole design system. The audience is someone standing at
/// a stall with a queue in front of them, holding the phone in one hand,
/// often in daylight — so the rules are:
///
///  * **Warm paper, not developer grey.** `ColorScheme.fromSeed` gives a
///    cool, faintly blue neutral ramp. Every surface token is re-pinned to a
///    warm off-white (light) / warm charcoal (dark) ramp so cards read as
///    stacked paper rather than as UI chrome. The seed and every accent
///    role stay exactly as M3 derived them.
///  * **Hierarchy from weight and tracking, not from size alone.** Titles
///    are semibold and slightly tight; body text is a notch larger than
///    Material's default for daylight legibility; `titleSmall` is the
///    small, wide-tracked "eyebrow" used for section labels.
///  * **Flat, outlined cards.** Elevation shadows disappear in sunlight; a
///    1 dp `outlineVariant` hairline does not.
///  * **Big targets.** Every button carries a >= 48 dp minimum, primary
///    actions >= 56 dp, and every `ListTile` a 56 dp floor.
library;

import 'package:flutter/material.dart';

import '../core/folder_appearance.dart';

/// Seed for both brightnesses (design §9).
const Color loadoutSeedColor = Color(0xff356859);

/// Content column width cap shared by every screen (design §9).
const double contentMaxWidth = 640;

/// Minimum size for primary action buttons (design §9: primary >= 56 dp).
const Size primaryButtonMinSize = Size.fromHeight(56);

/// The spacing scale. Screens compose from these instead of ad-hoc numbers
/// so rhythm survives being edited by six different hands.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. One family: cards 16, controls 14, small chips 12.
abstract final class Radii {
  static const double card = 16;
  static const double control = 14;
  static const double small = 12;
}

/// Numerals are a first-class role (design-spec §5): anywhere a quantity or
/// count is read at arm's length it is set in one of exactly three styles,
/// always tabular so columns align and ticking counts don't jitter.
abstract final class Numerals {
  /// Quantities and counts: lining, equal-width digits so columns align
  /// and ticking counts don't jitter.
  static const tabular = [FontFeature.tabularFigures()];

  /// Row quantity — the trailing count on a data row (item rows, activity):
  /// `titleLarge` at w600. 16 pt numerals fail the arm's-length glance;
  /// 20 clears the older-adult floor with margin.
  static TextStyle? rowQuantity(TextTheme text) => text.titleLarge?.copyWith(
    fontWeight: FontWeight.w600,
    fontFeatures: tabular,
  );

  /// Glance number — a scaled recipe quantity, the closeout fraction:
  /// `headlineSmall` at w600 (the 22 pt touchscreen-glance figure).
  static TextStyle? glance(TextTheme text) => text.headlineSmall?.copyWith(
    fontWeight: FontWeight.w600,
    fontFeatures: tabular,
  );

  /// Hero number — the Home lead tile's one big figure: `displaySmall` at
  /// w700. At most one per screen.
  static TextStyle? hero(TextTheme text) => text.displaySmall?.copyWith(
    fontWeight: FontWeight.w700,
    fontFeatures: tabular,
  );
}

/// Warm neutral ramp for light mode — paper, not printer paper.
const _lightSurfaces = _Surfaces(
  surface: Color(0xFFFBF8F2),
  lowest: Color(0xFFFFFFFF),
  low: Color(0xFFF6F2E9),
  container: Color(0xFFF1ECE2),
  high: Color(0xFFEAE5DA),
  highest: Color(0xFFE3DDD1),
  outlineVariant: Color(0xFFD4CEC2),
);

/// Warm charcoal ramp for dark mode — a hair green, never blue.
const _darkSurfaces = _Surfaces(
  surface: Color(0xFF141613),
  lowest: Color(0xFF0E100D),
  low: Color(0xFF1A1C18),
  container: Color(0xFF1E211D),
  high: Color(0xFF292C27),
  highest: Color(0xFF343831),
  outlineVariant: Color(0xFF434941),
);

final class _Surfaces {
  const _Surfaces({
    required this.surface,
    required this.lowest,
    required this.low,
    required this.container,
    required this.high,
    required this.highest,
    required this.outlineVariant,
  });

  final Color surface;
  final Color lowest;
  final Color low;
  final Color container;
  final Color high;
  final Color highest;
  final Color outlineVariant;
}

/// M3 tonal palette from the seed, with the neutral ramp re-pinned warm.
/// Accent roles (primary/secondary/tertiary/error and their containers) are
/// untouched, so contrast stays exactly as Material computed it.
ColorScheme loadoutColorScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: loadoutSeedColor,
    brightness: brightness,
  );
  final ramp = brightness == Brightness.light ? _lightSurfaces : _darkSurfaces;
  return base.copyWith(
    surface: ramp.surface,
    surfaceContainerLowest: ramp.lowest,
    surfaceContainerLow: ramp.low,
    surfaceContainer: ramp.container,
    surfaceContainerHigh: ramp.high,
    surfaceContainerHighest: ramp.highest,
    outlineVariant: ramp.outlineVariant,
  );
}

/// The type scale. Sizes stay close to Material's so nothing clips at 200 %
/// scale; the hierarchy comes from weight, tracking and line height.
TextTheme _loadoutTextTheme(TextTheme base) => base.copyWith(
  displaySmall: base.displaySmall?.copyWith(
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
  ),
  headlineLarge: base.headlineLarge?.copyWith(
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  ),
  headlineMedium: base.headlineMedium?.copyWith(
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  ),
  headlineSmall: base.headlineSmall?.copyWith(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  ),
  titleLarge: base.titleLarge?.copyWith(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  ),
  titleMedium: base.titleMedium?.copyWith(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  ),
  // The "eyebrow": small, wide, bold. Section labels only — all-caps is
  // acceptable ONLY because eyebrows are 1-3 words; never extend uppercase
  // to titles or buttons (NIA warns against caps for emphasis).
  titleSmall: base.titleSmall?.copyWith(
    fontSize: 13.5,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.7,
  ),
  bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
  bodyMedium: base.bodyMedium?.copyWith(fontSize: 14.5, height: 1.45),
  // Captions that merely repeat information ONLY — never the sole carrier
  // of meaning: 13 sits below the 13-14.5 pt older-adult reading floor.
  bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.4),
  labelLarge: base.labelLarge?.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  ),
  labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
  labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600),
);

// ----------------------------------------------------------- folder palette

/// The eight hue SEEDS (design-spec §3), tuned to sit with the app seed on
/// warm paper. Indexed by [FolderHue] table order. Seeds, not final colors:
/// the shipped (tint, ink) pairs are derived from these per brightness.
const Map<FolderHue, Color> folderHueSeeds = {
  FolderHue.fern: Color(0xFF356859),
  FolderHue.lake: Color(0xFF31628D),
  FolderHue.plum: Color(0xFF7A4E7E),
  FolderHue.berry: Color(0xFF95455C),
  FolderHue.clay: Color(0xFF9A4F2E),
  FolderHue.honey: Color(0xFF8A6C1F),
  FolderHue.olive: Color(0xFF6D7239),
  FolderHue.stone: Color(0xFF6E6459),
};

/// One folder hue's shipped pair: [tint] fills the chip, [ink] draws the
/// icon on it. Derived, never hand-tuned, so contrast holds by construction.
@immutable
final class FolderColors {
  const FolderColors({required this.tint, required this.ink});

  final Color tint;
  final Color ink;
}

/// The eight precomputed (tint, ink) pairs, derived ONCE at theme build via
/// `ColorScheme.fromSeed(seed).primaryContainer / onPrimaryContainer` —
/// M3's tonal construction carries the WCAG contrast the repo's theme tests
/// measure, in both brightnesses. Widgets read `FolderPalette.of(context)`
/// (or `Theme.of(context).extension<FolderPalette>()`) and never derive.
@immutable
final class FolderPalette extends ThemeExtension<FolderPalette> {
  const FolderPalette._(this._pairs);

  /// Derives all eight pairs for [brightness]. Called once per theme build.
  factory FolderPalette.derive(Brightness brightness) => FolderPalette._([
    for (final hue in FolderHue.values)
      _pairFromSeed(folderHueSeeds[hue]!, brightness),
  ]);

  static FolderColors _pairFromSeed(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return FolderColors(
      tint: scheme.primaryContainer,
      ink: scheme.onPrimaryContainer,
    );
  }

  /// Indexed by [FolderHue.index]; always exactly eight entries.
  final List<FolderColors> _pairs;

  /// The pair for [hue] — pass a folder's `effectiveHue`.
  FolderColors pair(FolderHue hue) => _pairs[hue.index];

  /// Convenience for widgets: the palette on the ambient theme.
  static FolderPalette of(BuildContext context) =>
      Theme.of(context).extension<FolderPalette>()!;

  @override
  FolderPalette copyWith({List<FolderColors>? pairs}) =>
      FolderPalette._(pairs ?? _pairs);

  @override
  FolderPalette lerp(ThemeExtension<FolderPalette>? other, double t) {
    if (other is! FolderPalette) return this;
    return FolderPalette._([
      for (var i = 0; i < _pairs.length; i++)
        FolderColors(
          tint: Color.lerp(_pairs[i].tint, other._pairs[i].tint, t)!,
          ink: Color.lerp(_pairs[i].ink, other._pairs[i].ink, t)!,
        ),
    ]);
  }
}

// ------------------------------------------------------------ status colors

/// Seed for the amber "warning" status pair (design-spec §5): the one hue in
/// the state grammar the M3 scheme does not already carry.
const Color statusWarningSeed = Color(0xFF9A6A00);

/// Semantic status tokens (design-spec §5): the amber warning container
/// pair, derived by the same §3 method as the folder palette. This completes
/// the state vocabulary — neutral, amber, red (`ColorScheme.error`), green
/// (the scheme's own primary/primaryContainer) — never a fifth.
@immutable
final class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.warning, required this.onWarning});

  factory StatusColors.derive(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: statusWarningSeed,
      brightness: brightness,
    );
    return StatusColors(
      warning: scheme.primaryContainer,
      onWarning: scheme.onPrimaryContainer,
    );
  }

  /// Amber container fill for "due soon" / "doesn't add up" surfaces.
  final Color warning;

  /// Ink that reads on [warning].
  final Color onWarning;

  /// Convenience for widgets: the tokens on the ambient theme.
  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>()!;

  @override
  StatusColors copyWith({Color? warning, Color? onWarning}) => StatusColors(
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
  );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
    );
  }
}

ThemeData loadoutTheme(Brightness brightness) {
  final scheme = loadoutColorScheme(brightness);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    // Phone-shaped everywhere, including the desktop host that runs tests.
    visualDensity: VisualDensity.standard,
  );
  final text = _loadoutTextTheme(base.textTheme);
  final hairline = BorderSide(color: scheme.outlineVariant);

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,

    // Precomputed per brightness so widgets never derive at build time.
    extensions: <ThemeExtension<dynamic>>[
      FolderPalette.derive(brightness),
      StatusColors.derive(brightness),
    ],

    // App bar: flat, on the page's own surface, separated by a hairline
    // instead of a shadow that vanishes outdoors.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: Space.l,
      shape: Border(bottom: hairline),
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
    ),

    // Cards are the primary content container: flat, outlined, warm.
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: hairline,
      ),
    ),

    listTileTheme: ListTileThemeData(
      // One-thumb target floor everywhere, without each screen asking.
      minTileHeight: 56,
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: text.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xl,
          vertical: Space.m,
        ),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xl,
          vertical: Space.m,
        ),
        textStyle: text.labelLarge,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small),
        ),
      ),
    ),

    // Only `filled`, `fillColor` and the default `border` are themed: many
    // forms pass their own `border`, and theming the per-state borders too
    // would make those fields change shape on focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      helperMaxLines: 3,
      errorMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.small),
        borderSide: BorderSide(color: scheme.outline),
      ),
      labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelSmall?.copyWith(
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      side: hairline,
      labelStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small),
      ),
    ),

    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: hairline,
      ),
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHigh,
    ),
  );
}
