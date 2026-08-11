/// §10 scratch-space hygiene: sessions live under
/// `scratch/<purpose>/<id>/`, dispose deletes, sweepAll clears everything
/// and reports a content-free count.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/infrastructure/files/scratch_space.dart';
import 'package:path/path.dart' as p;

import 'harness.dart';

void main() {
  late Directory temp;
  late CapturingDiag diag;
  late AppSupportScratchSpace scratch;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scratch_test');
    diag = CapturingDiag();
    scratch = AppSupportScratchSpace(
      root: Directory('${temp.path}/scratch'),
      diag: diag,
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('createSession nests under scratch/<purpose>/<id>', () async {
    final session = await scratch.createSession('backup');
    expect(session.existsSync(), isTrue);
    expect(p.basename(session.parent.path), 'backup');
    expect(p.basename(session.path), hasLength(26)); // ULID
    expect(p.isWithin('${temp.path}/scratch', session.path), isTrue);
  });

  test('unknown purpose is rejected', () {
    expect(() => scratch.createSession('exfil'), throwsArgumentError);
  });

  test('disposeSession deletes the session tree', () async {
    final session = await scratch.createSession('restore');
    File(p.join(session.path, 'staged.bin')).writeAsBytesSync([1, 2, 3]);
    await scratch.disposeSession(session);
    expect(session.existsSync(), isFalse);
  });

  test('disposeSession refuses paths outside the scratch root', () async {
    final outside = Directory.systemTemp.createTempSync('not_scratch');
    addTearDown(() => outside.deleteSync(recursive: true));
    expect(() => scratch.disposeSession(outside), throwsArgumentError);
  });

  test('sweepAll removes every session and reports the count', () async {
    final a = await scratch.createSession('backup');
    final b = await scratch.createSession('restore');
    final c = await scratch.createSession('ocr');
    File(p.join(a.path, 'x')).writeAsStringSync('x');

    await scratch.sweepAll();

    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
    expect(c.existsSync(), isFalse);
    final sweep = diag.events.where((e) => e.event == DiagEvent.scratchSweepOk);
    expect(sweep.single.count, 3);
  });

  test('sweepAll on a missing root is a zero-count no-op', () async {
    await scratch.sweepAll();
    expect(diag.events.single.event, DiagEvent.scratchSweepOk);
    expect(diag.events.single.count, 0);
  });
}
