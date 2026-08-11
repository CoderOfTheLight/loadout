import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/core/ids.dart';

/// Deterministic 26-char sequential ids ('...0001', '...0002', …).
/// Lexicographic order equals generation order, like real ULIDs.
final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator({this.prefix = ''});

  final String prefix;
  int _next = 0;

  @override
  String newId() {
    _next++;
    final tail = '$_next';
    final id = '$prefix$tail'.padLeft(26, '0');
    assert(id.length == 26);
    return id;
  }
}

final class DiagRecord {
  const DiagRecord(this.event, {this.count, this.errorType});

  final DiagEvent event;
  final int? count;
  final String? errorType;
}

/// Captures every diagnostics event for assertions.
final class RecordingDiag implements Diag {
  final List<DiagRecord> records = [];

  @override
  void event(
    DiagEvent event, {
    int? count,
    Duration? elapsed,
    String? errorType,
    int? schemaVersion,
  }) {
    records.add(DiagRecord(event, count: count, errorType: errorType));
  }

  List<DiagRecord> ofType(DiagEvent event) => [
    for (final r in records)
      if (r.event == event) r,
  ];
}
