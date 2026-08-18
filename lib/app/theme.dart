/// Visual language (design §9): Material 3, light + dark with
/// `ThemeMode.system`, content columns `maxWidth: 640`, primary buttons at
/// least 56 dp tall.
///
/// This file is the whole design system. The audience is someone standing at
/// a stall with a queue in front of them, holding the phone in one hand,
/// often in daylight — so the rules are:
///
///  * **Warm paper, not developer grey.** `ColorScheme.fromSeed` gives a
///    cool, faintly blue neutral ramp. Every surface AND every neutral
///    foreground is re-pinned to a warm off-white (light) / warm charcoal
///    (dark) ramp so cards read as stacked paper rather than as UI chrome.
///  * **One brand colour, and it is a working colour.** [loadoutBrandGreen]
///    is the only saturated colour the *app* owns: buttons, selection,
///    progress, links. Every other colour on screen belongs to the user's
///    data (the eight folder hues) or to state.
///  * **Colour means state before it means anything else.** Green =
///    counted/confirmed, amber = pending, red = short/destructive
///    ([StatusColors], a closed set of three). A hue that carries state is
///    never also decoration — that is why folders get their own eight hues
///    and why there is no fourth state colour to reach for.
///  * **Dark mode is its own system, not a tint of light.** The brand green
///    at #2F6B57 scores 1.6:1 on the dark ground — illegible. Dark gets a
///    hand-calibrated counterpart ([loadoutBrandGreenDark]) and so do amber,
///    red and every neutral foreground.
///  * **Hierarchy from weight and tracking, not from size alone.** Titles
///    are semibold and slightly tight; body text is a notch larger than
///    Material's default for daylight legibility; `titleSmall` is the
///    small, wide-tracked "eyebrow" used for section labels.
///  * **Numbers are the content.** [Numerals] is a three-tier scale — hero,
///    quantity, caption — always tabular. One hero figure per card.
///  * **Flat, outlined cards.** Elevation shadows disappear in sunlight; a
///    1 dp `outlineVariant` hairline does not.
///  * **Big targets.** Every button carries a >= 48 dp minimum, primary
///    actions >= 56 dp, and every `ListTile` a 56 dp floor.
///  * **Disabled still has to be readable.** Material's default disabled
///    label is `onSurface` at 38 % on a 12 % fill — 2.3:1, under the 3:1
///    floor for UI text. The ramp pins a disabled ink instead.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/folder_appearance.dart';

// ------------------------------------------------------- canonical palette

/// Palette direction "A · Warm Paper, finished". These five values are the
/// source of truth; everything else in this file is either derived from one
/// of them, a neutral from the warm ramp, or one of the eight folder hues.
/// A colour that is none of those does not exist in this app.

/// The page. Every light surface is this or one step off it.
const Color loadoutPaper = Color(0xFFFBF8F2);

/// Body ink — warm near-black, 16.2:1 on [loadoutPaper].
const Color loadoutInk = Color(0xFF191C18);

/// THE brand colour. One saturated green for every interactive affordance
/// (primary buttons, selection, progress, focus) and for nothing decorative.
/// 6.3:1 under white, 5.9:1 on paper.
const Color loadoutBrandGreen = Color(0xFF2F6B57);

/// The brand green re-cut for a near-black ground: #2F6B57 scores 1.6:1 on
/// the dark surface, so dark mode gets its own tone rather than a tint of
/// the light one. 10.3:1 on the dark surface.
const Color loadoutBrandGreenDark = Color(0xFF7FD3AF);

/// Pending / "not counted yet" / "doesn't add up". Reserved: see
/// [StatusColors].
const Color loadoutPendingAmber = Color(0xFFB8791B);

/// Short / critical / destructive. Reserved: see [StatusColors]; also the
/// scheme's `error`.
const Color loadoutDangerRed = Color(0xFFA33E36);

/// The seed handed to [ColorScheme.fromSeed] for the roles this file does
/// not pin by hand (secondary, tertiary, inverse, scrim, …). It is the brand
/// green itself, so the derived family stays in the brand's hue instead of
/// drifting off to the old seed's.
const Color loadoutSeedColor = loadoutBrandGreen;

