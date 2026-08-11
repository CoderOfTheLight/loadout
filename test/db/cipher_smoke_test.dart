import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('bundled sqlite3 is a SQLCipher build', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final rows = db.select('PRAGMA cipher_version;');
    expect(
      rows,
      isNotEmpty,
      reason:
          'cipher_version is empty on a plain SQLite build; '
          'the sqlcipher hook in pubspec.yaml is not taking effect',
    );
    expect(rows.first.values.single, isA<String>());
  });

  test('data written with a key is unreadable without it', () {
    final path =
        '${Directory.systemTemp.createTempSync('cipher_smoke').path}/t.db';
    final db = sqlite3.open(path);
    db
      ..execute("PRAGMA key = 'correct horse';")
      ..execute('CREATE TABLE t (v TEXT);')
      ..execute("INSERT INTO t VALUES ('secret');")
      ..close();

    final wrong = sqlite3.open(path);
    addTearDown(wrong.close);
    expect(
      () => wrong.select('SELECT * FROM t;'),
      throwsA(isA<SqliteException>()),
      reason: 'opening without PRAGMA key must not expose plaintext',
    );
  });
}
