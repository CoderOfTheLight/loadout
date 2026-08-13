/// The design system's guardrails (design §9 visual language).
///
/// `loadoutTheme` re-pins Material's neutral ramp to a warm one so the app
/// reads as paper rather than as developer grey. Re-pinning surfaces by hand
/// is exactly the change that can quietly destroy contrast, so every
/// foreground/background pair the app actually uses is checked against WCAG
/// here, in both brightnesses. The rest pins the decisions a later edit
/// could undo by accident: the seed, flat outlined cards, always-visible tab
/// labels, and thumb-sized buttons.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/theme.dart';

/// WCAG 2.1 contrast ratio between two opaque colours.
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

void main() {
  group('colour scheme', () {
    test('keeps the design §9 seed for both brightnesses', () {
      for (final brightness in Brightness.values) {
        final ours = loadoutColorScheme(brightness);
        final material = ColorScheme.fromSeed(
          seedColor: loadoutSeedColor,
          brightness: brightness,
        );
        // Only the neutral ramp is re-pinned; every accent role is
        // Material's own tonal value.
        expect(ours.primary, material.primary);
        expect(ours.secondaryContainer, material.secondaryContainer);
        expect(ours.tertiaryContainer, material.tertiaryContainer);
        expect(ours.error, material.error);
      }
    });

    test('surfaces are warm, not the default cool grey', () {
      final light = loadoutColorScheme(Brightness.light).surface;
      final dark = loadoutColorScheme(Brightness.dark).surface;
      for (final (name, colour) in [('light', light), ('dark', dark)]) {
        expect(
          colour.r,
          greaterThan(colour.b),
          reason: '$name surface should lean warm (more red than blue)',
        );
      }
    });

    test('every foreground pair the app paints clears WCAG', () {
      for (final brightness in Brightness.values) {
        final s = loadoutColorScheme(brightness);
        final label = brightness.name;
        // Body copy read at arm's length in daylight: AAA, not AA.
        _expectContrast(
          s.onSurface,
          s.surface,
          atLeast: 7,
          pair: '$label onSurface/surface',
        );
        _expectContrast(
          s.onSurface,
          s.surfaceContainerLow,
          atLeast: 7,
          pair: '$label onSurface/card',
        );
        _expectContrast(
          s.onSurfaceVariant,
          s.surfaceContainerLow,
          atLeast: 4.5,
          pair: '$label onSurfaceVariant/card',
        );
        for (final (fg, bg, pair) in [
          (s.onPrimary, s.primary, 'primary'),
          (s.onPrimaryContainer, s.primaryContainer, 'primaryContainer'),
          (s.onSecondaryContainer, s.secondaryContainer, 'secondaryContainer'),
          (s.onTertiaryContainer, s.tertiaryContainer, 'tertiaryContainer'),
          (s.onErrorContainer, s.errorContainer, 'errorContainer'),
          (s.onInverseSurface, s.inverseSurface, 'inverseSurface'),
        ]) {
          _expectContrast(fg, bg, atLeast: 4.5, pair: '$label $pair');
        }
        // The card hairline has to be visible against the card itself.
        _expectContrast(
          s.outlineVariant,
          s.surfaceContainerLow,
          atLeast: 1.2,
          pair: '$label outlineVariant/card',
        );
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
    });
  });
}
