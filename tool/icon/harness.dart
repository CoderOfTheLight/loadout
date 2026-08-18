// Icon render harness for Loadout.
//
// App icons are defined as code (Canvas drawing in a 1024x1024 coordinate
// space) and rendered to PNG by `render_icons_test.dart` under
// `fvm flutter test`. No external image tooling required.
//
// Conventions every candidate must follow:
//  * All drawing happens in a fixed 1024x1024 logical space; the harness
//    scales the canvas before calling paint, so every output size is a
//    direct vector render (never an upscaled bitmap).
//  * `paintBackground` must fill the entire 1024x1024 rect with opaque
//    paint (iOS App Store icons must have no alpha).
//  * `paintForeground` draws the artwork only, on a transparent field
//    (this becomes the Android adaptive foreground / mono layer source).
//  * `artExtent` is the fraction of the canvas the foreground art spans at
//    its widest; the harness uses it to rescale the art into the Android
//    adaptive safe zone (66dp of the 108dp canvas).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Logical design space. All candidate painting code assumes this side.
const double kDesignSide = 1024.0;

/// Android adaptive: safe zone diameter is 66dp on a 108dp canvas.
const double kAdaptiveSafeFraction = 66.0 / 108.0;

abstract class LoadoutIconCandidate {
  /// Short id used in output filenames, e.g. 'a_crate'.
  String get id;

  /// Fraction of the 1024 canvas the foreground artwork spans at its widest.
  double get artExtent;

  /// Fully opaque, fills the whole 1024x1024 rect.
  void paintBackground(Canvas canvas);

  /// Artwork only, transparent field, positioned for the iOS composite.
  void paintForeground(Canvas canvas);

  /// Source for the Android 13+ themed-icon layer, drawn in the same
  /// 1024-space as [paintForeground]. Everything opaque here ends up a single
  /// flat colour, so a candidate whose colour separation carries the shape
  /// must re-cut that separation as holes (BlendMode.clear) or it silhouettes
  /// into a blob. Defaults to the foreground for candidates that already read
  /// as one shape.
  void paintMonochrome(Canvas canvas) => paintForeground(canvas);

  /// Optional soft grounding shadow, drawn between background and foreground
  /// in the flat composite only. Deliberately excluded from the Android
  /// adaptive foreground and mono layers (Apple/Google both say: no baked
  /// effects in layered artwork; the system supplies depth).
  void paintShadow(Canvas canvas) {}
}

Rect get designRect => const Rect.fromLTWH(0, 0, kDesignSide, kDesignSide);

/// Renders [draw] (which paints in 1024-space) to an exact [size]x[size]
/// sRGB PNG at [outPath]. Vector-scales before painting: no resampling.
///
/// [opaque]: strips the alpha channel entirely (24-bit RGB PNG) — required
/// for iOS icons, which App Store validation rejects if they carry alpha.
/// Flutter's built-in PNG encoder always writes RGBA, so opaque output is
/// re-encoded by the minimal RGB encoder below (zlib via dart:io).
Future<void> renderPng(
  void Function(Canvas canvas) draw,
  int size,
  String outPath, {
  bool opaque = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
  );
  canvas.scale(size / kDesignSide);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);

  final Uint8List pngBytes;
  if (opaque) {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) throw StateError('raw readback failed for $outPath');
    pngBytes = _encodeRgbPng(size, size, raw.buffer.asUint8List());
  } else {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw StateError('PNG encode failed for $outPath');
    pngBytes = byteData.buffer.asUint8List();
  }
  image.dispose();

  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(pngBytes, flush: true);
}

/// Renders [draw] (1024-space) into a [size]x[size] raster image in memory.
Future<ui.Image> renderImageAt(
  void Function(Canvas canvas) draw,
  int size,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
  );
  canvas.scale(size / kDesignSide);
  draw(canvas);
  return recorder.endRecording().toImage(size, size);
}

