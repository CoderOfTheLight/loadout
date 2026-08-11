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
}
