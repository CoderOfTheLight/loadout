/// Dart side of the §7.2/§10 iOS backup exclusion: sets
/// `NSURLIsExcludedFromBackupKey` on the `db/` and `scratch/` directories via
/// a small MethodChannel handled in `AppDelegate.swift`. No-op everywhere
/// else.
library;

import 'dart:io';

import 'package:flutter/services.dart';

final class IosBackupExclusion {
  const IosBackupExclusion();

  static const MethodChannel _channel = MethodChannel(
    'loadout/backup_exclusion',
  );

  /// Returns true when the exclusion attribute was applied. Best-effort:
  /// failures are reported as false, never thrown (bootstrap must not die on
  /// a resource-attribute hiccup).
  Future<bool> excludeFromBackup(Directory dir) async {
    if (!Platform.isIOS) {
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>(
        'excludeFromBackup',
        dir.path,
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// True on the iOS Simulator, which implements neither Data Protection
  /// nor the Secure Enclave; false on a device and everywhere else.
  Future<bool> isSimulator() async {
    if (!Platform.isIOS) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('isSimulator') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The data-protection class iOS actually applied to [path], e.g.
  /// `NSFileProtectionCompleteUntilFirstUserAuthentication`. Null off iOS or
  /// when the attribute cannot be read.
  ///
  /// Design §10 relies on the platform default rather than an entitlement
  /// (see ios/Runner/Runner.entitlements); this is how that claim gets
  /// checked against a real file on a real device.
  Future<String?> fileProtection(FileSystemEntity entity) async {
    if (!Platform.isIOS) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>('fileProtection', entity.path);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
