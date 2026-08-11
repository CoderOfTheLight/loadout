/// Domain error taxonomy (design §6.1). `DomainError.code` is a stable machine
/// string; expected outcomes crossing the application boundary return
/// `Result<T>` carrying one of these. Programmer errors throw instead
/// (`ArgumentError`, `StateError`, [QuantityOverflowError]).
sealed class DomainError {
  const DomainError();
  String get code;
  String get message;
}

final class NotFoundError extends DomainError {
  const NotFoundError(this.message);
  @override
  String get code => 'NOT_FOUND';
  @override
  final String message;
}

final class DuplicateIdError extends DomainError {
  const DuplicateIdError(this.message);
  @override
  String get code => 'DUPLICATE_ID';
  @override
  final String message;
}

final class ValidationError extends DomainError {
  const ValidationError(this.message);
  @override
  String get code => 'VALIDATION';
  @override
  final String message;
}

final class ImmutableRecordError extends DomainError {
  const ImmutableRecordError(this.message);
  @override
  String get code => 'IMMUTABLE_RECORD';
  @override
  final String message;
}

final class AlreadyReversedError extends DomainError {
  const AlreadyReversedError(this.message);
  @override
  String get code => 'ALREADY_REVERSED';
  @override
  final String message;
}

final class RecipeNestingError extends DomainError {
  const RecipeNestingError(this.message, {this.path = const []});
  @override
  String get code => 'RECIPE_NESTING';
  @override
  final String message;

  /// Item/recipe ids narrating the offending reference, when known.
  final List<String> path;
}

final class RecipeCycleError extends DomainError {
  const RecipeCycleError(this.message, {this.path = const []});
  @override
  String get code => 'RECIPE_CYCLE';
  @override
  final String message;

  /// Deterministic cycle path, when known.
  final List<String> path;
}

final class DomainOverflowError extends DomainError {
  const DomainOverflowError(this.message);
  @override
  String get code => 'OVERFLOW';
  @override
  final String message;
}

final class StaleStateError extends DomainError {
  const StaleStateError(this.message);
  @override
  String get code => 'STALE_STATE';
  @override
  final String message;
}

final class NotAvailableError extends DomainError {
  const NotAvailableError(this.message);
  @override
  String get code => 'NOT_AVAILABLE';
  @override
  final String message;
}

/// Programmer error: exact integer quantity arithmetic exceeded
/// `Quantity.maxMicros`. Thrown, never returned.
final class QuantityOverflowError extends Error {
  QuantityOverflowError(this.detail);
  final String detail;

  @override
  String toString() => 'QuantityOverflowError: $detail';
}