/// Content column width cap shared by every screen (design §9).
const double contentMaxWidth = 640;

/// Minimum size for primary action buttons (design §9: primary >= 56 dp).
const Size primaryButtonMinSize = Size.fromHeight(56);

/// WCAG 2.2 contrast ratio between two opaque colours. The tint/ink
/// derivations below use it at theme-build time, so contrast is a
/// *construction* rather than a hope; `test/app/theme_test.dart` measures the
/// same ratio on the shipped values.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

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

/// Numerals are a first-class role (design-spec §5): this app's content IS
/// its numbers, so anywhere a quantity is read at arm's length it is set in
/// one of exactly THREE tiers, always tabular so columns align and ticking
/// counts don't jitter:
///
///  1. **Hero** — [hero], display scale at w700. The one answer a card or a
///     screen exists to give. At most one per screen.
///  2. **Quantity** — [rowQuantity] for the trailing figure on a data row,
///     [glance] for the same tier one step up when a figure is the subject
///     of its own block (a scaled recipe amount, the closeout fraction).
///  3. **Caption** — [caption], supporting figures that qualify a hero
///     ("of 24", "3 left") and never carry meaning alone.
///
/// Emphasis is carried by WEIGHT, not by a token: Material 3 Expressive's
/// principle is that weight, not size or colour, is what separates a figure
/// from its label — and since Flutter ships no M3E components, weight is the
/// part we can honour exactly.
abstract final class Numerals {
  /// Quantities and counts: lining, equal-width digits so columns align
  /// and ticking counts don't jitter. Every role below sets it; anything
  /// hand-styling a number sets it too.
  static const tabular = [FontFeature.tabularFigures()];

  /// TIER 3 — supporting figure: `bodySmall` at w600. Only ever beside a
  /// hero or a row quantity that already carries the meaning (13 pt sits on
  /// the older-adult reading floor, not above it).
  static TextStyle? caption(TextTheme text) => text.bodySmall?.copyWith(
    fontWeight: FontWeight.w600,
    fontFeatures: tabular,
  );

  /// TIER 2 — row quantity: the trailing count on a data row (item rows,
  /// activity), `titleLarge` at w600. 16 pt numerals fail the arm's-length
  /// glance; 20 clears the older-adult floor with margin.
  static TextStyle? rowQuantity(TextTheme text) => text.titleLarge?.copyWith(
    fontWeight: FontWeight.w600,
    fontFeatures: tabular,
  );

  /// TIER 2, raised — a figure that is the subject of its own block: a
  /// scaled recipe quantity, the closeout fraction. `headlineSmall` at w600
  /// (the 22 pt touchscreen-glance figure).
  static TextStyle? glance(TextTheme text) => text.headlineSmall?.copyWith(
    fontWeight: FontWeight.w600,
    fontFeatures: tabular,
  );

  /// TIER 1 — hero: the one big figure on a card or screen (`displaySmall`
  /// at w700). If a screen has two, one of them is not a hero.
  static TextStyle? hero(TextTheme text) => text.displaySmall?.copyWith(
    fontWeight: FontWeight.w700,
    fontFeatures: tabular,
  );
}

/// Warm neutral ramp for light mode — paper, not printer paper. Foregrounds
/// are pinned here too: `fromSeed` hands back cool blue-greys for
/// `onSurface`/`onSurfaceVariant`/`outline`, which read as grey UI chrome
/// sitting on top of warm paper rather than as ink printed on it.
const _lightSurfaces = _Surfaces(
  surface: loadoutPaper,
  lowest: Color(0xFFFFFFFF),
  low: Color(0xFFF6F2E9),
  container: Color(0xFFF1ECE2),
  high: Color(0xFFEAE5DA),
  highest: Color(0xFFE3DDD1),
  outlineVariant: Color(0xFFD4CEC2),
  ink: loadoutInk,
  inkMuted: Color(0xFF4A4E46),
  outline: Color(0xFF75786F),
  disabledInk: Color(0xFF5E6158),
);

