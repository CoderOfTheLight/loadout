import 'errors.dart';

/// Expected-outcome carrier for the application boundary (design §6.1).
sealed class Result<T> {
  const Result();
  R fold<R>(R Function(T value) onOk, R Function(DomainError error) onErr);
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  @override
  R fold<R>(R Function(T value) onOk, R Function(DomainError error) onErr) =>
      onOk(value);
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final DomainError error;

  @override
  R fold<R>(R Function(T value) onOk, R Function(DomainError error) onErr) =>
      onErr(error);
}
