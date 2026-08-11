/// Container codec tests (§8.1): STORED zip round-trip, truncation and
/// non-STORED rejection, CRC-32 reference vector.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/infrastructure/backup/stored_zip.dart';

void main() {
  test('round-trips entries byte-for-byte', () {
    final manifest = Uint8List.fromList(utf8.encode('{"format":"x"}'));
    final payload = Uint8List.fromList(
      List.generate(70000, (i) => (i * 31) & 0xff),
    );
    final zipped = writeStoredZip([
      StoredZipEntry(name: 'manifest.json', bytes: manifest),
      StoredZipEntry(name: 'payload.db', bytes: payload),
    ]);
    final read = readStoredZip(zipped);
    expect(read, hasLength(2));
    expect(read[0].name, 'manifest.json');
    expect(read[0].bytes, manifest);
    expect(read[1].name, 'payload.db');
    expect(read[1].bytes, payload);
  });

  test('output is a real zip (magic + EOCD present)', () {
    final zipped = writeStoredZip([
      StoredZipEntry(name: 'a', bytes: Uint8List.fromList([1])),
    ]);
    expect(zipped.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
    expect(zipped.sublist(zipped.length - 22, zipped.length - 18), [
      0x50,
      0x4b,
      0x05,
      0x06,
    ]);
  });

  test('truncation is rejected', () {
    final zipped = writeStoredZip([
      StoredZipEntry(
        name: 'payload.db',
        bytes: Uint8List.fromList(List.filled(4096, 7)),
      ),
    ]);
    for (final keep in [10, zipped.length - 1, zipped.length - 30]) {
      expect(
        () => readStoredZip(Uint8List.sublistView(zipped, 0, keep)),
        throwsA(isA<StoredZipFormatException>()),
        reason: 'kept $keep bytes',
      );
    }
  });

  test('compressed entries are rejected', () {
    final zipped = writeStoredZip([
      StoredZipEntry(name: 'a', bytes: Uint8List.fromList([1, 2, 3])),
    ]);
    // Patch the central directory's compression method to 8 (DEFLATE).
    final tampered = Uint8List.fromList(zipped);
    for (var i = 0; i + 4 <= tampered.length; i++) {
      if (tampered[i] == 0x50 &&
          tampered[i + 1] == 0x4b &&
          tampered[i + 2] == 0x01 &&
          tampered[i + 3] == 0x02) {
        tampered[i + 10] = 8;
        break;
      }
    }
    expect(
      () => readStoredZip(tampered),
      throwsA(isA<StoredZipFormatException>()),
    );
  });

  test('non-ASCII entry names are refused at write time', () {
    expect(
      () => writeStoredZip([
        StoredZipEntry(name: 'påyload', bytes: Uint8List(0)),
      ]),
      throwsArgumentError,
    );
  });

  test('crc32 matches the reference vector', () {
    // The canonical CRC-32/ISO-HDLC check value.
    expect(crc32(Uint8List.fromList(ascii.encode('123456789'))), 0xcbf43926);
    expect(crc32(Uint8List(0)), 0);
  });
}