/// Warm charcoal ramp for dark mode — a hair green, never blue. Hand
/// calibrated against the light ramp rather than lerped from it.
const _darkSurfaces = _Surfaces(
  surface: Color(0xFF141613),
  lowest: Color(0xFF0E100D),
  low: Color(0xFF1A1C18),
  container: Color(0xFF1E211D),
  high: Color(0xFF292C27),
  highest: Color(0xFF343831),
  outlineVariant: Color(0xFF434941),
  ink: Color(0xFFE7E3D9),
  inkMuted: Color(0xFFBDB8AC),
  outline: Color(0xFF8A857A),
  disabledInk: Color(0xFF9A9C93),
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
    required this.ink,
    required this.inkMuted,
    required this.outline,
    required this.disabledInk,
  });

  final Color surface;
  final Color lowest;
  final Color low;
  final Color container;
  final Color high;
  final Color highest;
  final Color outlineVariant;

  /// Body ink (`onSurface`).
  final Color ink;

  /// Secondary ink (`onSurfaceVariant`) — still >= 4.5:1 on every surface in
  /// the ramp, because this app puts real information in its second line.
  final Color inkMuted;

  /// Control edges (`outline`) — >= 3:1 on paper, the WCAG floor for the
  /// boundary of a UI component.
  final Color outline;

  /// Label ink for a disabled control. Material would paint `onSurface` at
  /// 38 % here, which lands at 2.3:1 (light) / 2.9:1 (dark) — under the 3:1
  /// floor. Disabledness is carried by the flat neutral FILL instead, so the
  /// label can stay readable.
  final Color disabledInk;

  /// Fill for a disabled control: a flat step of the neutral ramp, which is
  /// what makes it read as "off" beside a brand-green enabled button.
  Color get disabledFill => high;
}

