/// Key lifecycle (design §7.1).
///
/// The 32-byte SQLCipher raw key is generated from the platform CSPRNG and
/// lives exclusively in the platform secure store (iOS Keychain, Android
/// Keystore-wrapped preferences). It never appears in logs, exports, or the
/// database itself. The only cross-device migration path is the encrypted
/// backup container (§8).
library;

// The prefer_initializing_formals fix ('this._x' named parameters) needs
// the experimental private-named-parameters language feature, which this
// SDK does not enable; explicit `_x = x` initializers stay.
// ignore_for_file: prefer_initializing_formals

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hex.dart';

/// Secure-store entry name (design §7.1).
const String databaseKeyStorageName = 'loadout.db_key.v1';

/// 32 bytes from `Random.secure()` (platform CSPRNG).
Uint8List generateDatabaseKey({Random? random}) {
  final rng = random ?? Random.secure();
  final key = Uint8List(32);
  for (var i = 0; i < key.length; i++) {
    key[i] = rng.nextInt(256);
  }
  return key;
}

abstract interface class KeyManager {
  Future<bool> hasDatabaseKey();

  /// 32 bytes; creates on first call.
  Future<Uint8List> getOrCreateDatabaseKey();

  /// PRAGMA rekey seam; no UI in v1. Persists [newKey] as the stored device
  /// key. The caller owns the database side: issue
  /// `PRAGMA rekey = "x'<hex>'"` on the live connection, then call this.
  /// Also used by bootstrap for the §7.3 db-absent/key-present overwrite.
  Future<void> rekeyDatabase(Uint8List newKey);

  /// ONLY from the workspace-reset flow (and recovery start-fresh, which is a
  /// workspace reset).
  Future<void> destroyDatabaseKey();
}

/// Production [KeyManager] over `flutter_secure_storage` ^11.
///
/// Posture (normative, §7.1): iOS `first_unlock_this_device` — background
/// writes keep working after the device re-locks, the key stays sealed on a
/// never-unlocked stolen device, and the key is non-migratable (never enters
/// iCloud Keychain or device transfer). Android: Keystore-wrapped AES-GCM
/// encrypted preferences — in v11 this is the package's only Android backend
/// (the v9 `encryptedSharedPreferences: true` flag no longer exists);
/// `resetOnError: false` because silently erasing the key on a transient
/// Keystore error would destroy the workspace (§7.3 forbids silent data
/// loss — a broken key must surface as `/recovery`, not as a wipe).
final class SecureStorageKeyManager implements KeyManager {
  SecureStorageKeyManager({FlutterSecureStorage? storage, Random? random})
    : _storage = storage ?? _defaultStorage,
      _random = random;

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(resetOnError: false),
  );

  final FlutterSecureStorage _storage;
  final Random? _random;

  @override
  Future<bool> hasDatabaseKey() =>
      _storage.containsKey(key: databaseKeyStorageName);

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async {
    final stored = await _storage.read(key: databaseKeyStorageName);
    if (stored != null) {
      final key = _decodeStored(stored);
      return key;
    }
    final key = generateDatabaseKey(random: _random);
    await _storage.write(key: databaseKeyStorageName, value: hexEncode(key));
    return key;
  }

  @override
  Future<void> rekeyDatabase(Uint8List newKey) async {
    _requireKeyLength(newKey);
    await _storage.write(key: databaseKeyStorageName, value: hexEncode(newKey));
  }

  @override
  Future<void> destroyDatabaseKey() =>
      _storage.delete(key: databaseKeyStorageName);

  Uint8List _decodeStored(String stored) {
    if (stored.length != 64) {
      throw StateError('stored database key is malformed');
    }
    final Uint8List key;
    try {
      key = hexDecode(stored);
    } on FormatException {
      throw StateError('stored database key is malformed');
    }
    return key;
  }

  static void _requireKeyLength(Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError.value(
        key.length,
        'newKey',
        'database key must be exactly 32 bytes',
      );
    }
  }
}

/// Host-test / composition [KeyManager]; no platform channels.
final class InMemoryKeyManager implements KeyManager {
  InMemoryKeyManager({Uint8List? initialKey, Random? random})
    : _key = initialKey == null ? null : Uint8List.fromList(initialKey),
      _random = random;

  Uint8List? _key;
  final Random? _random;

  @override
  Future<bool> hasDatabaseKey() async => _key != null;

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async =>
      Uint8List.fromList(_key ??= generateDatabaseKey(random: _random));

  @override
  Future<void> rekeyDatabase(Uint8List newKey) async {
    SecureStorageKeyManager._requireKeyLength(newKey);
    _key = Uint8List.fromList(newKey);
  }

  @override
  Future<void> destroyDatabaseKey() async => _key = null;
}
