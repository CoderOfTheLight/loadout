/// Minimal STORED-only zip writer/reader for the §8.1 backup container.
///
/// The design pins the container to zip with STORED entries (no compression;
/// ciphertext doesn't compress). `package:archive` is not in the committed
/// dependency set, so this file implements the tiny required subset of the
/// format directly: local file headers, central directory, and end-of-
/// central-directory record. Any compressed, encrypted, zip64, or
/// multi-disk container is rejected — the reader exists for Loadout backups
/// only.
library;

import 'dart:typed_data';

final class StoredZipEntry {
  const StoredZipEntry({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

final class StoredZipFormatException implements Exception {
  const StoredZipFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'StoredZipFormatException($reason)';
}

const int _localHeaderSignature = 0x04034b50;
const int _centralHeaderSignature = 0x02014b50;
const int _eocdSignature = 0x06054b50;

/// Serializes [entries] as a STORED zip. Entry names must be ASCII.
Uint8List writeStoredZip(List<StoredZipEntry> entries) {
  final builder = BytesBuilder(copy: false);
  final centralRecords = <Uint8List>[];

  for (final entry in entries) {
    final nameBytes = _asciiName(entry.name);
    final crc = crc32(entry.bytes);
    final offset = builder.length;

    final local = ByteData(30);
    local.setUint32(0, _localHeaderSignature, Endian.little);
    local.setUint16(4, 20, Endian.little); // version needed
    local.setUint16(6, 0, Endian.little); // flags
    local.setUint16(8, 0, Endian.little); // method: STORED
    local.setUint16(10, 0, Endian.little); // mod time
    local.setUint16(12, 0x21, Endian.little); // mod date (1980-01-01)
    local.setUint32(14, crc, Endian.little);
    local.setUint32(18, entry.bytes.length, Endian.little);
    local.setUint32(22, entry.bytes.length, Endian.little);
    local.setUint16(26, nameBytes.length, Endian.little);
    local.setUint16(28, 0, Endian.little); // extra length
    builder
      ..add(local.buffer.asUint8List())
      ..add(nameBytes)
      ..add(entry.bytes);

    final central = ByteData(46);
    central.setUint32(0, _centralHeaderSignature, Endian.little);
    central.setUint16(4, 20, Endian.little); // version made by
    central.setUint16(6, 20, Endian.little); // version needed
    central.setUint16(8, 0, Endian.little); // flags
    central.setUint16(10, 0, Endian.little); // method: STORED
    central.setUint16(12, 0, Endian.little); // mod time
    central.setUint16(14, 0x21, Endian.little); // mod date
    central.setUint32(16, crc, Endian.little);
    central.setUint32(20, entry.bytes.length, Endian.little);
    central.setUint32(24, entry.bytes.length, Endian.little);
    central.setUint16(28, nameBytes.length, Endian.little);
    // 30..40: extra/comment lengths, disk, attributes — all zero.
    central.setUint32(42, offset, Endian.little);
    final record = BytesBuilder(copy: false)
      ..add(central.buffer.asUint8List())
      ..add(nameBytes);
    centralRecords.add(record.takeBytes());
  }

  final centralOffset = builder.length;
  for (final record in centralRecords) {
    builder.add(record);
  }
  final centralSize = builder.length - centralOffset;

  final eocd = ByteData(22);
  eocd.setUint32(0, _eocdSignature, Endian.little);
  eocd.setUint16(8, entries.length, Endian.little);
  eocd.setUint16(10, entries.length, Endian.little);
  eocd.setUint32(12, centralSize, Endian.little);
  eocd.setUint32(16, centralOffset, Endian.little);
  builder.add(eocd.buffer.asUint8List());
  return builder.takeBytes();
}

/// Parses a STORED zip produced by [writeStoredZip] (or any single-disk,
/// uncompressed, unencrypted zip). Throws [StoredZipFormatException] on
/// anything else, including truncation.
List<StoredZipEntry> readStoredZip(Uint8List bytes) {
  final eocdOffset = _findEocd(bytes);
  final eocd = ByteData.sublistView(bytes, eocdOffset);
  final diskNumber = eocd.getUint16(4, Endian.little);
  final centralDisk = eocd.getUint16(6, Endian.little);
  final entryCount = eocd.getUint16(10, Endian.little);
  final centralOffset = eocd.getUint32(16, Endian.little);
  if (diskNumber != 0 || centralDisk != 0) {
    throw const StoredZipFormatException('multi-disk zip');
  }

  final entries = <StoredZipEntry>[];
  var cursor = centralOffset;
  for (var i = 0; i < entryCount; i++) {
    if (cursor + 46 > bytes.length) {
      throw const StoredZipFormatException('truncated central directory');
    }
    final central = ByteData.sublistView(bytes, cursor);
    if (central.getUint32(0, Endian.little) != _centralHeaderSignature) {
      throw const StoredZipFormatException('bad central directory signature');
    }
    final flags = central.getUint16(8, Endian.little);
    final method = central.getUint16(10, Endian.little);
    final compressedSize = central.getUint32(20, Endian.little);
    final size = central.getUint32(24, Endian.little);
    final nameLength = central.getUint16(28, Endian.little);
    final extraLength = central.getUint16(30, Endian.little);
    final commentLength = central.getUint16(32, Endian.little);
    final localOffset = central.getUint32(42, Endian.little);
    if (method != 0 || compressedSize != size) {
      throw const StoredZipFormatException('entry is not STORED');
    }
    if (flags & 0x1 != 0) {
      throw const StoredZipFormatException('encrypted zip entry');
    }
    if (cursor + 46 + nameLength > bytes.length) {
      throw const StoredZipFormatException('truncated entry name');
    }
    final name = String.fromCharCodes(
      bytes.sublist(cursor + 46, cursor + 46 + nameLength),
    );

    if (localOffset + 30 > bytes.length) {
      throw const StoredZipFormatException('truncated local header');
    }
    final local = ByteData.sublistView(bytes, localOffset);
    if (local.getUint32(0, Endian.little) != _localHeaderSignature) {
      throw const StoredZipFormatException('bad local header signature');
    }
    final localNameLength = local.getUint16(26, Endian.little);
    final localExtraLength = local.getUint16(28, Endian.little);
    final dataStart = localOffset + 30 + localNameLength + localExtraLength;
    if (dataStart + size > bytes.length) {
      throw const StoredZipFormatException('truncated entry data');
    }
    entries.add(
      StoredZipEntry(
        name: name,
        bytes: Uint8List.sublistView(bytes, dataStart, dataStart + size),
      ),
    );
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

int _findEocd(Uint8List bytes) {
  if (bytes.length < 22) {
    throw const StoredZipFormatException('too short for a zip');
  }
  final floor = bytes.length - 22 - 0xffff < 0 ? 0 : bytes.length - 22 - 0xffff;
  for (var i = bytes.length - 22; i >= floor; i--) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      return i;
    }
  }
  throw const StoredZipFormatException('end-of-central-directory not found');
}

Uint8List _asciiName(String name) {
  final units = name.codeUnits;
  for (final unit in units) {
    if (unit < 0x20 || unit > 0x7e) {
      throw ArgumentError.value(name, 'name', 'entry names must be ASCII');
    }
  }
  return Uint8List.fromList(units);
}

final List<int> _crcTable = _buildCrcTable();

List<int> _buildCrcTable() {
  final table = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

/// Standard CRC-32 (IEEE 802.3), as used by the zip format.
int crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
