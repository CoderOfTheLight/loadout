/// The parked-workspace scanner (§7.3, §8.2): what counts as recoverable
/// ciphertext in `db/`, how the copies are ordered, and where each copy's
/// sidecars live. Pure file-name/statistics logic — no SQLCipher here.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/infrastructure/files/loadout_paths.dart';
import 'package:loadout/infrastructure/startup/parked_workspace.dart';

void main() {
  late Directory temp;
  late LoadoutPaths paths;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('parked_scan');
    paths = LoadoutPaths(Directory('${temp.path}/support'));
    paths.dbDir.createSync(recursive: true);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File write(String name, [String body = 'ciphertext']) {
    final file = File('${paths.dbDir.path}/$name')..writeAsStringSync(body);
    return file;
  }

  test('a missing db directory scans clean', () {
    paths.dbDir.deleteSync(recursive: true);
    expect(scanParkedWorkspaces(paths), isEmpty);
  });

  test('the live database and its sidecars are not parked copies', () {
    write('loadout.db');
    write('loadout.db-wal');
    write('loadout.db-shm');
    expect(scanParkedWorkspaces(paths), isEmpty);
  });

  test('an interrupted restore is found by its .pre-restore name', () {
    write('loadout.db.pre-restore');

    final found = scanParkedWorkspaces(paths);
    expect(found, hasLength(1));
    expect(found.single.kind, ParkedWorkspaceKind.interruptedRestore);
    expect(found.single.label, 'pre-restore');
    expect(found.single.sizeBytes, greaterThan(0));
  });

  test('interrupted-restore sidecars keep the trailing-suffix shape', () {
    write('loadout.db.pre-restore');
    write('loadout.db-wal.pre-restore');

    final parked = scanParkedWorkspaces(paths).single;
    expect(
      parked.memberFor('-wal').path,
      '${paths.dbDir.path}/loadout.db-wal.pre-restore',
      reason: 'restoreBackup appends .pre-restore AFTER the -wal suffix',
    );
    expect(parked.memberFor('').path, parked.file.path);
    expect(
      parked.existingMembers().map((m) => m.$1),
      ['', '-wal'],
      reason: 'the absent -shm is not reported',
    );
  });

  test('archives are found, labelled for their retained key, and dated', () {
    write('orphaned-20260701120000.db');
    write('orphaned-20260701120000.db-wal');

    final parked = scanParkedWorkspaces(paths).single;
    expect(parked.kind, ParkedWorkspaceKind.archived);
    expect(
      parked.label,
      'orphaned-20260701120000',
      reason: 'exactly the label startFreshFromRecovery retains the key under',
    );
    expect(parked.parkedAtUtc, DateTime.utc(2026, 7, 1, 12));
    expect(
      parked.memberFor('-wal').path,
      '${paths.dbDir.path}/orphaned-20260701120000.db-wal',
    );
  });

  test('several archives come back newest first', () {
    write('orphaned-20260101000000.db');
    write('orphaned-20260815093000.db');
    write('orphaned-20260301000000.db');

    expect(scanParkedWorkspaces(paths).map((w) => w.label), [
      'orphaned-20260815093000',
      'orphaned-20260301000000',
      'orphaned-20260101000000',
    ]);
  });

  test('a same-second collision archive is still recognised', () {
    write('orphaned-20260815093000.db');
    write('orphaned-20260815093000-2.db');

    expect(
      scanParkedWorkspaces(paths).map((w) => w.label),
      ['orphaned-20260815093000-2', 'orphaned-20260815093000'],
      reason: 'the -<n> disambiguator sorts after the base label',
    );
  });

  test('unrelated files in db/ are ignored', () {
    write('loadout.db.new');
    write('orphaned-nope.db');
    write('orphaned-2026081509300.db'); // 13 digits
    write('notes.txt');
    expect(scanParkedWorkspaces(paths), isEmpty);
  });
}
