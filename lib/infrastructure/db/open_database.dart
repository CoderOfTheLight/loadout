/// Production database open path (design §7.2).
///
/// SQLCipher comes from `package:sqlite3` via the pubspec
/// `hooks.user_defines: sqlite3: source: sqlcipher` block; native-asset
/// loading is process-wide and works in every isolate automatically — there
/// is no `open.overrideFor` / `isolateSetup` step anywhere in the codebase.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
// DriftRemoteException is how drift surfaces background-isolate errors; the
// wrong-key classifier below must unwrap it. The API is marked experimental
// but is the only sanctioned unwrap point.
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:sqlite3/common.dart';

import '../security/hex.dart';

/// Opens the encrypted Loadout executor over [file] with the 32-byte raw
/// [key]. The `setup` callback runs on every opened connection, in whichever
/// isolate opens it.
QueryExecutor openLoadoutExecutor({
  required File file,
  required Uint8List key, // exactly 32 bytes
}) {
  assert(key.length == 32);
  if (key.length != 32) {
    throw ArgumentError.value(
      key.length,
      'key',
      'SQLCipher raw key must be exactly 32 bytes',
    );
  }
  final hexKey = hexEncode(key); // 64 lowercase hex chars
  return NativeDatabase.createInBackground(
    file,
    setup: (db) => configureLoadoutConnection(db, hexKey),
  );
}

/// Per-connection SQLCipher setup (§7.2, order normative):
/// key → cipher-presence guard → wrong-key check → session pragmas.
///
/// SQLCipher 4 defaults stand (AES-256-CBC, per-page HMAC-SHA512); the raw
/// key form skips the internal KDF. `cipher_memory_security` is deliberately
/// OFF (CPU cost for no coverage against an attacker who already reads app
/// memory).
void configureLoadoutConnection(
  CommonDatabase db,
  String hexKey, {
  ResultSet Function()? cipherVersionProbe, // test seam only
}) {
  db.execute('PRAGMA key = "x\'$hexKey\'";');
  // Refuse to run if the hook is misconfigured and plain SQLite loaded.
  final v = cipherVersionProbe != null
      ? cipherVersionProbe()
      : db.select('PRAGMA cipher_version;');
  if (v.isEmpty || (v.first.values.first as String).isEmpty) {
    throw StateError('SQLCipher not linked; refusing plain SQLite');
  }
  // Wrong-key check: throws SqliteException(26) "file is not a database".
  db.select('SELECT count(*) FROM sqlite_master;');
  db.execute('PRAGMA foreign_keys = ON;');
  db.execute('PRAGMA journal_mode = WAL;'); // WAL pages are encrypted
  db.execute('PRAGMA temp_store = MEMORY;');
}

/// True when [error] is the SQLCipher wrong-key failure — `SqliteException`
/// result code 26 ("file is not a database") — including when drift's
/// background isolate wraps it in a [DriftRemoteException].
bool isWrongKeyError(Object error) {
  final unwrapped = _unwrap(error);
  if (unwrapped is SqliteException) {
    return unwrapped.resultCode == 26 || unwrapped.extendedResultCode == 26;
  }
  return false;
}

/// True when [error] is the §7.2 cipher-presence guard refusing to run on a
/// plain (non-SQLCipher) build.
bool isCipherMissingError(Object error) {
  final unwrapped = _unwrap(error);
  return unwrapped is StateError &&
      unwrapped.message.toString().contains('SQLCipher not linked');
}

Object _unwrap(Object error) {
  var current = error;
  while (current is DriftRemoteException) {
    current = current.remoteCause;
  }
  return current;
}
