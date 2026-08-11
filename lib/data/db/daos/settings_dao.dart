import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

/// Workspace meta and settings access. Preference upserts are an explicit
/// exception to the command path (design §6.4) and land with SettingsService.
@DriftAccessor(tables: [WorkspaceMeta, Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// JSON-encoded scalar for [key], or null when unset.
  Future<String?> value(String key) async {
    final row = await (select(
      settings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return row?.value;
  }
}
