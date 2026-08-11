/// Content-free diagnostics sink (design §10): in-memory ring buffer plus a
/// 256 KB rotating plaintext file `support/diag/diag.log` (content-free ⇒
/// plaintext acceptable), viewed/exported only via `/settings/diagnostics`.
///
/// Allowed per line: UTC timestamp, severity, event code, integer
/// counts/durations, exception *type name* only, schema version, and a random
/// per-session correlation id. Never: item names, quantities, event names,
/// recipe text, file paths, SQL, or exception messages.
library;

// The prefer_initializing_formals fix ('this._x' named parameters) needs
// the experimental private-named-parameters language feature, which this
// SDK does not enable; explicit `_x = x` initializers stay.
// ignore_for_file: prefer_initializing_formals

import 'dart:collection';
import 'dart:io';
import 'dart:math';

import '../../core/diagnostics/diag.dart';
import '../../core/time.dart';

/// Line shape (stable; pinned by test regex):
/// `<ISO-8601 UTC>Z <I|W|E> <eventCode> sid=<8 hex>`
/// `[ count=<int>][ elapsedMs=<int>][ err=<TypeName>][ schema=<int>]`
final class RingFileDiag implements Diag {
  RingFileDiag({
    required File logFile,
    Clock clock = const SystemClock(),
    int ringCapacity = 512,
    int maxFileBytes = 256 * 1024,
    Random? sessionIdSource,
  }) : _logFile = logFile,
       _clock = clock,
       _ringCapacity = ringCapacity,
       _maxFileBytes = maxFileBytes,
       sessionId = _newSessionId(sessionIdSource ?? Random.secure());

  final File _logFile;
  final Clock _clock;
  final int _ringCapacity;
  final int _maxFileBytes;

  /// Random per-session correlation id (8 lowercase hex chars).
  final String sessionId;

  final Queue<String> _ring = Queue<String>();

  /// Snapshot of the in-memory ring buffer, oldest first (diagnostics screen).
  List<String> get bufferedLines => List.unmodifiable(_ring);

  /// The rotating log file (diagnostics screen export source).
  File get logFile => _logFile;

  @override
  void event(
    DiagEvent event, {
    int? count,
    Duration? elapsed,
    String? errorType,
    int? schemaVersion,
  }) {
    final line = formatLine(
      now: _clock.now(),
      severity: severityOf(event),
      event: event,
      sessionId: sessionId,
      count: count,
      elapsed: elapsed,
      errorType: errorType,
      schemaVersion: schemaVersion,
    );
    _ring.addLast(line);
    while (_ring.length > _ringCapacity) {
      _ring.removeFirst();
    }
    _append(line);
  }

  void _append(String line) {
    try {
      final parent = _logFile.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      if (_logFile.existsSync() &&
          _logFile.lengthSync() + line.length + 1 > _maxFileBytes) {
        final rotated = File('${_logFile.path}.1');
        if (rotated.existsSync()) {
          rotated.deleteSync();
        }
        _logFile.renameSync(rotated.path);
      }
      _logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } on FileSystemException {
      // Diagnostics must never take the app down; the ring buffer still has
      // the line.
    }
  }

  /// Severity per event. The switch is exhaustive on purpose: adding a
  /// [DiagEvent] member without classifying it is a compile error.
  static String severityOf(DiagEvent event) => switch (event) {
    DiagEvent.dbOpenOk ||
    DiagEvent.backupCreateOk ||
    DiagEvent.restoreOk ||
    DiagEvent.scratchSweepOk ||
    DiagEvent.migrationOk ||
    DiagEvent.commandApplied => 'I',
    DiagEvent.dbOpenWrongKey ||
    DiagEvent.dbKeyMissing ||
    DiagEvent.backupValidateFail ||
    DiagEvent.restoreRolledBack ||
    DiagEvent.commandRejected => 'W',
    DiagEvent.dbCipherMissing ||
    DiagEvent.backupCreateFail ||
    DiagEvent.migrationFail => 'E',
  };

  static String formatLine({
    required Instant now,
    required String severity,
    required DiagEvent event,
    required String sessionId,
    int? count,
    Duration? elapsed,
    String? errorType,
    int? schemaVersion,
  }) {
    final ts = DateTime.fromMicrosecondsSinceEpoch(
      now.epochMicrosUtc,
      isUtc: true,
    ).toIso8601String();
    final buffer = StringBuffer('$ts $severity ${event.name} sid=$sessionId');
    if (count != null) {
      buffer.write(' count=$count');
    }
    if (elapsed != null) {
      buffer.write(' elapsedMs=${elapsed.inMilliseconds}');
    }
    if (errorType != null) {
      buffer.write(' err=${sanitizeErrorType(errorType)}');
    }
    if (schemaVersion != null) {
      buffer.write(' schema=$schemaVersion');
    }
    return buffer.toString();
  }

  /// Defense in depth: even though callers pass `runtimeType.toString()`,
  /// strip anything that is not a type-name character and cap the length so a
  /// line physically cannot carry content.
  static String sanitizeErrorType(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9_$<>]'), '');
    final bounded = cleaned.isEmpty ? 'UnknownError' : cleaned;
    return bounded.length <= 64 ? bounded : bounded.substring(0, 64);
  }

  static String _newSessionId(Random random) {
    const digits = '0123456789abcdef';
    return String.fromCharCodes(
      List.generate(8, (_) => digits.codeUnitAt(random.nextInt(16))),
    );
  }
}
