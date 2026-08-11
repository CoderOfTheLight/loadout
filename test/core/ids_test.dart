import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';

const crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

void main() {
  test('ULIDs are 26 Crockford base32 characters', () {
    for (var i = 0; i < 100; i++) {
      final id = newUlid();
      expect(id.length, 26);
      for (final unit in id.codeUnits) {
        expect(
          crockford.contains(String.fromCharCode(unit)),
          isTrue,
          reason: 'unexpected character in $id',
        );
      }
    }
  });

  test('ULIDs are unique and strictly ascending in generation order', () {
    final ids = List.generate(5000, (_) => newUlid());
    expect(ids.toSet().length, ids.length);
    for (var i = 1; i < ids.length; i++) {
      expect(
        ids[i].compareTo(ids[i - 1]),
        greaterThan(0),
        reason: 'monotonic generation must sort strictly ascending',
      );
    }
  });

  test('same-millisecond ULIDs increment monotonically', () {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final ids = List.generate(1000, (_) => newUlid(nowMillis: now));
    for (var i = 1; i < ids.length; i++) {
      expect(ids[i].compareTo(ids[i - 1]), greaterThan(0));
      // Same millisecond: the 10-char time prefix must not change.
      expect(ids[i].substring(0, 10), ids[i - 1].substring(0, 10));
    }
  });

  test('later milliseconds sort after earlier ones', () {
    final base = DateTime.now().toUtc().millisecondsSinceEpoch;
    final a = newUlid(nowMillis: base + 60000);
    final b = newUlid(nowMillis: base + 120000);
    expect(b.compareTo(a), greaterThan(0));
    expect(a.substring(0, 10) == b.substring(0, 10), isFalse);
  });

  test('clock going backwards still yields ascending ids', () {
    final base = DateTime.now().toUtc().millisecondsSinceEpoch + 300000;
    final a = newUlid(nowMillis: base);
    final b = newUlid(nowMillis: base - 250000); // skew: earlier clock
    expect(b.compareTo(a), greaterThan(0));
  });

  test('rejects timestamps outside the 48-bit range', () {
    expect(() => newUlid(nowMillis: -1), throwsArgumentError);
    expect(() => newUlid(nowMillis: 0x1000000000000), throwsArgumentError);
  });

  // Runs LAST in this file: it pushes the process-wide monotonic state to the
  // maximum timestamp, which would pin every later id to that prefix.
  test('maximum 48-bit timestamp encodes to the documented prefix', () {
    final id = newUlid(nowMillis: 0xFFFFFFFFFFFF);
    expect(id.substring(0, 10), '7ZZZZZZZZZ');
  });

  test('UlidIdGenerator produces valid ULIDs', () {
    const generator = UlidIdGenerator();
    final id = generator.newId();
    expect(id.length, 26);
  });
}
