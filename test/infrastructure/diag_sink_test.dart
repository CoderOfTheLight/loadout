/// §11.2: Diag line format pinned by regex + DiagEvent exhaustiveness; ring
/// buffer bounds; 256 KB file rotation; error-type sanitization.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/core/time.dart';
import 'package:loadout/infrastructure/diagnostics/diag_sink.dart';

/// The §10 contract: UTC timestamp, severity, event code, session id, and
/// ONLY integer counts/durations, an exception type name, and a schema
/// version — in this order. Anything else on a line is a bug.
final lineFormat = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z '
  r'[IWE] [a-zA-Z]+ sid=[0-9a-f]{8}'
  r'( count=\d+)?( elapsedMs=\d+)?( err=[A-Za-z0-9_$<>]{1,64})?( schema=\d+)?$',
);

void main() {
  late Directory temp;
  late File logFile;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('diag_test');
    logFile = File('${temp.path}/diag/diag.log');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  RingFileDiag makeDiag({
    int maxFileBytes = 256 * 1024,
    int ringCapacity = 512,
  }) => RingFileDiag(
    logFile: logFile,
    clock: FixedClock(const Instant(1754906400000000)),
    maxFileBytes: maxFileBytes,
    ringCapacity: ringCapacity,
    sessionIdSource: Random(3),
  );

  test('every DiagEvent produces a line matching the pinned format', () {
    final diag = makeDiag();
    // Exhaustive over the closed set: a new enum member that is not
    // classified in RingFileDiag.severityOf is a compile error; a new member
    // that breaks the line shape fails here.
    for (final event in DiagEvent.values) {
      diag.event(
        event,
        count: 3,
        elapsed: const Duration(milliseconds: 12),
        errorType: 'StateError',
        schemaVersion: 1,
      );
    }
    final lines = diag.bufferedLines;
    expect(lines, hasLength(DiagEvent.values.length));
    for (final line in lines) {
      expect(line, matches(lineFormat), reason: line);
    }
    // Same content on disk.
    final fileLines = logFile.readAsLinesSync();
    expect(fileLines, lines);
  });

  test('lines without optional fields also match', () {
    final diag = makeDiag();
    diag.event(DiagEvent.dbOpenOk);
    expect(diag.bufferedLines.single, matches(lineFormat));
    expect(diag.bufferedLines.single, contains(' I dbOpenOk '));
  });

  test('severity classes are stable', () {
    expect(RingFileDiag.severityOf(DiagEvent.dbOpenOk), 'I');
    expect(RingFileDiag.severityOf(DiagEvent.dbOpenWrongKey), 'W');
    expect(RingFileDiag.severityOf(DiagEvent.dbKeyMissing), 'W');
    expect(RingFileDiag.severityOf(DiagEvent.dbCipherMissing), 'E');
    expect(RingFileDiag.severityOf(DiagEvent.backupCreateFail), 'E');
    expect(RingFileDiag.severityOf(DiagEvent.restoreRolledBack), 'W');
    expect(RingFileDiag.severityOf(DiagEvent.migrationFail), 'E');
  });

  test('ring buffer evicts oldest beyond capacity', () {
    final diag = makeDiag(ringCapacity: 5);
    for (var i = 0; i < 8; i++) {
      diag.event(DiagEvent.commandApplied, count: i);
    }
    expect(diag.bufferedLines, hasLength(5));
    expect(diag.bufferedLines.first, contains('count=3'));
    expect(diag.bufferedLines.last, contains('count=7'));
  });

  test('file rotates before exceeding the byte cap', () {
    final diag = makeDiag(maxFileBytes: 512);
    for (var i = 0; i < 40; i++) {
      diag.event(DiagEvent.commandApplied, count: i);
    }
    final rotated = File('${logFile.path}.1');
    expect(rotated.existsSync(), isTrue);
    expect(logFile.lengthSync(), lessThanOrEqualTo(512));
    expect(rotated.lengthSync(), lessThanOrEqualTo(512));
  });

  test('error type sanitization strips everything content-like', () {
    expect(
      RingFileDiag.sanitizeErrorType('SqliteException(26): /secret/path.db'),
      'SqliteException26secretpathdb',
    );
    expect(RingFileDiag.sanitizeErrorType('!!!'), 'UnknownError');
    expect(RingFileDiag.sanitizeErrorType('A' * 100), hasLength(64));
  });
}
