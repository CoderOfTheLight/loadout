/// The app's real schema version, for test doubles that need it.
///
/// Read off an unopened [AppDatabase] exactly as production does
/// (`backup_providers._appSchemaVersion`) instead of being written out as a
/// literal — a literal silently turns every backup the app writes into a
/// "backup from a newer version" the moment the schema is bumped.
library;

import 'package:drift/native.dart';
import 'package:loadout/data/db/app_database.dart';

final int appSchemaVersionUnderTest = () {
  final probe = AppDatabase.forTesting(NativeDatabase.memory());
  final version = probe.schemaVersion;
  probe.close();
  return version;
}();