/// Writes a critique sheet for [c]: the true 60px raster blown up 6x and the
/// true 120px raster blown up 3x (nearest-neighbour, so the actual home-screen
/// pixels are visible), each on a dark and a light ground.
Future<void> renderPreviewSheet(LoadoutIconCandidate c, String outPath) async {
  const cell = 380.0;
  const inset = 10.0;
  final small = await renderImageAt(composite(c), 60);
  final medium = await renderImageAt(composite(c), 120);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, cell * 4, 420));
  final grounds = [
    const Color(0xFF1C1C1E), // dark wallpaper
    const Color(0xFFF2F2F4), // light wallpaper
  ];
  final images = [small, small, medium, medium];
  final labels = [0, 1, 0, 1]; // ground index per cell
  final paint = Paint()..filterQuality = FilterQuality.none;
  for (var i = 0; i < 4; i++) {
    final x = i * cell;
    canvas.drawRect(
      Rect.fromLTWH(x, 0, cell, 420),
      Paint()..color = grounds[labels[i]],
    );
    final img = images[i];
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(x + inset, 30, cell - 2 * inset, cell - 2 * inset),
      paint,
    );
  }
  final sheet = await recorder.endRecording().toImage((cell * 4).toInt(), 420);
  final bytes = await sheet.toByteData(format: ui.ImageByteFormat.png);
  small.dispose();
  medium.dispose();
  sheet.dispose();
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);
}

/// Writes an Android critique sheet for [c], rendered at mdpi (108px — the
/// smallest adaptive canvas, so the harshest test) and blown up 3.5x with
/// nearest-neighbour sampling.
///
/// The four cells are the two things a launcher can do to this artwork: crop
/// the 108dp canvas to its centre 72dp and mask it (circle, then squircle),
/// and throw away every colour in favour of the mono layer (light theme, then
/// dark). If the icon survives all four it survives Android.
Future<void> renderAndroidPreviewSheet(
  LoadoutIconCandidate c,
  String outPath,
) async {
  const src = 108.0; // mdpi adaptive canvas
  const visible = 72.0; // what survives the launcher's crop
  const cell = 380.0;
  const inset = 20.0;
  final adaptive = await renderImageAt((canvas) {
    adaptiveBackground(c)(canvas);
    adaptiveForeground(c)(canvas);
  }, src.toInt());
  final mono = await renderImageAt(monoLayer(c), src.toInt());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, cell * 4, cell));
  const crop = Rect.fromLTWH(
    (src - visible) / 2,
    (src - visible) / 2,
    visible,
    visible,
  );
  final dst = const Rect.fromLTWH(
    inset,
    inset,
    cell - 2 * inset,
    cell - 2 * inset,
  );
  // (ground, image, tint) per cell.
  final cells = <(Color, ui.Image, Color?)>[
    (const Color(0xFF1C1C1E), adaptive, null),
    (const Color(0xFFF2F2F4), adaptive, null),
    (const Color(0xFFF2F2F4), mono, const Color(0xFF2F6B57)),
    (const Color(0xFF1C1C1E), mono, const Color(0xFFB9D8C8)),
  ];
  final sample = Paint()..filterQuality = FilterQuality.none;
  for (var i = 0; i < cells.length; i++) {
    final (ground, image, tint) = cells[i];
    canvas.save();
    canvas.translate(i * cell, 0);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, cell, cell),
      Paint()..color = ground,
    );
    // Even cells get the circle mask, odd cells the squircle: between them they
    // bracket every launcher shape.
    canvas.clipPath(
      i.isEven
          ? (Path()..addOval(dst))
          : (Path()..addRRect(
              RRect.fromRectAndRadius(dst, Radius.circular(dst.width * 0.32)),
            )),
    );
    if (tint != null) {
      // Themed icons: a flat tinted plate, then the mono layer re-coloured.
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, cell, cell),
        Paint()
          ..color = i == 2 ? const Color(0xFFCFE3D8) : const Color(0xFF1E3A30),
      );
      sample.colorFilter = ui.ColorFilter.mode(tint, BlendMode.srcIn);
    } else {
      sample.colorFilter = null;
    }
    canvas.drawImageRect(image, crop, dst, sample);
    canvas.restore();
  }

  final sheet = await recorder.endRecording().toImage(
    (cell * 4).toInt(),
    cell.toInt(),
  );
  final bytes = await sheet.toByteData(format: ui.ImageByteFormat.png);
  adaptive.dispose();
  mono.dispose();
  sheet.dispose();
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);
}

