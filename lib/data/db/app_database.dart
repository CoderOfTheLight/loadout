import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../core/folder_appearance.dart';
import '../../core/ids.dart';
import 'daos/closeout_dao.dart';
import 'daos/command_dao.dart';
import 'daos/event_dao.dart';
import 'daos/folder_dao.dart';
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
    Folders,
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
    RecipeLinesV2,
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
    FolderDao,
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
  int get schemaVersion => 5;

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
      for (final sql in schemaV3Indices) {
        await customStatement(sql);
      }
      for (final sql in schemaV5RecipeLinesV2Triggers) {
        await customStatement(sql);
      }
      await _seedV1(); // same transaction
      await _seedStarterFolders(); // fresh workspaces only — see below
    },
    onUpgrade: (m, from, to) async {
      // ATOMIC, or not at all. The v5 rollout proved why: the first launch
      // on a real phone applied ADD COLUMN unit_label, failed later in the
      // block, and — with no transaction — left the change behind with
      // user_version still 4. Every subsequent launch re-ran the block,
      // hit "duplicate column name", and died before the first frame: a
      // white screen with the owner's data intact but unreachable.
      //
      // So: foreign-key enforcement is suspended OUTSIDE the transaction
      // (pragmas are silently ignored inside one), every step runs INSIDE
      // it, and a failure at any step rolls the file back to exactly the
      // bytes it arrived with. beforeOpen re-asserts foreign_keys = ON on
      // this connection afterwards; the finally is for the failure path.
      await customStatement('PRAGMA foreign_keys = OFF');
      try {
        await transaction(() => _migrationSteps(m, from, to));
        final violations = await customSelect('PRAGMA foreign_key_check').get();
        if (violations.isNotEmpty) {
          throw StateError(
            'migration left ${violations.length} dangling reference(s)',
          );
        }
      } finally {
        await customStatement('PRAGMA foreign_keys = ON');
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

  /// Stepwise migration body, run inside one transaction by [migration].
  ///
  /// Each block checks `to` as well as `from`: production always upgrades
  /// to the latest version, but the SchemaVerifier migration tests stop at
  /// intermediate versions and must get exactly that version's schema.
  ///
  /// The v5 block is RE-ENTRANT on purpose: phones stranded by the
  /// pre-atomic v5 rollout carry part of it (user_version 4, unit_label
  /// present), and this block completes the remainder instead of tripping
  /// over its own earlier steps. Additive blocks before it stay plain —
  /// under the transaction they can no longer strand anything.
  Future<void> _migrationSteps(Migrator m, int from, int to) async {
    if (from < 2 && to >= 2) {
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
      await m.addColumn(forecastLines, forecastLines.baselineExpectedUseMicros);
      await m.addColumn(forecastLines, forecastLines.baselinePlannedMicros);
      await m.addColumn(forecastLines, forecastLines.baselineLoadMicros);
      await m.addColumn(forecastLines, forecastLines.baselineAcquireMicros);
    }
    if (from < 3 && to >= 3) {
      // v3: folders + the one-question demand basis. The folders table is
      // new (created empty — a MIGRATED workspace gets folders from the
      // owner's tidy-up flow, never from migration); every items /
      // forecast_lines addition is a nullable column whose NULL means
      // "unanswered": unfiled, inherit, no baseline. Nothing moves, no
      // number changes, until the owner acts. Created from the frozen v3
      // SQL, not the migrator: the Dart table grew v4 columns, and this
      // block must land exactly v3 (see schemaV3FoldersCreate).
      await customStatement(schemaV3FoldersCreate);
      await m.addColumn(items, items.folderId);
      await m.addColumn(items, items.demandBasis);
      await m.addColumn(items, items.perEventBaselineMicros);
      await m.addColumn(items, items.perPersonNumerator);
      await m.addColumn(items, items.perPersonDenominator);
      await m.addColumn(forecastLines, forecastLines.demandBasis);
      await m.addColumn(forecastLines, forecastLines.baselinePerEventMicros);
      await m.addColumn(
        forecastLines,
        forecastLines.baselinePerPersonNumerator,
      );
      await m.addColumn(
        forecastLines,
        forecastLines.baselinePerPersonDenominator,
      );
      for (final sql in schemaV3Indices) {
        await customStatement(sql);
      }
    }
    if (from < 4 && to >= 4) {
      // v4: folder appearance (design-spec §3). Two nullable columns whose
      // NULL means "never chose": effective hue is assigned by position
      // order, effective icon by the starter-name table. Existing folders
      // keep every byte and simply render their effective defaults.
      await m.addColumn(folders, folders.hueName);
      await m.addColumn(folders, folders.iconName);
    }
    if (from < 5 && to >= 5) {
      // v5: unit labels + recipe decoupling. Three moves, each honest
      // about what its table is:
      //
      // (1) items.unit_label — plain nullable ADD COLUMN; every v4 row
      //     rides byte for byte, NULL = no label, nothing displays
      //     differently until the owner types one.
      if (!await _columnExists('items', 'unit_label')) {
        await m.addColumn(items, items.unitLabel);
      }
      // (2) recipe_lines is trigger-enforced APPEND-ONLY, so it can be
      //     neither widened (ingredient_item_id is NOT NULL) nor
      //     backfilled in place. recipe_lines_v2 supersedes it: created
      //     here, every legacy row COPIED in (INSERT is legal on an
      //     append-only table) with ingredient_name backfilled from the
      //     linked item's name and the link kept; the legacy table stays
      //     byte-intact as the historical record and stops being read.
      //     NOTE: createTable builds the CURRENT Dart shape — exactly v5
      //     today. If a later version alters this table, freeze this
      //     block to v5 SQL the way schemaV3FoldersCreate froze folders.
      if (!await _tableExists('recipe_lines_v2')) {
        await m.createTable(recipeLinesV2);
        for (final sql in schemaV5RecipeLinesV2Triggers) {
          await customStatement(sql);
        }
      }
      final v2HasRows = await customSelect(
        'SELECT 1 FROM recipe_lines_v2 LIMIT 1',
      ).get();
      if (v2HasRows.isEmpty) {
        await customStatement(schemaV5RecipeLinesBackfill);
      }
      // (3) recipes.output_item_id NOT NULL → NULLABLE ("not added to
      //     items yet"). recipes is mutable master data — no append-only
      //     triggers, absent from appendOnlyTables — so the documented
      //     SQLite copy-rewrite (drift TableMigration) is legal here;
      //     every row is copied byte for byte. The partial unique index
      //     drops with the old table and is recreated verbatim; NULLs
      //     never collide in it. Same current-Dart-shape caveat as (2).
      final outputStillNotNull = await customSelect(
        'SELECT 1 FROM pragma_table_info(?1) '
        "WHERE name = 'output_item_id' AND \"notnull\" = 1",
        variables: [Variable<String>('recipes')],
      ).get();
      if (outputStillNotNull.isNotEmpty) {
        await m.alterTable(TableMigration(recipes));
        await customStatement(schemaV5RecipesOutputIndex);
      }
    }
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect(
      'SELECT 1 FROM pragma_table_info(?1) WHERE name = ?2',
      variables: [Variable<String>(table), Variable<String>(column)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _tableExists(String name) async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
      variables: [Variable<String>(name)],
    ).get();
    return rows.isNotEmpty;
  }

  /// The eight starter folders, in packing order, with the answer each one
  /// gives to "does how much you bring depend on how many people come?".
  /// All renameable; the wording fits the kitchen AND the sales table.
  /// Disposables stay per_person on purpose — plates and napkins scale with
  /// the crowd; it is cleaning and setup gear that does not.
  static const starterFolders = <(String, String)>[
    ('Cooked on site', 'per_person'),
    ('Bought ready to serve', 'per_person'),
    ('Fresh produce', 'per_person'),
    ('Bakery', 'per_person'),
    ('Drinks', 'per_person'),
    ('Disposables', 'per_person'),
    ('Cleaning & setup', 'per_event'),
    ('Sales table', 'per_person'),
  ];

  /// Runs ONLY from onCreate: fresh workspaces start with the eight starter
  /// folders. Migrated workspaces never pass through here — their folders
  /// are created by the owner's tidy-up flow, and until then every existing
  /// item is Unfiled and forecasts are byte-identical to v2.
  /// `always_planned` starts false everywhere: "comes along to every event"
  /// is the owner's call, suggested on screen, never assumed.
  ///
  /// Each starter also gets its lead-reconciliation identity (v4): hue and
  /// icon from [starterFolderAppearance], each of the eight hues exactly
  /// once. Stored explicitly, not left to the effective defaults, so a
  /// renamed starter keeps the identity the owner has learned.
  Future<void> _seedStarterFolders() async {
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    for (var i = 0; i < starterFolders.length; i++) {
      final (name, basis) = starterFolders[i];
      final appearance = starterFolderAppearance[name]!;
      await into(folders).insert(
        FoldersCompanion.insert(
          id: newUlid(),
          name: name,
          position: i,
          demandBasis: basis,
          hueName: Value(appearance.hue.dbValue),
          iconName: Value(appearance.iconName),
          createdAtMicros: nowMicros,
          updatedAtMicros: nowMicros,
        ),
      );
    }
  }
}
