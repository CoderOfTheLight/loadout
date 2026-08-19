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
  ); // 'ocr' | 'backup' | 'restore' | 'export'
  Future<void> disposeSession(Directory session); // try/finally at call sites
  Future<void> sweepAll(); // on every app start and AppLifecycleState.paused
}

final class AppSupportScratchSpace implements ScratchSpace {
  AppSupportScratchSpace({
    required Directory root,
    Diag diag = const NoopDiag(),
  }) : _root = root,
       _diag = diag;

  static const Set<String> _purposes = {'ocr', 'backup', 'restore', 'export'};

  final Directory _root;
  final Diag _diag;

  /// Sessions handed out and not yet disposed. [sweepAll] leaves these
  /// alone: a session is in use until its owner says otherwise, and the OS
  /// pauses this app whenever a system file picker takes the screen — the
  /// exact moment a backup container is sitting in scratch waiting to be
  /// copied out. The set starts empty each launch, so anything left behind
  /// by a previous run is still swept.
  final Set<String> _liveSessions = {};

  @override
  Future<Directory> createSession(String purpose) async {
    if (!_purposes.contains(purpose)) {
      throw ArgumentError.value(purpose, 'purpose', 'unknown scratch purpose');
    }
    final session = Directory(p.join(_root.path, purpose, newUlid()));
    await session.create(recursive: true);
    _liveSessions.add(p.canonicalize(session.path));
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
    _liveSessions.remove(p.canonicalize(session.path));
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
          if (_liveSessions.contains(p.canonicalize(session.path))) {
            continue;
          }
          await session.delete(recursive: true);
          swept++;
        }
      }
    }
    _diag.event(DiagEvent.scratchSweepOk, count: swept);
  }
}
