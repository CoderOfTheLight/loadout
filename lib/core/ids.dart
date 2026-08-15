import 'dart:math';
import 'dart:typed_data';

/// Crockford base32 alphabet. Its characters are in ascending ASCII order, so
/// lexicographic ULID comparison equals numeric (chronological) comparison:
/// `ORDER BY id` is insert order and `MAX(id)` is "latest" (design §3).
const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

const int _timeChars = 10; // 48 bits of milliseconds, 5 bits per char.
const int _entropyBytes = 10; // 80 bits of Random.secure() entropy.
const int _maxMillis = 0xFFFFFFFFFFFF; // 2^48 - 1.

final Random _secureRandom = Random.secure();
int _lastMillis = -1;
final Uint8List _lastEntropy = Uint8List(_entropyBytes);

/// Monotonic ULID: 26 chars, Crockford base32, `Random.secure()` entropy.
///
/// Monotonic within the process: a call in the same (or an earlier —
/// clock-skew defense) millisecond as the previous call reuses the previous
/// timestamp and increments the previous entropy by one, so ids from one
/// process always sort strictly ascending in generation order.
String newUlid({int? nowMillis}) {
  var millis = nowMillis ?? DateTime.now().toUtc().millisecondsSinceEpoch;
  if (millis < 0 || millis > _maxMillis) {
    throw ArgumentError.value(
      nowMillis,
      'nowMillis',
      'must fit the 48-bit ULID timestamp',
    );
  }
  if (millis <= _lastMillis) {
    millis = _lastMillis;
    _incrementEntropy();
  } else {
    _lastMillis = millis;
    for (var i = 0; i < _entropyBytes; i++) {
      _lastEntropy[i] = _secureRandom.nextInt(256);
    }
  }

  final units = List<int>.filled(26, 0);
  for (var i = 0; i < _timeChars; i++) {
    units[i] = _crockford.codeUnitAt((millis >> (45 - 5 * i)) & 0x1f);
  }
  var buffer = 0;
  var bits = 0;
  var out = _timeChars;
  for (var i = 0; i < _entropyBytes; i++) {
    buffer = (buffer << 8) | _lastEntropy[i];
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      units[out++] = _crockford.codeUnitAt((buffer >> bits) & 0x1f);
    }
  }
  return String.fromCharCodes(units);
}

void _incrementEntropy() {
  for (var i = _entropyBytes - 1; i >= 0; i--) {
    if (_lastEntropy[i] != 0xff) {
      _lastEntropy[i]++;
      return;
    }
    _lastEntropy[i] = 0;
  }
  // 2^80 generations within a single millisecond.
  throw StateError('ULID entropy overflow');
}

extension type const ItemId(String value) implements Object {}

extension type const FolderId(String value) implements Object {}

extension type const EventId(String value) implements Object {}

extension type const MovementId(String value) implements Object {}

extension type const RecipeId(String value) implements Object {}

extension type const RecipeRevisionId(String value) implements Object {}

extension type const CloseoutId(String value) implements Object {}

extension type const ForecastSnapshotId(String value) implements Object {}

extension type const CommandId(String value) implements Object {}

abstract interface class IdGenerator {
  String newId(); // production: newUlid(); tests: sequential 26-char ids
}

/// Production [IdGenerator].
final class UlidIdGenerator implements IdGenerator {
  const UlidIdGenerator();

  @override
  String newId() => newUlid();
}
