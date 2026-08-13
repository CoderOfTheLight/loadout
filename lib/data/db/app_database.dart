import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../core/ids.dart';
import 'daos/closeout_dao.dart';
import 'daos/command_dao.dart';
import 'daos/event_dao.dart';
import 'daos/forecast_dao.dart';
import 'daos/item_dao.dart';
import 'daos/ledger_dao.dart';
import 'daos/recipe_dao.dart';
import 'daos/settings_dao.dart';
import 'schema_sql.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Seeded into `workspace_meta.created_by_app_version`. Keep in sync with
/// pubspec.yaml; runtime version lookup is deliberately absent (no
/// package_info dependency in v1).
const String seedAppVersion = '1.0.0+1';

@DriftDatabase(
  tables: [
    WorkspaceMeta,
    Settings,
    Commands,
    Items,
    Events,
    EventItems,
    InventoryMovements,
    EventCloseouts,
    CloseoutLines,
    CloseoutDrafts,
    Recipes,
    RecipeRevisions,
    RecipeLines,
    ForecastSnapshots,
    ForecastLines,
    ForecastEvidence,
    ForecastOverrides,
  ],
  daos: [
    LedgerDao,
    EventDao,
    CloseoutDao,
    ItemDao,
    RecipeDao,
    ForecastDao,
    CommandDao,
    SettingsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Production path: the executor is injected (key management and the
  /// SQLCipher open path live in lib/infrastructure/, design §7).
  AppDatabase(super.executor);

  AppDatabase.forTesting(NativeDatabase super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final sql in schemaV1Indices) {
        await customStatement(sql);
      }
      for (final sql in schemaV1Triggers) {
        await customStatement(sql);
      }
      await _seedV1(); // same transaction
    },
    onUpgrade: (m, from, to) async {
      // Stepwise, additive only: every block is ALTER TABLE ... ADD COLUMN
      // on a nullable column, so existing rows keep every byte they had and
      // no append-only table is rewritten. Before any real onUpgrade,
      // bootstrap makes a plain file copy of the (already
      // device-key-encrypted) db to db/pre-migration-v<from>.db; deleted on
      // success. No passphrase involved.
      if (from < 2) {
        // v2: an item is NAME + HOW MANY + optionally HOW MANY ONE SERVES.
        // `unit`/`pack_size_micros` keep their v1 values on existing rows
        // and stop being surfaced; new items are always 'each' / one unit.
        await m.addColumn(items, items.servesPerUnitMicros);
        // v2: the no-history "1 serves N" baseline plan, stored alongside —
        // never inside — the frozen engine's outputs.
        await m.addColumn(
          forecastLines,
          forecastLines.baselineServesPerUnitMicros,
        );
        await m.addColumn(
          forecastLines,
          forecastLines.baselineExpectedUseMicros,
        );
        await m.addColumn(forecastLines, forecastLines.baselinePlannedMicros);
        await m.addColumn(forecastLines, forecastLines.baselineLoadMicros);
        await m.addColumn(forecastLines, forecastLines.baselineAcquireMicros);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Seeds ONLY the workspace_meta singleton and default settings (§4.2).
  /// There are no unit tables; the unit enum lives in Dart and in the
  /// `items.unit` CHECK.
  Future<void> _seedV1() async {
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    await into(workspaceMeta).insert(
      WorkspaceMetaCompanion.insert(
        id: const Value(1),
        workspaceUid: newUlid(),
        createdAtMicros: nowMicros,
        createdByAppVersion: seedAppVersion,
      ),
    );
    const defaults = <String, String>{
      'planning_policy_default': '"balanced"',
      'exposure_label': '"attendance"',
      'history_window_events': '12',
      'seeded_v1': 'true',
    };
    for (final entry in defaults.entries) {
      await into(settings).insert(
        SettingsCompanion.insert(
          key: entry.key,
          value: entry.value,
          updatedAtMicros: nowMicros,
        ),
      );
    }
  }
}
