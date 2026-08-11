/// UTC epoch microseconds. Every persisted `*_at_micros` column stores one of
/// these; microsecond precision is required by the `recordedAt` monotonic
/// tie-bump contract (design §3, §6.3).
extension type const Instant(int epochMicrosUtc) implements Object {}

abstract interface class Clock {
  Instant now();
}

/// Production clock.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  Instant now() => Instant(DateTime.now().toUtc().microsecondsSinceEpoch);
}

/// Deterministic clock for tests; time moves only when told to.
final class FixedClock implements Clock {
  FixedClock(Instant initial) : _now = initial;
  Instant _now;

  @override
  Instant now() => _now;

  void set(Instant value) => _now = value;

  void advanceMicros(int micros) =>
      _now = Instant(_now.epochMicrosUtc + micros);
}