// ---------------------------------------------------------------------------
// Minimal 24-bit RGB PNG encoder (no alpha channel), for iOS icon output.
// ---------------------------------------------------------------------------

Uint8List _encodeRgbPng(int width, int height, Uint8List rgba) {
  // Scanlines: 1 filter byte (0 = None) + 3 bytes per pixel.
  final raw = Uint8List(height * (1 + width * 3));
  var ri = 0;
  var si = 0;
  for (var y = 0; y < height; y++) {
    raw[ri++] = 0;
    for (var x = 0; x < width; x++) {
      raw[ri++] = rgba[si];
      raw[ri++] = rgba[si + 1];
      raw[ri++] = rgba[si + 2];
      si += 4; // drop alpha (all pixels are opaque by construction)
    }
  }
  final idat = ZLibCodec(level: 9).encode(raw);

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // color type 2: truecolor, no alpha
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace

  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _addChunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _addChunk(out, 'sRGB', Uint8List.fromList(const [0])); // perceptual intent
  _addChunk(out, 'IDAT', Uint8List.fromList(idat));
  _addChunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

void _addChunk(BytesBuilder out, String type, Uint8List data) {
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final typeAndData = Uint8List(4 + data.length)
    ..setRange(0, 4, type.codeUnits)
    ..setRange(4, 4 + data.length, data);
  out.add(typeAndData);
  final crc = ByteData(4)..setUint32(0, _crc32(typeAndData));
  out.add(crc.buffer.asUint8List());
}

final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

int _crc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// iOS composite: opaque background + shadow + foreground.
void Function(Canvas) composite(LoadoutIconCandidate c) => (canvas) {
  c.paintBackground(canvas);
  c.paintShadow(canvas);
  c.paintForeground(canvas);
};

/// Runs [draw] rescaled about the canvas centre so art spanning
/// [LoadoutIconCandidate.artExtent] lands inside the 66/108 safe zone.
void _inSafeZone(
  LoadoutIconCandidate c,
  Canvas canvas,
  void Function(Canvas) draw,
) {
  final scale = kAdaptiveSafeFraction / c.artExtent;
  canvas.save();
  canvas.translate(kDesignSide / 2, kDesignSide / 2);
  canvas.scale(scale);
  canvas.translate(-kDesignSide / 2, -kDesignSide / 2);
  draw(canvas);
  canvas.restore();
}

/// Android adaptive foreground: transparent field, artwork rescaled about the
/// canvas centre so it fits the 66/108 safe zone.
void Function(Canvas) adaptiveForeground(LoadoutIconCandidate c) =>
    (canvas) => _inSafeZone(c, canvas, c.paintForeground);

/// Pre-API-26 round launcher icon: the flat composite clipped to the circle
/// inscribed in the canvas. Carries alpha, unlike every other output here.
void Function(Canvas) legacyRound(LoadoutIconCandidate c) => (canvas) {
  canvas.save();
  canvas.clipPath(Path()..addOval(designRect));
  composite(c)(canvas);
  canvas.restore();
};

/// Android adaptive background: the opaque background alone.
void Function(Canvas) adaptiveBackground(LoadoutIconCandidate c) =>
    (canvas) => c.paintBackground(canvas);

/// Android 13+ themed-icon mono layer: white silhouette of
/// [LoadoutIconCandidate.paintMonochrome] on transparency (system re-tints it).
///
/// Painted into its own layer so a candidate can carve holes with
/// BlendMode.clear; the srcIn filter then flattens whatever survives to white.
void Function(Canvas) monoLayer(LoadoutIconCandidate c) => (canvas) {
  final paint = Paint()
    ..colorFilter = const ui.ColorFilter.mode(
      Color(0xFFFFFFFF),
      BlendMode.srcIn,
    );
  canvas.saveLayer(designRect, paint);
  _inSafeZone(c, canvas, c.paintMonochrome);
  canvas.restore();
};
