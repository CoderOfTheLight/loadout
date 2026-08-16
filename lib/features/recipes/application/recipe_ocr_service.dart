/// Gate 5, OCR half: photograph a printed recipe and read its text ON THIS
/// DEVICE. The camera path presents the system document scanner
/// (edge-detected, perspective-corrected pages); the photo path presents the
/// system photo picker. Both feed Apple Vision text recognition (revision
/// 3, iOS 16 floor) behind one MethodChannel and come back as plain text
/// lines in reading order.
///
/// The lines then flow into the SAME pipeline as "Paste ingredients" —
/// `parseIngredientPaste` and the review sheet — exactly as the parser's
/// Gate 5 seam planned: OCR is a second producer, not a second reviewer.
///
/// Privacy (threat model): the photo and every recognized string stay in
/// process memory; nothing is written to disk, nothing reaches the
/// diagnostics log (content-free codes only), and no network exists to
/// reach. Recognition models live inside the OS.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Content-free failure surfaced to the form ("Couldn't read that photo").
/// [code] is one of the channel's stable codes — never text from the photo.
final class RecipeOcrException implements Exception {
  const RecipeOcrException(this.code);

  final String code;

  @override
  String toString() => 'RecipeOcrException($code)';
}

/// One capture: the recognized text lines, top to bottom, pages in scan
/// order. Empty means the photo held no readable text.
final class RecipeOcrCapture {
  const RecipeOcrCapture({required this.lines});

  final List<String> lines;
}

/// Screen-facing OCR surface. Availability is a capability, not an error:
/// screens hide the affordance when a probe returns false (Android says
/// false everywhere until its ML Kit half ships).
abstract interface class RecipeOcrService {
  /// True when the system document camera can be presented.
  Future<bool> isCameraScanAvailable();

  /// True when the system photo picker + recognizer can be presented.
  Future<bool> isPhotoPickAvailable();

  /// Presents the document camera. Null when the owner cancelled.
  Future<RecipeOcrCapture?> scanWithCamera();

  /// Presents the photo picker. Null when the owner cancelled.
  Future<RecipeOcrCapture?> pickPhoto();
}

/// The production implementation over the native channel. iOS only today;
/// every other platform is a standing "not available" without touching the
/// channel.
final class MethodChannelRecipeOcrService implements RecipeOcrService {
  const MethodChannelRecipeOcrService();

  static const MethodChannel channel = MethodChannel(
    'dev.coderofthelight.loadout/recipe_ocr',
  );

  bool get _platformSupported =>
      defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;

  @override
  Future<bool> isCameraScanAvailable() => _probe('isCameraScanAvailable');

  @override
  Future<bool> isPhotoPickAvailable() => _probe('isPhotoPickAvailable');

  @override
  Future<RecipeOcrCapture?> scanWithCamera() => _capture('scanWithCamera');

  @override
  Future<RecipeOcrCapture?> pickPhoto() => _capture('pickPhoto');

  Future<bool> _probe(String method) async {
    if (!_platformSupported) return false;
    try {
      return await channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<RecipeOcrCapture?> _capture(String method) async {
    if (!_platformSupported) {
      throw const RecipeOcrException('unavailable');
    }
    try {
      final lines = await channel.invokeListMethod<String>(method);
      if (lines == null) return null; // owner cancelled
      return RecipeOcrCapture(lines: lines);
    } on PlatformException catch (e) {
      throw RecipeOcrException(e.code);
    } on MissingPluginException {
      throw const RecipeOcrException('unavailable');
    }
  }
}
