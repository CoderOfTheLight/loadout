/// Barcode capture for "scan items in" and scan-to-count closeouts —
/// ON THIS DEVICE, like everything else. The native side presents a
/// full-screen camera that detects ONE barcode and returns its raw payload;
/// the app never looks the code up anywhere. A barcode means something only
/// because the owner once told Loadout which of HER items it is
/// (items.barcode, schema v6): recognition, not lookup.
///
/// Privacy (threat model): frames stay in the camera pipeline, the decoded
/// payload stays in process memory, nothing is written, logged, or sent.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Content-free failure ("Couldn't open the camera"). [code] is one of the
/// channel's stable codes — never a payload.
final class BarcodeScanException implements Exception {
  const BarcodeScanException(this.code);

  final String code;

  @override
  String toString() => 'BarcodeScanException($code)';
}

/// One detected barcode: the raw payload exactly as the detector delivered
/// it (UPC-A arrives as its 13-digit EAN form — stable as long as the same
/// detector reads it every time, which is the only equality that matters),
/// and the symbology name for display/debugging only.
final class BarcodeScan {
  const BarcodeScan({required this.payload, required this.symbology});

  final String payload;
  final String symbology;
}

/// Screen-facing scanner surface. Availability is a capability, not an
/// error: screens hide scan affordances when the probe says false (Android
/// says false until its half ships; permission-denied says true here and
/// surfaces as 'camera_denied' on capture so the screen can point at
/// Settings).
abstract interface class BarcodeScanService {
  /// True when the device has a camera this build can present a scanner on.
  Future<bool> isAvailable();

  /// Presents the scanner until one barcode is detected. Null when the
  /// owner cancelled.
  Future<BarcodeScan?> scanOne();
}

/// The production implementation over the native channel. iOS only today.
final class MethodChannelBarcodeScanService implements BarcodeScanService {
  const MethodChannelBarcodeScanService();

  static const MethodChannel channel = MethodChannel(
    'dev.coderofthelight.loadout/barcode_scan',
  );

  bool get _platformSupported =>
      defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;

  @override
  Future<bool> isAvailable() async {
    if (!_platformSupported) return false;
    try {
      return await channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<BarcodeScan?> scanOne() async {
    if (!_platformSupported) {
      throw const BarcodeScanException('unavailable');
    }
    try {
      final result = await channel.invokeMapMethod<String, Object?>('scanOne');
      if (result == null) return null; // owner cancelled
      return BarcodeScan(
        payload: result['payload']! as String,
        symbology: result['symbology']! as String,
      );
    } on PlatformException catch (e) {
      throw BarcodeScanException(e.code);
    } on MissingPluginException {
      throw const BarcodeScanException('unavailable');
    }
  }
}
