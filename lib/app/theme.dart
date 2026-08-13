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
  // The "eyebrow": small, wide, bold. Section labels only.
  titleSmall: base.titleSmall?.copyWith(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.7,
  ),
  bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
  bodyMedium: base.bodyMedium?.copyWith(fontSize: 14.5, height: 1.45),
  bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.4),
  labelLarge: base.labelLarge?.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  ),
  labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
  labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600),
);

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
