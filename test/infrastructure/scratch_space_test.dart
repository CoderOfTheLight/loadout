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

  test('sweepAll clears leftovers from previous runs', () async {
    // Sessions this process never handed out — i.e. what a crash or a kill
    // left behind. The live-session registry starts empty each launch, so
    // these are exactly the directories a sweep is meant to reclaim.
    final root = Directory('${temp.path}/scratch');
    for (final purpose in const ['backup', 'restore', 'ocr']) {
      final leftover = Directory(p.join(root.path, purpose, 'leftover'))
        ..createSync(recursive: true);
      File(p.join(leftover.path, 'staged.bin')).writeAsBytesSync([1, 2, 3]);
    }

    await scratch.sweepAll();

    for (final purpose in const ['backup', 'restore', 'ocr']) {
      expect(
        Directory(p.join(root.path, purpose, 'leftover')).existsSync(),
        isFalse,
      );
    }
    final sweep = diag.events.where((e) => e.event == DiagEvent.scratchSweepOk);
    expect(sweep.single.count, 3);
  });

  test('sweepAll leaves a session that is still in use', () async {
    // The OS pauses the app whenever a system file picker takes over, and
    // that is precisely when a backup container is staged in scratch waiting
    // to be copied out. Sweeping it there would delete the export.
    final live = await scratch.createSession('backup');
    File(p.join(live.path, 'loadout-backup.loadout')).writeAsStringSync('ct');

    await scratch.sweepAll();

    expect(live.existsSync(), isTrue);
    expect(
      File(p.join(live.path, 'loadout-backup.loadout')).existsSync(),
      isTrue,
    );
    expect(diag.events.single.count, 0, reason: 'nothing was reclaimed');

    // Once the owner is done, the session is disposable and stops being
    // exempt.
    await scratch.disposeSession(live);
    expect(live.existsSync(), isFalse);
  });

  test('sweepAll on a missing root is a zero-count no-op', () async {
    await scratch.sweepAll();
    expect(diag.events.single.event, DiagEvent.scratchSweepOk);
    expect(diag.events.single.count, 0);
  });
}
