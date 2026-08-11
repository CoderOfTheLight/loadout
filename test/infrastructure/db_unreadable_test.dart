/// §11.2 Tier 2: a keyed database (including its -wal and -shm sidecars) is
/// unreadable without the key — no `SQLite format 3\0` magic, no plaintext
/// marker — and opening with no/wrong key throws SqliteException(26).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/infrastructure/db/open_database.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;

import 'harness.dart';

bool containsBytes(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

void main() {
  final sqliteMagic = [...ascii.encode('SQLite format 3'), 0];
  final markerBytes = ascii.encode(secretMarker);

  late Directory temp;
  late File dbFile;
  final key = Uint8List.fromList(List.generate(32, (i) => 255 - i));

  setUp(() {
    temp = Directory.systemTemp.createTempSync('unreadable_test');
    dbFile = File('${temp.path}/loadout.db');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('db, -wal and -shm never leak magic or plaintext marker', () async {
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    await seedWorkspaceData(db); // schema created + marker rows written

    // WAL sidecars exist while the connection is open; read them live.
    final wal = File('${dbFile.path}-wal');
    final shm = File('${dbFile.path}-shm');
    expect(wal.existsSync(), isTrue, reason: 'journal_mode=WAL is set in §7.2');
    final walBytes = await wal.readAsBytes();
    expect(walBytes, isNotEmpty);
    expect(
      containsBytes(walBytes, markerBytes),
      isFalse,
      reason: 'WAL pages are encrypted',
    );
    if (shm.existsSync()) {
      final shmBytes = await shm.readAsBytes();
      expect(containsBytes(shmBytes, markerBytes), isFalse);
    }
    await db.close();

    final mainBytes = await dbFile.readAsBytes();
    expect(mainBytes, isNotEmpty);
    expect(
      containsBytes(mainBytes, sqliteMagic),
      isFalse,
      reason: 'an encrypted db has a random salt header, not the magic',
    );
    expect(containsBytes(mainBytes, markerBytes), isFalse);
  });

  test('reopen with no key or wrong key throws SqliteException(26)', () async {
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    await seedWorkspaceData(db);
    await db.close();

    final noKey = sqlite3.open(dbFile.path);
    addTearDown(noKey.close);
    expect(
      () => noKey.select('SELECT * FROM settings;'),
      throwsA(
        isA<SqliteException>().having((e) => e.resultCode, 'resultCode', 26),
      ),
    );

    final wrongKey = sqlite3.open(dbFile.path);
    addTearDown(wrongKey.close);
    wrongKey.execute('PRAGMA key = "x\'${'00' * 32}\'";');
    expect(
      () => wrongKey.select('SELECT count(*) FROM sqlite_master;'),
      throwsA(
        isA<SqliteException>().having((e) => e.resultCode, 'resultCode', 26),
      ),
    );
  });

  test('correct key reads the marker back', () async {
    final db = AppDatabase(openLoadoutExecutor(file: dbFile, key: key));
    await seedWorkspaceData(db);
    await db.close();

    final dump = dumpDatabase(dbFile, key);
    expect(dump, contains(secretMarker));
  });
}
