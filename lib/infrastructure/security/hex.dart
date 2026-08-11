import 'dart:typed_data';

const String _hexDigits = '0123456789abcdef';

/// Lowercase hex encoding; a 32-byte key becomes 64 lowercase hex chars
/// (design §7.1/§7.2).
String hexEncode(Uint8List bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out
      ..write(_hexDigits[(b >> 4) & 0xf])
      ..write(_hexDigits[b & 0xf]);
  }
  return out.toString();
}

/// Strict inverse of [hexEncode]; accepts upper- or lowercase digits.
Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('hex string must have even length');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(hex.substring(2 * i, 2 * i + 2), radix: 16);
    if (byte == null) {
      throw FormatException('invalid hex digit');
    }
    out[i] = byte;
  }
  return out;
}
