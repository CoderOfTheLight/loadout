// Renders every Loadout icon candidate to PNG.
//
// Run:
//   fvm flutter test tool/icon/render_icons_test.dart
//
// Output dir: $ICON_OUT if set, otherwise ./build/icon_out inside the repo.
// Per candidate:
//   <id>_ios_1024.png / _120 / _60   opaque iOS composites
//   <id>_android_fg_432.png          transparent adaptive foreground (xxxhdpi)
//   <id>_android_bg_432.png          opaque adaptive background
//   <id>_android_mono_432.png        white-on-transparent themed-icon layer
//   <id>_preview.png                 60px/120px critique sheet, dark + light
//   <id>_android_preview.png         masked adaptive + themed critique sheet

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'candidates/candidate_a_crate.dart';
import 'candidates/candidate_b_monogram.dart';
import 'candidates/candidate_c_folder.dart';
import 'candidates/candidate_d_stack.dart';
import 'harness.dart';

final List<LoadoutIconCandidate> candidates = [
  CandidateACrate(),
  CandidateBMonogram(),
  CandidateCFolder(),
  CandidateDStack(),
];

void main() {
  final outDir =
      Platform.environment['ICON_OUT'] ??
      '${Directory.current.path}/build/icon_out';

  test('render all icon candidates', () async {
    for (final c in candidates) {
      for (final size in [1024, 120, 60]) {
        await renderPng(
          composite(c),
          size,
          '$outDir/${c.id}_ios_$size.png',
          opaque: true,
        );
      }
      await renderPng(
        adaptiveForeground(c),
        432,
        '$outDir/${c.id}_android_fg_432.png',
      );
      await renderPng(
        adaptiveBackground(c),
        432,
        '$outDir/${c.id}_android_bg_432.png',
        opaque: true,
      );
      await renderPng(
        monoLayer(c),
        432,
        '$outDir/${c.id}_android_mono_432.png',
      );
      await renderPreviewSheet(c, '$outDir/${c.id}_preview.png');
      await renderAndroidPreviewSheet(c, '$outDir/${c.id}_android_preview.png');
    }
    // ignore: avoid_print
    print('Rendered ${candidates.length} candidate(s) into $outDir');
  });
}
