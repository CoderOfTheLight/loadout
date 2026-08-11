/// Scratch-space hygiene (design §10). All ephemera (restore staging, export
/// staging, future OCR images) live under `support/scratch/<purpose>/<id>/`
/// and are swept on every app start and on `AppLifecycleState.paused`.
library;

// The prefer_initializing_formals fix ('this._x' named parameters) needs
// the experimental private-named-parameters language feature, which this
// SDK does not enable; explicit `_x = x` initializers stay.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/diagnostics/diag.dart';
import '../../core/ids.dart';

abstract interface class ScratchSpace {
  Future<Directory> createSession(
    String purpose,
  ); // 'ocr' | 'backup' | 'restore'
  Future<void> disposeSession(Directory session); // try/finally at call sites
  Future<void> sweepAll(); // on every app start and AppLifecycleState.paused
}

final class AppSupportScratchSpace implements ScratchSpace {
  AppSupportScratchSpace({
    required Directory root,
    Diag diag = const NoopDiag(),
  }) : _root = root,
       _diag = diag;

  static const Set<String> _purposes = {'ocr', 'backup', 'restore'};

  final Directory _root;
  final Diag _diag;

  @override
  Future<Directory> createSession(String purpose) async {
    if (!_purposes.contains(purpose)) {
      throw ArgumentError.value(purpose, 'purpose', 'unknown scratch purpose');
    }
    final session = Directory(p.join(_root.path, purpose, newUlid()));
    await session.create(recursive: true);
    return session;
  }

  @override
  Future<void> disposeSession(Directory session) async {
    if (!p.isWithin(_root.path, session.path)) {
      throw ArgumentError.value(
        session.path,
        'session',
        'not a scratch session directory',
      );
    }
    if (await session.exists()) {
      await session.delete(recursive: true);
    }
  }

  @override
  Future<void> sweepAll() async {
    var swept = 0;
    if (await _root.exists()) {
      await for (final purposeDir in _root.list()) {
        if (purposeDir is! Directory) {
          await purposeDir.delete();
          continue;
        }
        await for (final session in purposeDir.list()) {
          await session.delete(recursive: true);
          swept++;
        }
      }
    }
    _diag.event(DiagEvent.scratchSweepOk, count: swept);
  }
}
