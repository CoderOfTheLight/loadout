/// §11.2: the backup KDF is pinned against the RFC 9106 Argon2id test vector
/// and the §8.1 production cost parameters are pinned as constants.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/infrastructure/backup/backup_service_impl.dart';
import 'package:loadout/infrastructure/security/hex.dart';

void main() {
  test(
    'DartArgon2id reproduces the RFC 9106 section 5.3 Argon2id vector',
    () async {
      // RFC 9106 §5.3: p=4, T=32, m=32, t=3, v=0x13,
      // password 32x01, salt 16x02, secret 8x03, associated data 12x04.
      final algorithm = DartArgon2id(
        parallelism: 4,
        memory: 32,
        iterations: 3,
        hashLength: 32,
      );
      final key = await algorithm.deriveKey(
        secretKey: SecretKey(List.filled(32, 0x01)),
        nonce: List.filled(16, 0x02),
        optionalSecret: List.filled(8, 0x03),
        associatedData: List.filled(12, 0x04),
      );
      expect(
        hexEncode(Uint8List.fromList(await key.extractBytes())),
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    },
  );

  test('production cost parameters match §8.1 exactly', () {
    const cost = Argon2Cost.production;
    expect(cost.memoryKiB, 19456);
    expect(cost.iterations, 3);
    expect(cost.parallelism, 1);
    expect(cost.hashLength, 32);
  });

  test(
    'deriveBackupKey is deterministic in (passphrase, salt) and 32 bytes',
    () async {
      const cost = Argon2Cost(
        memoryKiB: 32,
        iterations: 1,
        parallelism: 1,
        hashLength: 32,
      );
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final a = await deriveBackupKey(
        passphrase: 'correct horse',
        salt: salt,
        cost: cost,
      );
      final b = await deriveBackupKey(
        passphrase: 'correct horse',
        salt: salt,
        cost: cost,
      );
      final c = await deriveBackupKey(
        passphrase: 'correct horsf',
        salt: salt,
        cost: cost,
      );
      expect(a, hasLength(32));
      expect(b, a);
      expect(c, isNot(equals(a)));
    },
  );
}
