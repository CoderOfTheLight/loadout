/// §7.2 open-path tests: cipher-presence guard fires before any write;
/// wrong-key detection; key-length contract.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/infrastructure/db/open_database.dart';
import 'package:loadout/infrastructure/security/hex.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('open_db_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('cipher-presence guard', () {
    test('empty cipher_version result throws before any write', () {
      final path = '${temp.path}/guard.db';
      final db = sqlite3.open(path);
      addTearDown(db.close);
      expect(
        () => configureLoadoutConnection(
          db,
          'aa' * 32,
          cipherVersionProbe: () => ResultSet(['cipher_version'], [null], []),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('SQLCipher not linked'),
          ),
        ),
      );
      // Guard fired before journal_mode/schema statements: nothing was
      // written through this connection.
      expect(
        File(path).existsSync() ? File(path).lengthSync() : 0,
        0,
        reason: 'the guard must fail before any write',
      );
    });

    test('empty cipher_version STRING also throws', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(
        () => configureLoadoutConnection(
          db,
          'aa' * 32,
          cipherVersionProbe: () => ResultSet(['cipher_version'], [null], [
            [''],
          ]),
        ),
        throwsStateError,
      );
    });

    test('real SQLCipher build passes the guard', () {
      final db = sqlite3.open('${temp.path}/ok.db');
      addTearDown(db.close);
      configureLoadoutConnection(db, 'ab' * 32);
      db.execute('CREATE TABLE t (v TEXT)');
    });
  });

  group('openLoadoutExecutor', () {
    test('rejects keys that are not exactly 32 bytes', () {
      expect(
        () => openLoadoutExecutor(
          file: File('${temp.path}/x.db'),
          key: Uint8List(16),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });
  });

  group('isWrongKeyError', () {
    test('detects SqliteException(26) from a wrong-key open', () {
      final path = '${temp.path}/wrong.db';
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final db = sqlite3.open(path);
      configureLoadoutConnection(db, hexEncode(key));
      db.execute('CREATE TABLE t (v TEXT)');
      db.close();

      final wrong = sqlite3.open(path);
      addTearDown(wrong.close);
      wrong.execute('PRAGMA key = "x\'${'ff' * 32}\'";');
      Object? caught;
      try {
        wrong.select('SELECT count(*) FROM sqlite_master;');
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(isWrongKeyError(caught!), isTrue);
      expect(isCipherMissingError(caught), isFalse);
    });

    test('classifies the guard StateError as cipher-missing', () {
      final error = StateError('SQLCipher not linked; refusing plain SQLite');
      expect(isCipherMissingError(error), isTrue);
      expect(isWrongKeyError(error), isFalse);
    });
  });
}
