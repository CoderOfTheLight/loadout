/// Content-free diagnostics seam (design §10).
///
/// The API has no free-text parameter, so a log line physically cannot carry
/// item names, quantities, recipe text, file paths, SQL, or exception
/// messages. Allowed per event: the code itself, integer counts/durations,
/// an exception *type name*, and a schema version.
library;

/// Closed set — additions are code-reviewed.
enum DiagEvent {
  dbOpenOk,
  dbOpenWrongKey,
  dbKeyMissing,
  dbCipherMissing,
  backupCreateOk,
  backupCreateFail,
  backupValidateFail,
  restoreOk,
  restoreRolledBack,
  scratchSweepOk,
  migrationOk,
  migrationFail,
  commandApplied,
  commandRejected,
}

abstract interface class Diag {
  void event(
    DiagEvent event, {
    int? count,
    Duration? elapsed,
    String? errorType,
    int? schemaVersion,
  });
}

/// Default sink for tests and for wiring before the file/ring sink exists.
final class NoopDiag implements Diag {
  const NoopDiag();

  @override
  void event(
    DiagEvent event, {
    int? count,
    Duration? elapsed,
    String? errorType,
    int? schemaVersion,
  }) {}
}
