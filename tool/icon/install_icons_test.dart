// Installs the shipping Loadout icon into the iOS and Android platform trees.
//
// Run:
//   fvm flutter test tool/icon/install_icons_test.dart
//
// Every file is a direct vector render at its exact pixel size — nothing here
// is ever resampled from a larger bitmap, so the 20x20 iOS icon is as crisp as
// the 1024. Re-running is idempotent: same input, same bytes.
//
// `render_icons_test.dart` is the design loop (all candidates, critique
// sheets, throwaway output dir); this is the ship step for the chosen one.

import 'dart:io';
import 'dart:ui' show Canvas;

import 'package:flutter_test/flutter_test.dart';

import 'candidates/candidate_a_crate.dart';
import 'harness.dart';

/// The chosen icon. Changing this line re-skins both platforms.
final LoadoutIconCandidate shipping = CandidateACrate();

/// iOS asset catalogue: filename -> pixel side. Mirrors the `size` x `scale`
/// of every entry in AppIcon.appiconset/Contents.json; keep the two in step.
const Map<String, int> iosIcons = {
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

/// Android density buckets: mipmap suffix -> (adaptive canvas px, legacy px).
/// Adaptive layers are 108dp; legacy launcher icons are 48dp.
const Map<String, (int, int)> androidDensities = {
  'mdpi': (108, 48),
  'hdpi': (162, 72),
  'xhdpi': (216, 96),
  'xxhdpi': (324, 144),
  'xxxhdpi': (432, 192),
};

void main() {
  // Tests run with the package root as cwd.
  final root = Directory.current.path;
  final iosDir = '$root/ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final resDir = '$root/android/app/src/main/res';
  final written = <String>[];

  Future<void> emit(
    void Function(Canvas) draw,
    int size,
    String path, {
    bool opaque = false,
  }) async {
    await renderPng(draw, size, path, opaque: opaque);
    written.add('${size}px  ${path.substring(root.length + 1)}');
  }

  test('install iOS app icon set', () async {
    // Opaque throughout: App Store validation rejects an icon with alpha.
    for (final entry in iosIcons.entries) {
      await emit(
        composite(shipping),
        entry.value,
        '$iosDir/${entry.key}',
        opaque: true,
      );
    }
  });

  test('install Android launcher icons', () async {
    for (final entry in androidDensities.entries) {
      final dir = '$resDir/mipmap-${entry.key}';
      final (adaptive, legacy) = entry.value;
      await emit(
        adaptiveForeground(shipping),
        adaptive,
        '$dir/ic_launcher_foreground.png',
      );
      await emit(
        adaptiveBackground(shipping),
        adaptive,
        '$dir/ic_launcher_background.png',
        opaque: true,
      );
      await emit(
        monoLayer(shipping),
        adaptive,
        '$dir/ic_launcher_monochrome.png',
      );
      // Pre-API-26 fallbacks: the flat composite, square and round.
      await emit(
        composite(shipping),
        legacy,
        '$dir/ic_launcher.png',
        opaque: true,
      );
      await emit(legacyRound(shipping), legacy, '$dir/ic_launcher_round.png');
    }
  });

  tearDownAll(() {
    // ignore: avoid_print
    print(
      'Installed ${written.length} file(s) from "${shipping.id}":\n'
      '  ${written.join('\n  ')}',
    );
  });
}
