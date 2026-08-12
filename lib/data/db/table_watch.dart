/// Table-change tickers for services that assemble a view from several
/// queries.
library;

import 'package:drift/drift.dart';

import 'app_database.dart';

extension TableWatch on AppDatabase {
  /// Emits once on subscription, then again whenever any of [tables] change.
  ///
  /// Drift caches query streams by statement text plus variables — NOT by
  /// `readsFrom`. Two watchers sharing one sentinel statement therefore share
  /// a single stream, and every later subscriber silently inherits the first
  /// one's invalidation set: its screen stops updating when its own tables
  /// change. [label] keeps each watcher's statement distinct; pass something
  /// unique per call site.
  Stream<void> watchTables(String label, Set<ResultSetImplementation> tables) {
    assert(
      label.isNotEmpty && !label.contains('\n'),
      'label must be a non-empty single line',
    );
    return customSelect('SELECT 1 AS one -- $label', readsFrom: tables).watch();
  }
}
