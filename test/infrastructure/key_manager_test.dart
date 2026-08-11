/// Key material contracts (§7.1): 32-byte CSPRNG keys, 64-hex round-trip,
/// rekey/destroy lifecycle on the in-memory manager used by host tests.
/// (The flutter_secure_storage-backed manager is platform-channel code and is
/// covered by the same interface; its option posture is asserted at review.)
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/infrastructure/security/hex.dart';
import 'package:loadout/infrastructure/security/key_manager.dart';

void main() {
  test('generateDatabaseKey returns 32 fresh bytes', () {
    final a = generateDatabaseKey(random: Random(1));
    final b = generateDatabaseKey(random: Random(2));
    expect(a, hasLength(32));
    expect(b, hasLength(32));
    expect(a, isNot(equals(b)));
  });

  test('hex round-trip is lossless and 64 lowercase chars', () {
    final key = generateDatabaseKey(random: Random(3));
    final hex = hexEncode(key);
    expect(hex, hasLength(64));
    expect(hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(hexDecode(hex), key);
  });

  test('hexDecode rejects malformed input', () {
    expect(() => hexDecode('abc'), throwsFormatException);
    expect(() => hexDecode('zz'), throwsFormatException);
  });

  group('InMemoryKeyManager lifecycle', () {
    test('getOrCreate creates once and is stable', () async {
      final manager = InMemoryKeyManager(random: Random(4));
      expect(await manager.hasDatabaseKey(), isFalse);
      final first = await manager.getOrCreateDatabaseKey();
      expect(await manager.hasDatabaseKey(), isTrue);
      final second = await manager.getOrCreateDatabaseKey();
      expect(second, first);
    });

    test('rekey replaces the stored key and validates length', () async {
      final manager = InMemoryKeyManager(random: Random(5));
      final original = await manager.getOrCreateDatabaseKey();
      final replacement = generateDatabaseKey(random: Random(6));
      await manager.rekeyDatabase(replacement);
      expect(await manager.getOrCreateDatabaseKey(), replacement);
      expect(await manager.getOrCreateDatabaseKey(), isNot(equals(original)));
      expect(() => manager.rekeyDatabase(Uint8List(31)), throwsArgumentError);
    });

    test('destroy removes the key; next getOrCreate mints a new one', () async {
      final manager = InMemoryKeyManager(random: Random(7));
      final first = await manager.getOrCreateDatabaseKey();
      await manager.destroyDatabaseKey();
      expect(await manager.hasDatabaseKey(), isFalse);
      final second = await manager.getOrCreateDatabaseKey();
      expect(second, isNot(equals(first)));
    });
  });
}
