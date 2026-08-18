/// The design system's guardrails (design §9 visual language, palette
/// direction "A · Warm Paper, finished").
///
/// `loadoutTheme` pins Material's neutral ramp AND its brand, state and
/// disabled colours by hand, so the two things that can quietly destroy
/// legibility — re-pinning a colour, and adding a screen that uses a role
/// nobody measured — are both checked here: every foreground/background pair
/// the app actually paints is measured against WCAG 2.2 AA in BOTH
/// brightnesses, including the eight folder chips, the three state pairs and
/// the disabled states Material's defaults get wrong. The rest pins the
/// decisions a later edit could undo by accident: the canonical palette,
/// flat outlined cards, always-visible tab labels, thumb-sized buttons and
/// the three tabular numeral tiers.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/theme.dart';
import 'package:loadout/app/widgets/form_action_bar.dart';
import 'package:loadout/core/folder_appearance.dart';

/// WCAG 2.2 contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void _expectContrast(
  Color foreground,
  Color background, {
  required double atLeast,
  required String pair,
}) {
  final ratio = _contrast(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(atLeast),
    reason: '$pair contrast is ${ratio.toStringAsFixed(2)}:1, needs $atLeast:1',
  );
}

/// Shortest distance between two hue angles, in degrees.
double _hueGap(Color a, Color b) {
  final raw =
      (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs() % 360;
  return raw > 180 ? 360 - raw : raw;
}

/// Every surface in the warm ramp, in the order the app stacks them.
List<(String, Color)> _surfaces(ColorScheme s) => [
  ('surface', s.surface),
  ('surfaceContainerLowest', s.surfaceContainerLowest),
  ('surfaceContainerLow', s.surfaceContainerLow),
  ('surfaceContainer', s.surfaceContainer),
  ('surfaceContainerHigh', s.surfaceContainerHigh),
  ('surfaceContainerHighest', s.surfaceContainerHighest),
];

/// The three state pairs, named.
List<(String, StatusPair)> _states(StatusColors c) => [
  ('confirmed', c.confirmed),
  ('pending', c.pending),
  ('short', c.short),
];

void main() {
  group('canonical palette', () {
    test('ships the chosen values, not whatever the seed derives', () {
      final light = loadoutColorScheme(Brightness.light);
      // The palette direction pins exact values; `ColorScheme.fromSeed`
      // rounds them to its own tonal steps, and a brand colour that moves
      // when Flutter retunes its tonal algorithm is not a brand colour.
      expect(light.primary, loadoutBrandGreen);
      expect(light.surface, loadoutPaper);
      expect(light.onSurface, loadoutInk);
      expect(
        light.error,
        loadoutDangerRed,
        reason: 'destructive, invalid and "short" must be ONE red',
      );

      final dark = loadoutColorScheme(Brightness.dark);
      expect(dark.primary, loadoutBrandGreenDark);
    });

    test('dark is its own system, not a tint of light', () {
      final light = loadoutColorScheme(Brightness.light);
      final dark = loadoutColorScheme(Brightness.dark);
      // The proof that dark needs its own values: the light brand green on
      // the dark ground is unreadable, so it cannot simply be reused.
      expect(
        _contrast(loadoutBrandGreen, dark.surface),
        lessThan(3),
        reason: 'the light green sinks into the charcoal ramp',
      );
      for (final (name, l, d) in [
        ('primary', light.primary, dark.primary),
        ('error', light.error, dark.error),
        (
          'pending',
          StatusColors.derive(Brightness.light).pending.foreground,
          StatusColors.derive(Brightness.dark).pending.foreground,
        ),
      ]) {
        expect(
          d.computeLuminance(),
          greaterThan(l.computeLuminance() + 0.2),
          reason: '$name must lighten substantially for the dark ground',
        );
      }
    });

    test('surfaces AND inks are warm, not the default cool grey', () {
      for (final brightness in Brightness.values) {
        final s = loadoutColorScheme(brightness);
        for (final (name, colour) in [
          ('surface', s.surface),
          ('surfaceContainerHigh', s.surfaceContainerHigh),
          ('onSurface', s.onSurface),
          ('onSurfaceVariant', s.onSurfaceVariant),
          ('outline', s.outline),
        ]) {
          expect(
            colour.r,
            greaterThan(colour.b),
            reason:
                '${brightness.name} $name should lean warm '
                '(more red than blue)',
          );
        }
      }
    });
  });

  group('contrast — WCAG 2.2 AA in both brightnesses', () {
    test('body and secondary ink clear every surface in the ramp', () {
      for (final brightness in Brightness.values) {
        final s = loadoutColorScheme(brightness);
        final label = brightness.name;
        for (final (name, surface) in _surfaces(s)) {
          // Body copy read at arm's length in daylight: AAA, not AA.
          _expectContrast(
            s.onSurface,
            surface,
            atLeast: 7,
            pair: '$label onSurface/$name',
          );
          // Second lines carry real information in this app, so the muted
          // ink is held to the body floor, not to the 3:1 UI floor.
          _expectContrast(
            s.onSurfaceVariant,
            surface,
            atLeast: 4.5,
            pair: '$label onSurfaceVariant/$name',
          );
        }
      }
    });

    test('accent inks and container pairs clear 4.5:1', () {
      for (final brightness in Brightness.values) {
        final s = loadoutColorScheme(brightness);
        final label = brightness.name;
        for (final (fg, bg, pair) in [
          // The brand and the danger red are both used as TEXT (button
          // labels, links, validation), not only as fills.
          (s.primary, s.surface, 'primary/surface'),
          (s.primary, s.surfaceContainerLow, 'primary/card'),
          (s.error, s.surface, 'error/surface'),
          (s.error, s.surfaceContainerLow, 'error/card'),
          (s.onPrimary, s.primary, 'primary'),
          (s.onPrimaryContainer, s.primaryContainer, 'primaryContainer'),
          (s.onSecondaryContainer, s.secondaryContainer, 'secondaryContainer'),
          (s.onTertiaryContainer, s.tertiaryContainer, 'tertiaryContainer'),
          (s.onError, s.error, 'error'),
          (s.onErrorContainer, s.errorContainer, 'errorContainer'),
          (s.onInverseSurface, s.inverseSurface, 'inverseSurface'),
        ]) {
          _expectContrast(fg, bg, atLeast: 4.5, pair: '$label $pair');
        }
      }
    });

    test('component boundaries clear the 3:1 non-text floor', () {
      for (final brightness in Brightness.values) {
        final s = loadoutColorScheme(brightness);
        final label = brightness.name;
        // `outline` draws the edge of a control (outlined buttons, inputs):
        // WCAG 1.4.11 puts that at 3:1.
        _expectContrast(
          s.outline,
          s.surface,
          atLeast: 3,
          pair: '$label outline/surface',
        );
        _expectContrast(
          s.outline,
          s.surfaceContainerLow,
          atLeast: 3,
          pair: '$label outline/card',
        );
        // `outlineVariant` is the hairline that separates two surfaces —
        // decorative, but it has to be visible against the card it edges.
        _expectContrast(
          s.outlineVariant,
          s.surfaceContainerLow,
          atLeast: 1.2,
          pair: '$label outlineVariant/card',
        );
      }
    });

    test('all eight folder chips clear WCAG in both brightnesses', () {
      // Spec §3: pairs are DERIVED (the Notion recipe — desaturated ink on a
      // wash of the same hue), never hand-tuned; this test is the proof the
      // derivation holds for every seed. If one fails, adjust that seed's
      // tone, not the method.
      for (final brightness in Brightness.values) {
        final palette = FolderPalette.derive(brightness);
        final s = loadoutColorScheme(brightness);
        for (final hue in FolderHue.values) {
          final pair = palette.pair(hue);
          final name = '${brightness.name} folder ${hue.dbValue}';
          // The glyph on the chip. 4.5 is the floor; the recipe targets 5
          // because the small chip draws it at 14 dp.
          _expectContrast(pair.ink, pair.tint, atLeast: 4.5, pair: name);
          // The chip has to read as a shape on both grounds it sits on.
          _expectContrast(
            pair.tint,
            s.surface,
            atLeast: 1.1,
            pair: '$name tint/surface',
          );
          _expectContrast(
            pair.tint,
            s.surfaceContainerLow,
            atLeast: 1.1,
            pair: '$name tint/card',
          );
          // The ink doubles as the hue's solid mark on a page (dots, bars),
          // so it must also read straight on the surface.
          _expectContrast(
            pair.ink,
            s.surface,
            atLeast: 4.5,
            pair: '$name ink/surface',
          );
        }
      }
    });

    test('all three state pairs clear WCAG in both brightnesses', () {
      for (final brightness in Brightness.values) {
        final status = StatusColors.derive(brightness);
        final s = loadoutColorScheme(brightness);
        for (final (name, pair) in _states(status)) {
          final label = '${brightness.name} $name';
          _expectContrast(
            pair.foreground,
            pair.container,
            atLeast: 4.5,
            pair: label,
          );
          // A state foreground is also used as bare ink on the page (a red
          // figure, an amber count) — same colour, no second token.
          _expectContrast(
            pair.foreground,
            s.surface,
            atLeast: 4.5,
            pair: '$label fg/surface',
          );
          _expectContrast(
            pair.foreground,
            s.surfaceContainerLow,
            atLeast: 4.5,
            pair: '$label fg/card',
          );
          // Status surfaces (banners, the Home lead tile's rungs) sit as
          // tinted blocks on the page: each must be visibly distinct from
          // it, and from the card, without shouting.
          _expectContrast(
            pair.container,
            s.surface,
            atLeast: 1.2,
            pair: '$label container/surface',
          );
          _expectContrast(
            pair.container,
            s.surfaceContainerLow,
            atLeast: 1.15,
            pair: '$label container/card',
          );
        }
      }
    });

    test('disabled controls stay readable — the state Material gets wrong', () {
      // Regression: Material paints a disabled label as `onSurface` at 38 %
      // on an `onSurface`-at-12 % fill, which measures 2.26:1 in light and
      // 2.91:1 in dark — under the 3:1 floor WCAG sets for UI text, on the
      // one control (the closeout's "Finish closeout") whose entire job when
      // disabled is to be read. The theme pins disabled colours instead: a
      // flat neutral FILL says "off", so the LABEL can clear the body floor.
      const disabled = <WidgetState>{WidgetState.disabled};
      for (final brightness in Brightness.values) {
        final theme = loadoutTheme(brightness);
        final s = loadoutColorScheme(brightness);
        final label = brightness.name;
        for (final (name, style) in [
          ('filled', theme.filledButtonTheme.style),
          ('outlined', theme.outlinedButtonTheme.style),
          ('text', theme.textButtonTheme.style),
        ]) {
          final foreground = style!.foregroundColor?.resolve(disabled);
          expect(
            foreground,
            isNotNull,
            reason: '$name button must theme its disabled label',
          );
          // On its own fill when it has one, and on the page when it does
          // not (outlined and text buttons are transparent).
          final fill = style.backgroundColor?.resolve(disabled) ?? s.surface;
          _expectContrast(
            foreground!,
            fill,
            atLeast: 4.5,
            pair: '$label disabled $name label/fill',
          );
          _expectContrast(
            foreground,
            s.surface,
            atLeast: 4.5,
            pair: '$label disabled $name label/surface',
          );
          _expectContrast(
            foreground,
            s.surfaceContainerLow,
            atLeast: 4.5,
            pair: '$label disabled $name label/card',
          );
          // Disabled must still read as disabled: the fill is a flat
          // neutral, never the brand.
          expect(
            fill,
            isNot(s.primary),
            reason: 'a disabled button must not wear the brand colour',
          );
        }
        // Legacy widgets (ListTile, ToggleButtons, Slider) read this.
        _expectContrast(
          theme.disabledColor,
          s.surface,
          atLeast: 4.5,
          pair: '$label disabledColor/surface',
        );
      }
    });

    testWidgets('a disabled button really paints the themed label, even '
        'under a local styleFrom', (tester) async {
      // The closeout's commit button passes its own `styleFrom` for height.
      // ButtonStyle merges per-property, so the theme's disabled colours
      // must still win — this is the actual widget the defect was reported
      // on, in both brightnesses.
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: loadoutTheme(brightness),
            home: Scaffold(
              body: Center(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                  ),
                  onPressed: null,
                  child: const Text('Finish closeout'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final painted = tester
            .renderObject<RenderParagraph>(find.text('Finish closeout'))
            .text
            .style!
            .color!;
        final fill = tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.text('Finish closeout'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        _expectContrast(
          painted,
          fill,
          atLeast: 4.5,
          pair: '${brightness.name} painted disabled label/fill',
        );
      }
    });
  });

  group('the state grammar is a closed set', () {
    test('three pairs, each same-hue, and none of them reads as "just the '
        'accent"', () {
      for (final brightness in Brightness.values) {
        final status = StatusColors.derive(brightness);
        final s = loadoutColorScheme(brightness);
        final label = brightness.name;

        // Each pair is one hue: ink and wash come from the same seed, which
        // is what stops a banner reading as two colours.
        for (final (name, pair) in _states(status)) {
          expect(
            _hueGap(pair.foreground, pair.container),
            lessThan(20),
            reason: '$label $name: ink and container must be the same hue',
          );
        }

        // Amber and red must never be mistaken for the brand: if a state
        // colour reads as "just the accent", the state stops meaning
        // anything. (Green is the exception ON PURPOSE — "confirmed" is the
        // brand's own hue, and two greens would be worse than one.)
        for (final (name, pair) in [
          ('pending', status.pending),
          ('short', status.short),
        ]) {
          expect(
            _hueGap(pair.foreground, s.primary),
            greaterThan(60),
            reason: '$label $name must not read as the brand colour',
          );
        }
        expect(
          _hueGap(status.confirmed.foreground, s.primary),
          lessThan(20),
          reason: 'confirmed IS the brand family, deliberately',
        );
        // Amber and red are neighbours on the wheel; they still have to be
        // told apart at arm's length (and every status surface pairs the
        // colour with an icon and a word, never colour alone).
        expect(
          _hueGap(status.pending.foreground, status.short.foreground),
          greaterThan(25),
          reason: '$label pending vs short',
        );
      }
    });

    test('the theme carries the precomputed extensions', () {
      for (final brightness in Brightness.values) {
        final theme = loadoutTheme(brightness);
        final palette = theme.extension<FolderPalette>();
        expect(palette, isNotNull, reason: 'widgets must never derive');
        final derived = FolderPalette.derive(brightness);
        for (final hue in FolderHue.values) {
          expect(palette!.pair(hue).tint, derived.pair(hue).tint);
          expect(palette.pair(hue).ink, derived.pair(hue).ink);
        }
        final status = theme.extension<StatusColors>();
        expect(status, isNotNull);
        // The legacy single-pair names still resolve to the amber pair
        // while presentation code migrates to `.pending`.
        expect(status!.warning, status.pending.container);
        expect(status.onWarning, status.pending.foreground);
      }
    });
  });

  group('folder identity', () {
    test('the eight hue names are the DB contract and never change', () {
      // `folders.hue_name` stores these strings and SQL CHECKs them; a
      // rename here is a migration, not a theme edit.
      expect(
        [for (final hue in FolderHue.values) hue.dbValue],
        ['fern', 'lake', 'plum', 'berry', 'clay', 'honey', 'olive', 'stone'],
      );
      expect(folderHueSeeds.keys, FolderHue.values);
    });

    test('every chip is a wash of its own hue, not a grey', () {
      for (final brightness in Brightness.values) {
        final palette = FolderPalette.derive(brightness);
        final light = brightness == Brightness.light;
        for (final hue in FolderHue.values) {
          final pair = palette.pair(hue);
          final seed = folderHueSeeds[hue]!;
          final name = '${brightness.name} ${hue.dbValue}';
          expect(
            _hueGap(pair.tint, seed),
            lessThan(15),
            reason: '$name tint must stay on the seed\'s hue',
          );
          expect(
            _hueGap(pair.ink, seed),
            lessThan(15),
            reason: '$name ink must stay on the seed\'s hue',
          );
          // A wash, not a fill: it lives at the far end of the lightness
          // scale for its brightness.
          final lightness = HSLColor.fromColor(pair.tint).lightness;
          expect(
            light ? lightness : 1 - lightness,
            greaterThan(0.8),
            reason: '$name tint must stay a wash',
          );
          // …and the ink is desaturated, so eight of them can share a
          // screen without vibrating.
          expect(
            HSLColor.fromColor(pair.ink).saturation,
            lessThan(0.65),
            reason: '$name ink must be desaturated',
          );
        }
      }
    });
  });

  group('components', () {
    test('cards are flat and outlined, never default grey with a shadow', () {
      for (final brightness in Brightness.values) {
        final card = loadoutTheme(brightness).cardTheme;
        expect(card.elevation, 0);
        expect(card.color, loadoutColorScheme(brightness).surfaceContainerLow);
        expect(
          (card.shape as RoundedRectangleBorder?)?.side.style,
          BorderStyle.solid,
          reason: 'a hairline survives sunlight; a shadow does not',
        );
      }
    });

    test('nothing floats on a drop shadow — the FAB least of all', () {
      // Regression: the extended "Add item" FAB shipped on Material's
      // default 6 dp elevation, and `ThemeData.shadowColor` defaults to
      // OPAQUE BLACK — so the one floating control in the app wore a heavy
      // black ring in both brightnesses, against a design language that is
      // flat surfaces plus a hairline. The fix is at the theme root, so a
      // component nobody has themed yet starts flat too.
      for (final brightness in Brightness.values) {
        final theme = loadoutTheme(brightness);
        expect(
          theme.shadowColor,
          Colors.transparent,
          reason: 'an opaque black shadow is the app-wide root cause',
        );
        final fab = theme.floatingActionButtonTheme;
        for (final (name, elevation) in [
          ('resting', fab.elevation),
          ('focus', fab.focusElevation),
          ('hover', fab.hoverElevation),
          ('highlight', fab.highlightElevation),
          ('disabled', fab.disabledElevation),
        ]) {
          expect(elevation, 0, reason: 'FAB $name elevation must be flat');
        }
        expect(theme.popupMenuTheme.elevation, 0);
        expect(theme.bottomSheetTheme.elevation, 0);
        // …and it wears the brand, not the pale container: one saturated
        // colour does every interactive job.
        final scheme = loadoutColorScheme(brightness);
        expect(fab.backgroundColor, scheme.primary);
        expect(fab.foregroundColor, scheme.onPrimary);
      }
    });

    testWidgets('the pinned form action bar is flat with a hairline, not a '
        'black band', (tester) async {
      // Same root cause as the FAB, one screen lower: this bar carried
      // `elevation: 3`, which painted a hard black stripe across the full
      // width of every form (item edit, closeout, scan-in).
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: loadoutTheme(brightness),
            home: const Scaffold(
              bottomNavigationBar: FormActionBar(child: Text('Save')),
            ),
          ),
        );
        // MaterialApp lerps between themes; settle before reading colours.
        await tester.pumpAndSettle();
        final bar = tester.widget<Material>(
          find
              .ancestor(of: find.text('Save'), matching: find.byType(Material))
              .first,
        );
        expect(bar.elevation, 0);
        expect(bar.shadowColor, Colors.transparent);
        expect(
          (bar.shape as Border?)?.top.color,
          loadoutColorScheme(brightness).outlineVariant,
          reason: 'separation comes from the hairline, never a shadow',
        );
      }
    });

    test('buttons and list rows are thumb-sized', () {
      final theme = loadoutTheme(Brightness.light);
      const states = <WidgetState>{};
      for (final (name, style) in [
        ('filled', theme.filledButtonTheme.style),
        ('outlined', theme.outlinedButtonTheme.style),
        ('text', theme.textButtonTheme.style),
      ]) {
        final size = style!.minimumSize!.resolve(states)!;
        expect(
          size.height,
          greaterThanOrEqualTo(48),
          reason: '$name button must clear the 48 dp target floor',
        );
      }
      expect(theme.listTileTheme.minTileHeight, greaterThanOrEqualTo(48));
      // Design §9: primary actions are taller still.
      expect(primaryButtonMinSize.height, greaterThanOrEqualTo(56));
    });

    test('tab labels are always visible', () {
      expect(
        loadoutTheme(Brightness.light).navigationBarTheme.labelBehavior,
        NavigationDestinationLabelBehavior.alwaysShow,
        reason: 'icon-only tabs are a guessing game for an occasional user',
      );
    });

    test('the type scale has real hierarchy', () {
      final text = loadoutTheme(Brightness.light).textTheme;
      expect(
        text.headlineSmall!.fontSize!,
        greaterThan(text.titleLarge!.fontSize!),
      );
      expect(
        text.titleLarge!.fontSize!,
        greaterThan(text.titleMedium!.fontSize!),
      );
      expect(text.titleMedium!.fontWeight, FontWeight.w600);
      // The eyebrow: small, heavy, wide.
      expect(text.titleSmall!.fontWeight, FontWeight.w700);
      expect(text.titleSmall!.letterSpacing!, greaterThan(0.5));
      // Body copy is at least Material's default, never smaller.
      expect(text.bodyLarge!.fontSize!, greaterThanOrEqualTo(16));
      // Spec §5 deltas: the eyebrow and the caption both sit ON the
      // older-adult reading floor, not under it.
      expect(text.titleSmall!.fontSize, 13.5);
      expect(text.bodySmall!.fontSize, 13);
    });

    test('the numerals are three tabular tiers, separated by weight', () {
      final text = loadoutTheme(Brightness.light).textTheme;
      expect(Numerals.tabular, const [FontFeature.tabularFigures()]);
      final caption = Numerals.caption(text)!;
      final row = Numerals.rowQuantity(text)!;
      final glance = Numerals.glance(text)!;
      final hero = Numerals.hero(text)!;

      // Tier sizes ascend, with no two tiers landing on the same step.
      expect(caption.fontSize, text.bodySmall!.fontSize);
      expect(row.fontSize, text.titleLarge!.fontSize);
      expect(glance.fontSize, text.headlineSmall!.fontSize);
      expect(hero.fontSize, text.displaySmall!.fontSize);
      expect(caption.fontSize!, lessThan(row.fontSize!));
      expect(row.fontSize!, lessThan(glance.fontSize!));
      expect(glance.fontSize!, lessThan(hero.fontSize!));

      // M3 Expressive's principle, approximated with the one axis Flutter
      // gives us: the hero is heavier than the tiers that support it.
      expect(hero.fontWeight, FontWeight.w700);
      for (final (name, style) in [
        ('caption', caption),
        ('rowQuantity', row),
        ('glance', glance),
      ]) {
        expect(style.fontWeight, FontWeight.w600, reason: '$name weight');
        expect(
          hero.fontWeight!.value,
          greaterThan(style.fontWeight!.value),
          reason: 'the hero must outweigh $name',
        );
      }
      // Every tier is tabular — a count that jitters as it ticks is worse
      // than a count that is slightly too small.
      for (final style in [caption, row, glance, hero]) {
        expect(style.fontFeatures, Numerals.tabular);
      }
    });
  });
}