/// The scheme: M3 tonal roles from the brand seed, with everything that
/// carries meaning pinned by hand — the neutral ramp, the brand, and the
/// danger red. `fromSeed` still supplies the long tail (secondary, tertiary,
/// inverse, scrim, surfaceVariant, …) so a role nobody has thought about yet
/// still has a sane value.
ColorScheme loadoutColorScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: loadoutSeedColor,
    brightness: brightness,
  );
  final light = brightness == Brightness.light;
  final ramp = light ? _lightSurfaces : _darkSurfaces;
  return base.copyWith(
    // The brand. `fromSeed` rounds #2F6B57 to its own tonal step (#176B53
    // light) — close, but the palette direction pins an exact value, and a
    // brand colour that shifts when Flutter retunes its tonal algorithm is
    // not a brand colour.
    primary: light ? loadoutBrandGreen : loadoutBrandGreenDark,
    onPrimary: light ? const Color(0xFFFFFFFF) : const Color(0xFF063528),
    primaryContainer: light ? const Color(0xFFCDE5DD) : const Color(0xFF24513F),
    onPrimaryContainer: light
        ? const Color(0xFF1C5343)
        : const Color(0xFFA5EDCB),

    // Danger. `error` IS the palette's red so a destructive button, a
    // validation message and a "short" figure are one colour, not three.
    error: light ? loadoutDangerRed : const Color(0xFFF0B3AA),
    onError: light ? const Color(0xFFFFFFFF) : const Color(0xFF4F0E0A),
    errorContainer: light ? const Color(0xFFEFDBD9) : const Color(0xFF4A2421),
    onErrorContainer: light ? const Color(0xFF7E3530) : const Color(0xFFF1C6C0),

    // The warm ramp: surfaces and the inks that sit on them.
    surface: ramp.surface,
    surfaceContainerLowest: ramp.lowest,
    surfaceContainerLow: ramp.low,
    surfaceContainer: ramp.container,
    surfaceContainerHigh: ramp.high,
    surfaceContainerHighest: ramp.highest,
    onSurface: ramp.ink,
    onSurfaceVariant: ramp.inkMuted,
    outline: ramp.outline,
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

// ---------------------------------------------------------- the tint recipe

/// The recipe both the folder palette and the status colours are built with,
/// borrowed from the one product that has solved "many user colours on one
/// page": Notion's chips are a desaturated ink of a hue on a low-percentage
/// wash of the SAME hue, published as separate light and dark sets.
///
/// The naive reading — alpha-blend the hue over the page at 5 % — fails here
/// because our eight hues are dark SEEDS: blending toward paper kills the
/// chroma along with the lightness and every chip lands on the same warm
/// grey. So the wash is built in HSL instead: keep the hue angle, damp the
/// saturation, and take the lightness to the far end of the scale. The
/// result measures 1.10-1.14:1 against paper — the same barely-there step
/// Notion's own light chips make against white — but it still reads as
/// green, or blue, or plum.
///
/// [visibility] is the floor the wash must clear against [ground]: the
/// lightness walks toward the ink until it does, so a naturally light hue
/// (honey, olive) makes the same *perceived* step as a dark one (plum).
/// [ground] is always `surfaceContainerLow`, the CARD — not the page. A chip
/// sits on both, and the card is the worst case (it is already one step off
/// the page), so clearing it clears everything.
Color _hueWash(
  Color hue, {
  required Color ground,
  required Brightness brightness,
  required double satScale,
  required ({double min, double max}) satRange,
  required double visibility,
}) {
  final source = HSLColor.fromColor(hue);
  final sat = (source.saturation * satScale).clamp(satRange.min, satRange.max);
  final light = brightness == Brightness.light;
  var lightness = light ? 0.93 : 0.14;
  Color wash() => HSLColor.fromAHSL(1, source.hue, sat, lightness).toColor();
  while (light ? lightness > 0.84 : lightness < 0.30) {
    if (_contrast(wash(), ground) >= visibility) break;
    lightness += light ? -0.005 : 0.005;
  }
  return wash();
}

/// The ink half of the recipe: the same hue, desaturated (a full-chroma
/// glyph on a wash vibrates), walked along the lightness scale until it
/// clears [target] against [on] — and, when [and] is given, [andTarget]
/// against that too (a status foreground has to read both on its own
/// container and straight on the page).
Color _hueInk(
  Color hue, {
  required Color on,
  required Brightness brightness,
  required double satScale,
  required ({double min, double max}) satRange,
  required double target,
  Color? and,
  double andTarget = 4.5,
}) {
  final source = HSLColor.fromColor(hue);
  final sat = (source.saturation * satScale).clamp(satRange.min, satRange.max);
  final light = brightness == Brightness.light;
  var lightness = light ? 0.34 : 0.70;
  Color ink() => HSLColor.fromAHSL(1, source.hue, sat, lightness).toColor();
  bool clears() {
    final candidate = ink();
    return _contrast(candidate, on) >= target &&
        (and == null || _contrast(candidate, and) >= andTarget);
  }

  while (light ? lightness > 0.08 : lightness < 0.96) {
    if (clears()) break;
    lightness += light ? -0.005 : 0.005;
  }
  return ink();
}

// ----------------------------------------------------------- folder palette

/// The eight hue SEEDS (design-spec §3), tuned to sit with the brand green
/// on warm paper. Indexed by [FolderHue] table order. Seeds, not final
/// colors: the shipped (tint, ink) pairs are derived from these per
/// brightness. Widgets read [FolderPalette], never this map.
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

/// One folder hue's shipped pair.
@immutable
final class FolderColors {
  const FolderColors({required this.tint, required this.ink});

  /// The chip's fill: a wash of the hue, one barely-there step off the page.
  final Color tint;

  /// The hue at reading strength for this brightness. It draws the glyph on
  /// [tint] (>= 5:1), and it is ALSO the right colour for any solid mark of
  /// this hue elsewhere — a jump-chip dot, a legend swatch, a bar. Never use
  /// [folderHueSeeds] for that: a dark seed dot vanishes on the dark ramp.
  final Color ink;
}

/// The eight precomputed (tint, ink) pairs, derived ONCE at theme build by
/// the Notion recipe above ([_hueWash] + [_hueInk]) — never hand-tuned, so
/// contrast holds by construction in both brightnesses and the repo's theme
/// tests can prove it for all eight. Widgets read `FolderPalette.of(context)`
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
    final light = brightness == Brightness.light;
    final ground = light ? _lightSurfaces.low : _darkSurfaces.low;
    // Identity is quieter than state: the wash clears a 1.12 (light) / 1.22
    // (dark) visibility floor, where a status container clears 1.25 / 1.35.
    final tint = _hueWash(
      seed,
      ground: ground,
      brightness: brightness,
      satScale: light ? 0.75 : 0.70,
      satRange: light ? (min: 0.10, max: 0.55) : (min: 0.10, max: 0.50),
      visibility: light ? 1.12 : 1.22,
    );
    return FolderColors(
      tint: tint,
      ink: _hueInk(
        seed,
        on: tint,
        brightness: brightness,
        satScale: light ? 0.85 : 0.80,
        satRange: light ? (min: 0.18, max: 0.62) : (min: 0.15, max: 0.55),
        // 5:1, not 4.5 — the small chip draws a 14 dp glyph, and thin
        // strokes need headroom over the text minimum.
        target: 5,
      ),
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

/// One state's shipped pair: a [container] to fill a banner/row/rung with,
/// and a [foreground] that reads on it — and, deliberately, also on the page
/// surface, so a state can be a tinted block OR a bare figure without
/// introducing a second colour for the same word.
@immutable
final class StatusPair {
  const StatusPair({required this.container, required this.foreground});

  final Color container;
  final Color foreground;

  static StatusPair _lerp(StatusPair a, StatusPair b, double t) => StatusPair(
    container: Color.lerp(a.container, b.container, t)!,
    foreground: Color.lerp(a.foreground, b.foreground, t)!,
  );
}

/// The state grammar (design-spec §5), and it is a CLOSED SET of three:
///
///  * [confirmed] — green: counted, confirmed, done, on track. Deliberately
///    the brand's own hue: in this app "done" is the happy path the brand
///    colour already means, and splitting them would mean two greens.
///  * [pending] — amber ([loadoutPendingAmber]): not counted yet, due soon,
///    doesn't add up. Warnings never block.
///  * [short] — red ([loadoutDangerRed], = the scheme's `error`): short,
///    negative, destructive.
///
/// These three hues are RESERVED. Nothing decorative may use them: if amber
/// appears on this screen it means pending, every time, or the user learns
/// that colour here means nothing. Decoration and identity are what the
/// eight folder hues are for. There is no fourth state — a fourth would make
/// the first three ambiguous.
///
/// Meaning is never colour ALONE either: every status surface pairs its
/// colour with an icon and a word (see `WarningBanner`).
@immutable
final class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.confirmed,
    required this.pending,
    required this.short,
  });

  /// Derives the three pairs by the same recipe as the folder palette, from
  /// the three canonical hues — one step louder than identity, because a
  /// state is meant to be found across the room.
  factory StatusColors.derive(Brightness brightness) => StatusColors(
    confirmed: _pairFromSeed(loadoutBrandGreen, brightness),
    pending: _pairFromSeed(loadoutPendingAmber, brightness),
    short: _pairFromSeed(loadoutDangerRed, brightness),
  );

  static StatusPair _pairFromSeed(Color seed, Brightness brightness) {
    final light = brightness == Brightness.light;
    final ground = light ? _lightSurfaces.low : _darkSurfaces.low;
    final container = _hueWash(
      seed,
      ground: ground,
      brightness: brightness,
      satScale: light ? 0.80 : 0.75,
      satRange: light ? (min: 0.12, max: 0.62) : (min: 0.12, max: 0.55),
      visibility: light ? 1.25 : 1.35,
    );
    return StatusPair(
      container: container,
      foreground: _hueInk(
        seed,
        on: container,
        brightness: brightness,
        satScale: light ? 0.90 : 0.72,
        satRange: light ? (min: 0.20, max: 0.72) : (min: 0.18, max: 0.62),
        target: 5,
        // A status foreground doubles as ink straight on the page.
        and: ground,
      ),
    );
  }

  /// Green: counted / confirmed / on track.
  final StatusPair confirmed;

  /// Amber: pending / due soon / doesn't add up.
  final StatusPair pending;

  /// Red: short / negative / critical.
  final StatusPair short;

  /// Legacy names for the amber pair, kept so presentation code written
  /// against the single-pair `StatusColors` keeps compiling. New code uses
  /// `StatusColors.of(context).pending.container` / `.foreground`.
  Color get warning => pending.container;

  /// Legacy name — see [warning].
  Color get onWarning => pending.foreground;

  /// Convenience for widgets: the tokens on the ambient theme.
  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>()!;

  @override
  StatusColors copyWith({
    StatusPair? confirmed,
    StatusPair? pending,
    StatusPair? short,
  }) => StatusColors(
    confirmed: confirmed ?? this.confirmed,
    pending: pending ?? this.pending,
    short: short ?? this.short,
  );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      confirmed: StatusPair._lerp(confirmed, other.confirmed, t),
      pending: StatusPair._lerp(pending, other.pending, t),
      short: StatusPair._lerp(short, other.short, t),
    );
  }
}

ThemeData loadoutTheme(Brightness brightness) {
  final scheme = loadoutColorScheme(brightness);
  final ramp = brightness == Brightness.light ? _lightSurfaces : _darkSurfaces;
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

    // "Flat, outlined" is a rule about the WHOLE app, not about the four
    // components that happened to be themed by hand. Material's default
    // `shadowColor` is opaque black, so any surface that keeps a non-zero
    // elevation — the FAB, a bottom action bar, a menu — drops a hard black
    // drop shadow that reads as a broken outline rather than as depth.
    // Killing it at the theme root means a component added tomorrow starts
    // flat too, and the hairline (below) is what carries separation.
    shadowColor: Colors.transparent,

    // Every legacy widget that greys itself out (ListTile, ToggleButtons,
    // Slider) reads this instead of Material's black38 — see
    // [_Surfaces.disabledInk] for why 38 % opacity is not good enough.
    disabledColor: ramp.disabledInk,

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

    // The disabled colours on all three button themes are the fix for a real
    // defect: Material paints a disabled label as `onSurface` at 38 % on a
    // 12 % fill, which measures 2.3:1 in light and 2.9:1 in dark — under the
    // 3:1 floor WCAG sets for UI text, on the one control (the closeout's
    // "Finish closeout") whose whole job is to explain that it is waiting.
    // Fixing it per-screen would leave the next disabled button broken, so
    // it is fixed here: a flat neutral FILL says "off", and the label stays
    // readable at ~5:1.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xl,
          vertical: Space.m,
        ),
        textStyle: text.labelLarge,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        iconColor: scheme.onPrimary,
        disabledBackgroundColor: ramp.disabledFill,
        disabledForegroundColor: ramp.disabledInk,
        disabledIconColor: ramp.disabledInk,
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
        foregroundColor: scheme.primary,
        iconColor: scheme.primary,
        disabledForegroundColor: ramp.disabledInk,
        disabledIconColor: ramp.disabledInk,
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
        foregroundColor: scheme.primary,
        iconColor: scheme.primary,
        disabledForegroundColor: ramp.disabledInk,
        disabledIconColor: ramp.disabledInk,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small),
        ),
      ),
    ),

    // The FAB is the one floating surface, and Material floats it on a
    // 6 dp elevation shadow by default: on warm paper that reads as a
    // heavy ring, and against the charcoal ramp it reads as a black halo.
    // Flat filled pill instead, in the same radius family as every other
    // control — the fill and the label carry it, no shadow required.
    //
    // And the fill is the BRAND, not `primaryContainer`: one saturated
    // colour does every interactive job in this app, so the screen's create
    // action cannot be a paler green than the button at the bottom of the
    // form it opens.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      splashColor: scheme.onPrimary.withValues(alpha: 0.12),
      extendedTextStyle: text.labelLarge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    ),

    // Menus float too. With shadows off they need the hairline to keep an
    // edge against the page they sit over.
    popupMenuTheme: PopupMenuThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small),
        side: hairline,
      ),
      labelTextStyle: WidgetStatePropertyAll(
        text.bodyLarge?.copyWith(color: scheme.onSurface),
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      elevation: 0,
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
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
