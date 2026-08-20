# Loadout — Gates 2–3 Design (Implementation Contract)

Status: accepted. This is the single authoritative design for Gate 2 (complete domain/database
and deterministic forecast engine) and Gate 3 (complete every workflow without AI). It is
self-contained: implement from this document plus the repository. Where this document and any
earlier working note disagree, this document wins.

---

## 1. Overview & principles

1. **Deterministic Dart is authoritative** (ADR 0001). Every recorded number is produced by
   synchronous, exact, integer-only Dart. SQL enforces *shape* (enums, signs, uniqueness,
   append-only); Dart enforces *semantics*.
2. **One write path.** Every record mutation is a sealed `WorkspaceCommand` validated by
   `CommandValidator` and applied by `CommandApplier` in one transaction, with a row in the
   `commands` audit table. Forms build commands today; FunctionGemma (Gate 4) will emit
   proposals of the same types.
3. **Append-only records; derived state.** Movements, closeouts, recipe revisions, forecast
   snapshots, and overrides are immutable rows enforced by SQL triggers. Corrections are new
   rows (reversals / superseding revisions). On-hand is always `SUM(delta_micros)` — never a
   stored stock column.
4. **Confirmed outcomes are the only forecast labels.** The history query reads exclusively the
   latest closeout revision of closed events. Predictions (`planned_exposure`), overrides, and
   snapshots are structurally unreachable from that query.
5. **Offline, encrypted, content-free.** No runtime network capability; SQLCipher at rest with a
   device-bound key; diagnostics physically cannot carry content; backups are
   passphrase-encrypted files the user saves.
6. **Quantities are micros** (`Quantity`, scale 1e6). No `REAL` column exists. No `double` ever
   touches a quantity.

File layout (features carry domain / application / infrastructure / presentation; cross-feature
infrastructure sits in `lib/infrastructure/`):

```
lib/core/                      quantity.dart (additive only), ids.dart, time.dart, unit_ratio.dart,
                               result.dart, errors.dart, quantity_codec.dart, diagnostics/diag.dart
lib/data/db/                   tables.dart, schema_sql.dart, app_database.dart, daos/
lib/infrastructure/            db/open_database.dart, security/key_manager.dart,
                               backup/backup_service_impl.dart, files/scratch_space.dart
lib/features/<feature>/domain|application|presentation/
lib/features/approval/domain/  commands.dart, proposal.dart, approval_service.dart,
                               command_validator.dart, command_applier.dart
lib/features/agent/domain/     seams.dart (LocalAgent, RecipeOcr declarations)
lib/features/backup/domain/    backup_service.dart
```

---

## 2. Package set + SQLCipher sourcing

`pubspec.yaml` dependencies (constraints as pinned in the repo; `pubspec.lock` is committed and
canonical):

```yaml
dependencies:
  drift: ^2.34.3
  sqlite3: ^3.5.1                  # provides SQLCipher itself via the hook below
  path_provider: ^2.1.6
  path: ^1.9.1
  flutter_secure_storage: ^11.0.0  # SQLCipher key in Keystore/Keychain
  crypto: ^3.0.7                   # ALL SHA-256 (inputs_hash, payload digest)
  cryptography: ^2.9.0             # Argon2id ONLY (backup KDF)
  archive: ^4.0.0                  # pure-Dart zip (backup container, STORED); add at Gate 3
  flutter_riverpod: ^2.6.1         # Riverpod 2.x API
  go_router: ^17.5.0
  flutter_file_dialog: ^3.3.2     # SAF / UIDocumentPicker save & pick, zero permissions

dev_dependencies:
  drift_dev: ^2.34.5
  build_runner: ^2.15.1

hooks:
  user_defines:
    sqlite3:
      source: sqlcipher            # package:sqlite3 builds/loads SQLCipher
```

**SQLCipher sourcing (normative).** SQLCipher comes from `package:sqlite3` itself via the
`hooks.user_defines` block above — prebuilt SQLCipher shared libraries are fetched at **build**
time (runtime stays fully offline); on Android/Windows/Linux the build links OpenSSL.
Native-asset loading is process-wide and works in every isolate automatically: there is **no**
`open.overrideFor` / `isolateSetup` step anywhere in the codebase. SQLCipher's BSD-style license
applies and must appear in the app's license page.

Rules:

- **Never add `sqlcipher_flutter_libs`** (end-of-life; `0.7.0+eol` is a no-op stub) **or
  `sqlite3_flutter_libs`**, `drift_flutter`, `sqflite`, or anything that transitively bundles a
  second native SQLite — the classic "silently unencrypted" failure. CI enforces:
  `! grep -E "^  (sqlite3_flutter_libs|sqlcipher_flutter_libs|drift_flutter|sqflite)" pubspec.lock`
  (the `! grep` form is required; `grep -c ... == 0` exits nonzero on no match), plus a check
  that the `source: sqlcipher` hook is present.
- **Never add network-capable packages.** CI bans `http`, `dio`, `web_socket_channel`, `grpc`,
  `firebase_*`, `connectivity_plus` in `pubspec.lock` and greps `lib/` for `HttpClient` /
  `Socket.connect`.
- `share_plus`, `file_selector`, and `local_auth` are **not** dependencies in v1. Backup export
  is save-file-only via `flutter_file_dialog`; the device-lock advisory card renders
  unconditionally.
- One SHA-256 implementation: `package:crypto`; `package:cryptography` only for `DartArgon2id`.
- No `build.yaml` is needed: drift's default Dart-to-SQL name mapping is snake_case, and the raw
  SQL in §4 relies on that default.

---

## 3. Conventions

- **Primary keys:** 26-character Crockford-base32 **ULID** strings, generated in Dart
  (`lib/core/ids.dart`, `Random.secure()` entropy, monotonic within process). ULIDs are
  time-sortable: `ORDER BY id` is chronological insert order, `MAX(id)` is "latest", and
  `(item_id, id)` indexes double as per-item timelines. All id columns are
  `text().withLength(min: 26, max: 26)`. Timestamp leakage is a non-argument: every row already
  stores `*_at_micros`.
- **Timestamps:** `*_at_micros INTEGER` = UTC epoch **microseconds** (domain type `Instant`,
  §6.1). Microsecond precision is required by the `recordedAt` monotonic tie-bump contract.
- **Business dates:** event day is `TEXT 'YYYY-MM-DD'` in the owner's local calendar
  (`events.scheduled_date`); event history is calendar-day shaped.
- **Enums:** lowercase `TEXT` with SQL `CHECK (col IN (...))`, mapped to Dart enums in the DAO
  layer — SQL enforces validity independently of Dart.
- **Booleans:** drift `boolean()` → `INTEGER CHECK (col IN (0,1))`.
- **Soft archive, never delete:** master data (`items`, `recipes`) gets `archived_at_micros`;
  ledger FKs use `RESTRICT` so referenced rows can never be deleted.
- **Signed ledger:** `inventory_movements.delta_micros` is signed; sign is dictated per kind by
  CHECK. On-hand = `SUM(delta_micros)` and may legitimately go negative (surfaced as a warning,
  never silently clamped in audit views).
- **Caps:** every stored quantity magnitude ≤ `Quantity.maxMicros` (1e15); exposures in
  `[1, 1_000_000]`; closeout `depletion_micros ≤ 1e12` (the frozen engine's safe envelope).

---

## 4. Complete final schema

Seventeen tables. Schema version 1. `lib/data/db/tables.dart`:

```dart
import 'package:drift/drift.dart';

// ---------------------------------------------------------------- workspace

class WorkspaceMeta extends Table {
  IntColumn get id => integer().check(id.equals(1))(); // singleton row
  TextColumn get workspaceUid => text().withLength(min: 26, max: 26)();
  TextColumn get displayName => text().withDefault(const Constant('My workspace'))();
  IntColumn get createdAtMicros => integer()();
  TextColumn get createdByAppVersion => text()();
  @override Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text().withLength(min: 1, max: 64)();
  TextColumn get value => text()(); // JSON-encoded scalar
  IntColumn get updatedAtMicros => integer()();
  @override Set<Column> get primaryKey => {key};
}

// ---------------------------------------------------------------- commands

/// Audit + idempotency for the single write path. v1 rows are inserted with a terminal status
/// ('applied'|'rejected') in the same transaction as their effects; 'staged' exists for Gate 4.
/// Triggers (§4.1) forbid DELETE and any UPDATE other than staged -> applied|rejected touching
/// only status/applied_at/rejected_reason.
class Commands extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get origin => text().check(origin.isIn(['form', 'agent']))();
  TextColumn get kind => text().withLength(min: 1, max: 64)();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().check(status.isIn(['staged', 'applied', 'rejected']))();
  IntColumn get createdAtMicros => integer()();
  IntColumn get appliedAtMicros => integer().nullable()();
  TextColumn get rejectedReason => text().nullable()();
  @override Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------- items

/// One unit per item, closed list, no conversions. Unit is locked after the item's first
/// movement (validator-enforced; escape hatch: archive+recreate).
class Items extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get unit => text().check(unit.isIn(['each', 'g', 'kg', 'ml', 'L']))();
  /// Purchase/load rounding increment in micros of [unit]. Engine packSize.
  IntColumn get packSizeMicros => integer().check(packSizeMicros.isBiggerThanValue(0))();
  TextColumn get category => text().nullable().withLength(min: 1, max: 60)();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get archivedAtMicros => integer().nullable()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();
  @override Set<Column> get primaryKey => {id};
}
// Live-name uniqueness is the partial index uidx_items_name_live (§4.1):
// UNIQUE ON items(lower(name)) WHERE archived_at_micros IS NULL.

// ---------------------------------------------------------------- events

/// Mutable until closed. planned_exposure is a PREDICTION and never a label; confirmed exposure
/// lives on the append-only closeout header.
class Events extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get venue => text().nullable()();
  TextColumn get scheduledDate => text()(); // 'YYYY-MM-DD', CHECK below
  IntColumn get startsAtMicros => integer().nullable()();
  IntColumn get endsAtMicros => integer().nullable()();
  TextColumn get status => text()
      .check(status.isIn(['planned', 'active', 'closed', 'cancelled']))
      .withDefault(const Constant('planned'))();
  IntColumn get plannedExposure =>
      integer().nullable().check(plannedExposure.isBetweenValues(1, 1000000))();
  IntColumn get closedAtMicros => integer().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();
  @override Set<Column> get primaryKey => {id};
  @override List<String> get customConstraints => [
        "CHECK (scheduled_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')",
        "CHECK (status != 'closed' OR closed_at_micros IS NOT NULL)",
        'CHECK (ends_at_micros IS NULL OR starts_at_micros IS NULL '
            'OR ends_at_micros >= starts_at_micros)',
      ];
}

/// Planned items per event. Mutable until the event closes (validator rule).
class EventItems extends Table {
  TextColumn get eventId => text().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId => text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer().check(position.isBiggerOrEqualValue(0))();
  @override Set<Column> get primaryKey => {eventId, itemId};
}

// ---------------------------------------------------------------- ledger

/// APPEND-ONLY. UPDATE/DELETE blocked by triggers. On-hand = SUM(delta_micros); negative sums
/// are legal and surfaced. Kinds and sign (CHECK-enforced):
///   receive  +  purchase arrives     | consume - confirmed event depletion, written ONLY by
///   waste    -  spoilage/damage      |           closeout application, event_id required
///   adjust   +/- count reconciliation| reversal +/- exact negation of a prior row
class InventoryMovements extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)(); // ULID = time-sorted
  TextColumn get itemId => text().references(Items, #id, onDelete: KeyAction.restrict)();
  TextColumn get kind =>
      text().check(kind.isIn(['receive', 'consume', 'waste', 'adjust', 'reversal']))();
  IntColumn get deltaMicros => integer()(); // signed micros; never zero
  TextColumn get eventId => text().nullable().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get reversesMovementId =>
      text().nullable().references(InventoryMovements, #id, onDelete: KeyAction.restrict)();
  TextColumn get sourceCommandId => text().references(Commands, #id, onDelete: KeyAction.restrict)();
  IntColumn get occurredAtMicros => integer()(); // business time (backdatable)
  IntColumn get recordedAtMicros => integer()(); // applier clock, monotonic
  TextColumn get note => text().withDefault(const Constant(''))();
  @override Set<Column> get primaryKey => {id};
  @override List<String> get customConstraints => [
        'CHECK (delta_micros != 0)',
        'CHECK (abs(delta_micros) <= 1000000000000000)',
        "CHECK (CASE kind WHEN 'receive' THEN delta_micros > 0 "
            "WHEN 'consume' THEN delta_micros < 0 "
            "WHEN 'waste' THEN delta_micros < 0 ELSE 1 END)",
        "CHECK ((kind = 'reversal') = (reverses_movement_id IS NOT NULL))",
        'UNIQUE (reverses_movement_id)',
        "CHECK (kind != 'consume' OR event_id IS NOT NULL)",
      ];
}

// ---------------------------------------------------------------- closeouts

/// APPEND-ONLY confirmed-outcome HEADER: one row per (event, revision). Current outcome =
/// MAX(revision). Confirmed exposure here is the ONLY exposure ever used as a forecasting label.
class EventCloseouts extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get eventId => text().references(Events, #id, onDelete: KeyAction.restrict)();
  IntColumn get revision => integer().check(revision.isBiggerThanValue(0))();
  TextColumn get supersedesCloseoutId =>
      text().nullable().references(EventCloseouts, #id, onDelete: KeyAction.restrict)();
  IntColumn get confirmedExposure => integer().check(confirmedExposure.isBetweenValues(1, 1000000))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get sourceCommandId => text().references(Commands, #id, onDelete: KeyAction.restrict)();
  IntColumn get confirmedAtMicros => integer()();
  @override Set<Column> get primaryKey => {id};
  @override List<String> get customConstraints => [
        'UNIQUE (event_id, revision)',
        'UNIQUE (supersedes_closeout_id)',
        'CHECK ((revision = 1) = (supersedes_closeout_id IS NULL))',
      ];
}

/// APPEND-ONLY closeout LINES. Worksheet fields loaded/returned/waste are optional; when all
/// three are present the arithmetic must reconcile: depletion = loaded - returned - waste.
/// Depletion EXCLUDES waste: it is the demand label ("what sells"), not "what left the van".
class CloseoutLines extends Table {
  TextColumn get closeoutId => text().references(EventCloseouts, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId => text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get loadedMicros => integer().nullable().check(loadedMicros.isBiggerOrEqualValue(0))();
  IntColumn get returnedMicros => integer().nullable().check(returnedMicros.isBiggerOrEqualValue(0))();
  IntColumn get wasteMicros => integer().nullable().check(wasteMicros.isBiggerOrEqualValue(0))();
  /// The confirmed demand label. Envelope cap 1e12 micros (frozen engine).
  IntColumn get depletionMicros => integer().check(depletionMicros.isBetweenValues(0, 1000000000000))();
  BoolColumn get stockout => boolean().withDefault(const Constant(false))();
  BoolColumn get approximate => boolean().withDefault(const Constant(false))();
  /// Ledger rows written when this revision was applied (evidence links).
  TextColumn get consumptionMovementId =>
      text().nullable().references(InventoryMovements, #id, onDelete: KeyAction.restrict)();
  TextColumn get wasteMovementId =>
      text().nullable().references(InventoryMovements, #id, onDelete: KeyAction.restrict)();
  @override Set<Column> get primaryKey => {closeoutId, itemId};
  @override List<String> get customConstraints => [
        'CHECK (loaded_micros IS NULL OR returned_micros IS NULL OR waste_micros IS NULL '
            'OR depletion_micros = loaded_micros - returned_micros - waste_micros)',
      ];
}

/// Upsert-mutable autosave for the closeout form. A draft is not a record; append-only does not
/// apply. Row is deleted on confirm.
class CloseoutDrafts extends Table {
  TextColumn get eventId => text().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get payloadJson => text()();
  IntColumn get updatedAtMicros => integer()();
  @override Set<Column> get primaryKey => {eventId};
}

// ---------------------------------------------------------------- recipes

/// Identity + output binding. At most one live recipe per output item (partial unique index
/// uidx_recipes_output_live, §4.1).
class Recipes extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get outputItemId => text().references(Items, #id, onDelete: KeyAction.restrict)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get archivedAtMicros => integer().nullable()();
  IntColumn get createdAtMicros => integer()();
  @override Set<Column> get primaryKey => {id};
}

/// APPEND-ONLY. Editing a recipe inserts revision+1; current = MAX(revision). source_kind 'ocr'
/// is allowed in the CHECK now so Gate 5 needs no migration.
class RecipeRevisions extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get recipeId => text().references(Recipes, #id, onDelete: KeyAction.restrict)();
  IntColumn get revision => integer().check(revision.isBiggerThanValue(0))();
  IntColumn get yieldMicros => integer().check(yieldMicros.isBiggerThanValue(0))();
  TextColumn get yieldLabel => text().nullable()(); // e.g. "12 tacos"
  TextColumn get sourceKind => text().check(sourceKind.isIn(['form', 'ocr']))();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAtMicros => integer()();
  @override Set<Column> get primaryKey => {id};
  @override List<String> get customConstraints => ['UNIQUE (recipe_id, revision)'];
}

/// APPEND-ONLY (immutable with its revision). Amount is micros of the ingredient's own base unit
/// per batch. Expansion math is Gate 5.
class RecipeLines extends Table {
  TextColumn get revisionId => text().references(RecipeRevisions, #id, onDelete: KeyAction.restrict)();
  IntColumn get lineIndex => integer().check(lineIndex.isBiggerOrEqualValue(0))();
  TextColumn get ingredientItemId => text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantityPerBatchMicros =>
      integer().check(quantityPerBatchMicros.isBiggerThanValue(0))();
  @override Set<Column> get primaryKey => {revisionId, lineIndex};
  @override List<String> get customConstraints => ['UNIQUE (revision_id, ingredient_item_id)'];
}

// ---------------------------------------------------------------- forecasts

/// APPEND-ONLY. One snapshot per engine run over a WHOLE EVENT; per-item rows in forecast_lines;
/// evidence value-copied per line. Latest per event = MAX(id). Regenerating appends; nothing is
/// rewritten. Actuals are NEVER stored here — they are derived by join (§6.6).
class ForecastSnapshots extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get eventId => text().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get method => text()(); // 'direct_median'
  IntColumn get methodVersion => integer().check(methodVersion.isBiggerThanValue(0))(); // 1
  TextColumn get policy => text().check(policy.isIn(['lean', 'balanced', 'cautious']))();
  IntColumn get upcomingExposure => integer().check(upcomingExposure.isBetweenValues(1, 1000000))();
  /// The last-N history window in force when this snapshot was generated.
  IntColumn get historyWindow => integer().check(historyWindow.isBiggerThanValue(0))();
  /// SHA-256 lowercase hex over the canonical input encoding (§6.6).
  TextColumn get inputsHash => text().withLength(min: 64, max: 64)();
  /// JSON, e.g. {"reserve_percent":10,"history_window":12,
  /// "rate_normalization":"per_exposure_median","exposure_label":"attendance"}.
  TextColumn get assumptionsJson => text().withDefault(const Constant('{}'))();
  TextColumn get sourceCommandId => text().references(Commands, #id, onDelete: KeyAction.restrict)();
  IntColumn get createdAtMicros => integer()();
  @override Set<Column> get primaryKey => {id};
}

/// APPEND-ONLY per-item snapshot lines: frozen inputs + engine outputs. on_hand_micros stores
/// the SIGNED derived on-hand at generation time; the engine consumed max(0, on_hand_micros).
/// Warnings are the frozen engine's strings verbatim (the DB is encrypted; content-free binds
/// diagnostics only).
class ForecastLines extends Table {
  TextColumn get snapshotId => text().references(ForecastSnapshots, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId => text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get packSizeMicros => integer().check(packSizeMicros.isBiggerThanValue(0))();
  IntColumn get onHandMicros => integer()(); // signed
  IntColumn get confirmedInboundMicros => integer()
      .withDefault(const Constant(0))
      .check(confirmedInboundMicros.isBiggerOrEqualValue(0))();
  IntColumn get expectedUseMicros =>
      integer().nullable().check(expectedUseMicros.isBiggerOrEqualValue(0))();
  IntColumn get plannedMicros => integer().nullable().check(plannedMicros.isBiggerOrEqualValue(0))();
  IntColumn get loadMicros => integer().nullable().check(loadMicros.isBiggerOrEqualValue(0))();
  IntColumn get acquireMicros => integer().nullable().check(acquireMicros.isBiggerOrEqualValue(0))();
  TextColumn get evidenceGrade => text().check(
      evidenceGrade.isIn(['insufficient_data', 'single_event', 'observed_range']))();
  TextColumn get warningsJson => text().withDefault(const Constant('[]'))();
  @override Set<Column> get primaryKey => {snapshotId, itemId};
  @override List<String> get customConstraints => [
        "CHECK ((evidence_grade = 'insufficient_data') = (expected_use_micros IS NULL))",
      ];
}

/// APPEND-ONLY value-copies of the exact observations the engine saw, frozen at generation time.
/// Later closeout revisions never rewrite forecast history.
class ForecastEvidence extends Table {
  TextColumn get snapshotId => text().references(ForecastSnapshots, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId => text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer().check(position.isBiggerOrEqualValue(0))();
  TextColumn get closeoutId => text().references(EventCloseouts, #id, onDelete: KeyAction.restrict)();
  TextColumn get sourceEventId => text().references(Events, #id, onDelete: KeyAction.restrict)();
  IntColumn get exposure => integer().check(exposure.isBetweenValues(1, 1000000))();
  IntColumn get depletionMicros => integer().check(depletionMicros.isBetweenValues(0, 1000000000000))();
  BoolColumn get stockout => boolean()();
  BoolColumn get approximate => boolean()();
  @override Set<Column> get primaryKey => {snapshotId, itemId, position};
}

/// APPEND-ONLY override log per (snapshot, item). Latest row (MAX(id)) wins for display.
/// override_load_micros NULL means "revert to the engine value" (implements clear-override).
/// Reason mandatory, >= 3 chars. Overrides are plans, never labels: no history query reads this.
class ForecastOverrides extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get snapshotId => text().references(ForecastSnapshots, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId => text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get overrideLoadMicros =>
      integer().nullable().check(overrideLoadMicros.isBiggerOrEqualValue(0))();
  TextColumn get reason => text().withLength(min: 3, max: 500)();
  IntColumn get createdAtMicros => integer()();
  @override Set<Column> get primaryKey => {id};
}
```

### 4.1 Indices and append-only triggers — `lib/data/db/schema_sql.dart`

```dart
const schemaV1Indices = <String>[
  // HOT: on-hand = SUM(delta_micros); covering index answers per-item and GROUP BY sums
  // entirely from the index.
  'CREATE INDEX idx_movements_item_delta ON inventory_movements (item_id, delta_micros)',
  'CREATE INDEX idx_movements_item_id ON inventory_movements (item_id, id)',
  'CREATE INDEX idx_movements_event ON inventory_movements (event_id) WHERE event_id IS NOT NULL',
  'CREATE INDEX idx_movements_command ON inventory_movements (source_command_id)',
  'CREATE UNIQUE INDEX uidx_items_name_live ON items (lower(name)) '
      'WHERE archived_at_micros IS NULL',
  'CREATE INDEX idx_events_status_date ON events (status, scheduled_date)',
  'CREATE INDEX idx_closeouts_event_rev ON event_closeouts (event_id, revision)',
  'CREATE INDEX idx_closeout_lines_item ON closeout_lines (item_id, closeout_id)',
  'CREATE UNIQUE INDEX uidx_recipes_output_live ON recipes (output_item_id) '
      'WHERE archived_at_micros IS NULL',
  'CREATE INDEX idx_snapshots_event ON forecast_snapshots (event_id, id)',
  'CREATE INDEX idx_overrides_snapshot ON forecast_overrides (snapshot_id, item_id, id)',
];

/// Belt-and-braces append-only enforcement (ADR 0001: triggers forbid, never compute). The Dart
/// layer never issues UPDATE/DELETE on these tables.
const appendOnlyTables = [
  'inventory_movements', 'event_closeouts', 'closeout_lines', 'recipe_revisions', 'recipe_lines',
  'forecast_snapshots', 'forecast_lines', 'forecast_evidence', 'forecast_overrides',
];

List<String> get schemaV1Triggers => [
      for (final t in appendOnlyTables) ...[
        'CREATE TRIGGER trg_${t}_no_update BEFORE UPDATE ON $t '
            "BEGIN SELECT RAISE(ABORT, '$t is append-only'); END",
        'CREATE TRIGGER trg_${t}_no_delete BEFORE DELETE ON $t '
            "BEGIN SELECT RAISE(ABORT, '$t is append-only'); END",
      ],
      // commands: append-only except staged -> applied|rejected.
      'CREATE TRIGGER trg_commands_no_delete BEFORE DELETE ON commands '
          "BEGIN SELECT RAISE(ABORT, 'commands is append-only'); END",
      'CREATE TRIGGER trg_commands_limited_update BEFORE UPDATE ON commands '
          "WHEN OLD.status != 'staged' OR NEW.id != OLD.id OR NEW.origin != OLD.origin "
          'OR NEW.kind != OLD.kind OR NEW.payload_json != OLD.payload_json '
          'OR NEW.created_at_micros != OLD.created_at_micros '
          "OR NEW.status NOT IN ('applied', 'rejected') "
          "BEGIN SELECT RAISE(ABORT, 'commands: illegal transition'); END",
    ];
```

Cross-row rules SQL cannot express are owned by `CommandValidator` / `CommandApplier` and
covered by Gate 2 tests: a reversal's `delta_micros` is the exact negation of the reversed row
and matches its `item_id` and `event_id`; a reversal cannot target a reversal; closeout revision
N+1 exists only with the mirroring reversal movements written in the same transaction;
`consumption_movement_id` points at a `consume` row for the same event+item; `event_items` is
frozen once the event is `closed`; item `unit` is immutable once the item has any movement.

### 4.2 Database class, migration, seed

```dart
@DriftDatabase(
  tables: [
    WorkspaceMeta, Settings, Commands, Items, Events, EventItems, InventoryMovements,
    EventCloseouts, CloseoutLines, CloseoutDrafts, Recipes, RecipeRevisions, RecipeLines,
    ForecastSnapshots, ForecastLines, ForecastEvidence, ForecastOverrides,
  ],
  daos: [
    LedgerDao, EventDao, CloseoutDao, ItemDao, RecipeDao, ForecastDao, CommandDao, SettingsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  AppDatabase.forTesting(NativeDatabase super.executor);

  @override
  int get schemaVersion => 1;

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
          // v1: nothing. Future: stepwise `if (from < N)` additive blocks. Before any real
          // onUpgrade, bootstrap makes a plain file copy of the (already device-key-encrypted)
          // db to db/pre-migration-v<from>.db; deleted on success. No passphrase involved.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
```

`_seedV1` seeds **only**: the `workspace_meta` row and default settings —
`planning_policy_default = "balanced"`, `exposure_label = "attendance"`,
`history_window_events = 12`, `seeded_v1 = true`. There are no unit tables; the unit enum lives
in Dart and in the `items.unit` CHECK.

Migration rules: additive-only forever (never drop or rewrite append-only tables); stepwise
`if (from < N)` blocks; after any schema change run
`dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/loadout/` and commit
the JSON — CI fails if the dump drifts from the committed file. Drift's `SchemaVerifier`
migration tests arrive with the first real migration (schema v2), not before.

### 4.3 Derived on-hand and the label query

On-hand (served entirely from `idx_movements_item_delta`; at this scale a full index scan is
sub-millisecond — no checkpoint table in v1):

```sql
SELECT COALESCE(SUM(delta_micros), 0) FROM inventory_movements WHERE item_id = :itemId;
-- all items:
SELECT item_id, SUM(delta_micros) AS on_hand_micros FROM inventory_movements GROUP BY item_id;
```

Forecast history (**the only label source**; latest closeout revision of closed events only;
deterministic order):

```sql
SELECT h.id AS closeout_id, h.event_id, h.confirmed_exposure,
       l.depletion_micros, l.stockout, l.approximate
FROM closeout_lines l
JOIN event_closeouts h ON h.id = l.closeout_id
JOIN events e ON e.id = h.event_id
WHERE l.item_id = :itemId
  AND e.status = 'closed'
  AND h.revision = (SELECT MAX(h2.revision) FROM event_closeouts h2
                    WHERE h2.event_id = h.event_id)
ORDER BY e.scheduled_date DESC, e.id DESC
LIMIT :historyWindow;
```

This query never touches `forecast_*`, `events.planned_exposure`, or drafts — predictions and
overrides cannot leak into labels, structurally.

---

## 5. Ledger & closeout semantics

**Movement kinds (normative):**

| kind | sign | written by | event_id |
|---|---|---|---|
| `receive` | + | forms (Purchase) | never |
| `consume` | − | **closeout application only** | required |
| `waste` | − | forms (Waste), closeout application | optional |
| `adjust` | ± | forms (Count; service computes signed delta) | never |
| `reversal` | mirror of target | correction & closeout revision | copies target's |

There is no `opening` kind (an initial count is an `adjust`), no quarantine pool, and no
`loadOut`/`returnIn` kinds: with a single stock pool, loading the van changes nothing; what
happened at the event is captured once, at closeout. Loaded/returned are closeout **worksheet
fields**, not movements.

**Closeout confirm (revision 1) — one transaction:**
1. Insert `commands` row (`RecordCloseout`, status `applied`).
2. Insert `event_closeouts` header (revision 1, confirmed exposure) and one `closeout_lines` row
   per confirmed item.
3. Per line: insert a `consume` movement with `delta_micros = −depletion` (skipped when
   depletion = 0 — a confirmed zero is a legal label but deltas are never zero) and a `waste`
   movement with `delta_micros = −waste` when the worksheet waste field is present and > 0; link
   both ids onto the line.
4. Update `events`: `status = 'closed'`, `closed_at_micros` stamped.

**Closeout revision N+1 — one transaction:** insert the command row; insert `reversal` movements
exactly mirroring **every** event-linked movement written by revision N (consume and waste
rows); insert fresh `consume`/`waste` movements for the new lines; insert the new header
(revision N+1, `supersedes_closeout_id` = revision N's id) and lines. Inventory and labels can
never disagree, and every historical revision stays queryable.

**Negative on-hand:** always allowed, always warned. A command that drives on-hand negative
succeeds and returns `NEGATIVE_ON_HAND` in the receipt's warnings; Home's data-health card
surfaces items with negative sums. Closeout is the label factory and is **never blocked** by
ledger drift.

**Corrections:** `CorrectMovement` appends, in one transaction, a `reversal` mirroring the
target (`delta = −target.delta`, same item/event) plus an optional replacement movement. A
movement is reversible at most once (`UNIQUE(reverses_movement_id)`); a reversal cannot be
reversed — record a fresh original instead.

---

## 6. Domain services & write path

All code under `lib/core/` and `lib/**/domain/` is pure Dart — no Flutter, no drift imports.
Error style: programmer errors throw (`ArgumentError`, `StateError`, `QuantityOverflowError`);
expected outcomes crossing the application boundary return `Result<T>`.

### 6.1 Core types

```dart
// lib/core/ids.dart
/// Monotonic ULID: 26 chars, Crockford base32, Random.secure() entropy.
String newUlid({int? nowMillis});

extension type const ItemId(String value) implements Object {}
extension type const EventId(String value) implements Object {}
extension type const MovementId(String value) implements Object {}
extension type const RecipeId(String value) implements Object {}
extension type const RecipeRevisionId(String value) implements Object {}
extension type const CloseoutId(String value) implements Object {}
extension type const ForecastSnapshotId(String value) implements Object {}
extension type const CommandId(String value) implements Object {}

abstract interface class IdGenerator {
  String newId(); // production: newUlid(); tests: sequential 26-char ids
}

// lib/core/time.dart
extension type const Instant(int epochMicrosUtc) implements Object {}

abstract interface class Clock {
  Instant now();
}
// SystemClock (DateTime.now().toUtc().microsecondsSinceEpoch), FixedClock for tests.

// lib/core/result.dart
sealed class Result<T> {
  const Result();
  R fold<R>(R Function(T value) onOk, R Function(DomainError error) onErr);
}
final class Ok<T> extends Result<T> { const Ok(this.value); final T value; }
final class Err<T> extends Result<T> { const Err(this.error); final DomainError error; }

// lib/core/errors.dart — DomainError.code is a stable machine string: NOT_FOUND, DUPLICATE_ID,
// VALIDATION, IMMUTABLE_RECORD, ALREADY_REVERSED, RECIPE_NESTING, RECIPE_CYCLE, OVERFLOW,
// STALE_STATE, NOT_AVAILABLE.
sealed class DomainError { const DomainError(); String get code; String get message; }
final class QuantityOverflowError extends Error {
  QuantityOverflowError(this.detail);
  final String detail;
}
```

`Quantity` hardening (additive; existing methods keep their results for in-range inputs):
`static const int maxMicros = 1000000000000000;` (1e15 — generous, and small enough that the
frozen `multiplyRatio` with reserve numerators ≤ 210 cannot wrap int64); `fromMicros`
additionally throws `QuantityOverflowError` above the cap; add `Quantity plus(Quantity)`
(checked add). `lib/core/unit_ratio.dart` adds `UnitRatio` (exact positive int pair,
gcd-normalized, `applyCeil` via BigInt, overflow-checked). `RationalMicros` does **not** ship in
v1 (deferred with the aggregation tier, §13).

### 6.2 Entities

Immutable `final class`es mirroring §4 exactly: `Item {id, name, unit (ItemUnit:
each|g|kg|ml|L), packSize, category?, notes, archivedAt?, createdAt, updatedAt}`; `Event {id,
name, venue?, scheduledDate, startsAt?, endsAt?, status (planned|active|closed|cancelled),
plannedExposure?, closedAt?, notes?, plannedItemIds}`; `Movement {id, itemId, kind, deltaMicros,
eventId?, reverses?, occurredAt, recordedAt, sourceCommandId, note}`; `EventCloseout {id,
eventId, revision, supersedes?, confirmedExposure, note, confirmedAt, lines}` with
`CloseoutLine {itemId, loaded?, returned?, waste?, depletion, stockout, approximate}`; `Recipe`;
`RecipeRevisionView {id, recipeId, revision, yield, yieldLabel?, sourceKind, note, lines}` with
`RecipeLine {ingredientItemId, quantityPerBatch}`; snapshot/line/evidence/override views
mirroring §4.

Mapping to the frozen engine input, per item: `ConfirmedObservation(exposure:
header.confirmedExposure, depletion: line.depletion, stockout: line.stockout, approximate:
line.approximate)` — taken from the §4.3 label query only.

### 6.3 `InventoryLedger` port and `LedgerMath`

```dart
// lib/features/inventory/domain/ledger_math.dart
final class StockPosition {
  const StockPosition({required this.onHandMicros});
  final int onHandMicros;                       // SIGNED
  bool get isNegative => onHandMicros < 0;
  Quantity get onHand =>                        // clamped display view
      Quantity.fromMicros(onHandMicros < 0 ? 0 : onHandMicros);
}

final class LedgerMath {
  const LedgerMath._();
  /// Deterministic fold: movements sorted by (occurredAt, recordedAt, id bytewise) before
  /// summing delta_micros; asOf is INCLUSIVE on occurredAt. A reversal takes effect at ITS OWN
  /// occurredAt.
  static StockPosition position(Iterable<Movement> movements, {Instant? asOf});
}

// lib/features/inventory/domain/inventory_ledger.dart — the architecture seam.
abstract interface class InventoryLedger {
  // queries (open read path)
  Future<StockPosition> position(ItemId item, {Instant? asOf});
  Future<Map<ItemId, StockPosition>> positions({Instant? asOf});
  Future<List<Movement>> movements({ItemId? item, EventId? event, Instant? from, Instant? to});
  Future<Movement?> movement(MovementId id);
  Stream<StockPosition> watchPosition(ItemId item);
  Stream<int> watchVersion(); // max rowid; cheap recompute trigger

  // writes: called ONLY by CommandApplier inside its transaction
  Future<Movement> appendMovement(MovementDraft draft,
      {required CommandId sourceCommandId, required Instant recordedAt});
  Future<Movement> reverseMovement(
      {required MovementId target, required String reason, required Instant occurredAt,
      required CommandId sourceCommandId, required Instant recordedAt});
}

final class MovementDraft {
  const MovementDraft({required this.itemId, required this.kind, required this.deltaMicros,
      this.eventId, this.occurredAt, this.note = ''});
  final ItemId itemId;
  final MovementKind kind;   // reversal is NOT a legal draft kind
  final int deltaMicros;     // signed; validator enforces sign-per-kind
  final EventId? eventId;
  final Instant? occurredAt; // null => recordedAt
  final String note;
}
```

Ledger invariants (validator + applier, Gate 2 tested): `delta != 0`, `|delta| ≤ maxMicros`,
sign-per-kind; append-only; reversal mirrors target exactly, targets reversed at most once;
`consume` requires `eventId` and is only constructible by closeout application (forms cannot
submit it); `recordedAt` nondecreasing in application order (applier bumps 1 µs on Clock ties);
fold determinism under permutation. Negative on-hand is a **warning**, never a rejection (§5).

### 6.4 The single write path

```dart
// lib/features/approval/domain/commands.dart
sealed class WorkspaceCommand { const WorkspaceCommand(); }

// Catalog (master data: plain in-place updates; no revision log in v1)
final class CreateItem extends WorkspaceCommand {
  const CreateItem({required this.name, required this.unit, required this.packSize,
      this.category, this.notes = ''});
  final String name; final ItemUnit unit; final Quantity packSize;
  final String? category; final String notes;
}
final class UpdateItem extends WorkspaceCommand {
  const UpdateItem({required this.itemId, this.name, this.packSize, this.category, this.notes});
  final ItemId itemId; final String? name; final Quantity? packSize;
  final String? category; final String? notes; // unit is NOT updatable
}
final class SetItemArchived extends WorkspaceCommand {
  const SetItemArchived({required this.itemId, required this.archived});
  final ItemId itemId; final bool archived;
}

// Events (predictions: mutable until closed)
final class CreateEvent extends WorkspaceCommand {
  const CreateEvent({required this.name, required this.scheduledDate, this.startsAt, this.endsAt,
      this.plannedExposure, this.venue, this.notes, this.plannedItemIds = const []});
  final String name; final String scheduledDate; final Instant? startsAt; final Instant? endsAt;
  final int? plannedExposure; final String? venue; final String? notes;
  final List<ItemId> plannedItemIds;
}
final class UpdateEvent extends WorkspaceCommand {
  const UpdateEvent({required this.eventId, this.name, this.scheduledDate, this.startsAt,
      this.endsAt, this.plannedExposure, this.venue, this.notes, this.plannedItemIds});
  final EventId eventId; final String? name; final String? scheduledDate;
  final Instant? startsAt; final Instant? endsAt; final int? plannedExposure;
  final String? venue; final String? notes; final List<ItemId>? plannedItemIds;
}
final class ActivateEvent extends WorkspaceCommand {
  const ActivateEvent(this.eventId);
  final EventId eventId;
}
final class CancelEvent extends WorkspaceCommand {
  const CancelEvent({required this.eventId, required this.reason});
  final EventId eventId; final String reason; // valid only while 'planned'
}

// Ledger
final class AppendMovement extends WorkspaceCommand {
  const AppendMovement(this.draft);
  final MovementDraft draft; // kinds receive|waste|adjust only from forms
}
final class CorrectMovement extends WorkspaceCommand {
  const CorrectMovement({required this.target, this.replacement, required this.reason});
  final MovementId target; final MovementDraft? replacement;
  final String reason; // reversal + optional replacement, one transaction
}

// Closeout (writes header+lines+movements atomically; §5)
final class RecordCloseout extends WorkspaceCommand {
  const RecordCloseout({required this.eventId, required this.confirmedExposure,
      required this.lines, this.note = ''});
  final EventId eventId; final int confirmedExposure;
  final List<CloseoutLineDraft> lines; final String note;
}
final class ReviseCloseout extends WorkspaceCommand {
  const ReviseCloseout({required this.eventId, required this.confirmedExposure,
      required this.lines, this.note = ''});
  final EventId eventId; final int confirmedExposure;
  final List<CloseoutLineDraft> lines; final String note;
}
final class CloseoutLineDraft {
  const CloseoutLineDraft({required this.itemId, this.loaded, this.returned, this.waste,
      required this.depletion, this.stockout = false, this.approximate = false});
  final ItemId itemId; final Quantity? loaded; final Quantity? returned; final Quantity? waste;
  final Quantity depletion; final bool stockout; final bool approximate;
}

// Recipes
final class CreateRecipe extends WorkspaceCommand {
  const CreateRecipe({required this.outputItemId, required this.name, required this.firstRevision});
  final ItemId outputItemId; final String name; final RecipeRevisionDraft firstRevision;
}
final class AddRecipeRevision extends WorkspaceCommand {
  const AddRecipeRevision({required this.recipeId, required this.revision});
  final RecipeId recipeId; final RecipeRevisionDraft revision;
}
final class SetRecipeArchived extends WorkspaceCommand {
  const SetRecipeArchived({required this.recipeId, required this.archived});
  final RecipeId recipeId; final bool archived;
}

// Forecasting
final class SaveForecastSnapshot extends WorkspaceCommand {
  const SaveForecastSnapshot(this.snapshot);
  /// Fully-computed snapshot (header, lines, evidence, inputsHash). The applier recomputes
  /// inputsHash from the embedded inputs and rejects on mismatch (tamper/staleness check).
  /// Valid while event is planned|active.
  final ForecastSnapshotDraft snapshot;
}
final class OverrideForecastLine extends WorkspaceCommand {
  const OverrideForecastLine({required this.snapshotId, required this.itemId, this.overrideLoad,
      required this.reason});
  final ForecastSnapshotId snapshotId; final ItemId itemId;
  final Quantity? overrideLoad; // null = revert to engine value (clear)
  final String reason;          // mandatory, >= 3 chars
}
```

```dart
// lib/features/approval/domain/approval_service.dart
enum ProposalOrigin { form, agent }

final class Proposal {
  const Proposal({required this.commandId, required this.origin, required this.command,
      required this.createdAt});
  final CommandId commandId;   // caller-generated ULID; idempotency key
  final ProposalOrigin origin;
  final WorkspaceCommand command;
  final Instant createdAt;
}

final class CommandReceipt {
  const CommandReceipt({required this.commandId, required this.appliedAt,
      required this.createdRecordIds, this.warnings = const []});
  final CommandId commandId;
  final Instant appliedAt;
  final List<String> createdRecordIds;
  final List<String> warnings; // e.g. 'NEGATIVE_ON_HAND'
}

/// Pure: checks every invariant against a read-only state projection.
final class CommandValidator {
  const CommandValidator();
  Result<ValidatedCommand> validate(WorkspaceCommand command, WorkspaceReadModel state);
}

/// Port implemented over Drift. ONE transaction per command: the commands audit row plus every
/// effect. Assigns ids via IdGenerator, stamps recordedAt via Clock.
abstract interface class CommandApplier {
  Future<Result<CommandReceipt>> apply(ValidatedCommand command,
      {required CommandId commandId, required ProposalOrigin origin});
}

abstract interface class ApprovalService {
  /// Form path (v1): validate + apply atomically; command row inserted with terminal status.
  /// Duplicate commandId with identical payload returns the original receipt; different
  /// payload => DuplicateIdError.
  Future<Result<CommandReceipt>> submit(Proposal proposal);

  /// Agent path — the Gate 4 seam. Declared and frozen NOW; v1 bodies: stage/approve/reject
  /// return Err(NotAvailableError), pending() returns [].
  Future<Result<PendingProposal>> stage(Proposal proposal);
  Future<Result<CommandReceipt>> approve(CommandId commandId);
  Future<Result<void>> reject(CommandId commandId, {required String reason});
  Future<List<PendingProposal>> pending();
}
```

Validator invariants (all Gate 2 tested): every referenced id exists; archived items and
cancelled/closed events reject writes (identifier-invention defense); exposure caps `[1, 1e6]`;
depletion cap 1e12; worksheet arithmetic `depletion = loaded − returned − waste` when all three
present; closeout only for `active` events (revision 1) or `closed` events (revise); cancel and
activate only from `planned`; recipe revisions nonempty with unique ingredients,
`RecipeGraph.assertFlat` (no ingredient may be the output of a live recipe; output item not
among its own ingredients) and `RecipeGraph.detectCycles` pass; snapshot hash re-verification;
override reason ≥ 3 chars and snapshot line exists; item unit immutable after first movement;
`event_items` frozen after close.

**Repositories and DAOs expose no public mutators outside the applier.** Exceptions to the
command path — explicitly not records: `settings` / `workspace_meta` preference upserts
(SettingsService) and `closeout_drafts` autosave upserts (CloseoutService). Everything else goes
through `submit`.

### 6.5 Screen-facing application services

Implementations build `Proposal`s and call `ApprovalService.submit`; screens never construct
commands directly and never touch drift.

```dart
abstract interface class SettingsService {
  Future<Workspace> createWorkspace({required String name, required PlanningPolicy defaultPolicy});
  Future<void> updatePreferences({String? name, PlanningPolicy? defaultPolicy,
      String? exposureLabel, int? historyWindow});
  Stream<Workspace?> watchWorkspace();
}

abstract interface class CatalogService {
  Future<Result<String>> createItem(ItemDraft draft); // returns itemId
  Future<Result<void>> updateItem({required String itemId, required ItemDraft draft});
  Future<Result<void>> setArchived({required String itemId, required bool archived});
  Stream<List<ItemSummary>> watchItems(ItemFilter filter);
  Stream<ItemDetail> watchItem(String itemId);
  Future<List<String>> categorySuggestions(); // SELECT DISTINCT category
}

abstract interface class EventService {
  Future<Result<String>> createEvent(EventDraft draft);
  Future<Result<void>> updateEvent({required String eventId, required EventDraft draft});
  Future<Result<void>> activate(String eventId);
  Future<Result<void>> cancel(String eventId, {required String reason});
  Stream<List<EventSummary>> watchEvents({required EventStatusFilter filter});
  Stream<EventDetail> watchEvent(String eventId);
}

/// Screen-facing ledger surface (the domain port InventoryLedger keeps the architecture seam
/// name; this is the application layer over it).
abstract interface class InventoryService {
  Future<Result<CommandReceipt>> record(MovementFormDraft draft);
  /// Count mode: service computes the signed adjust from counted - derived.
  Future<Result<CommandReceipt>> recordCount({required String itemId,
      required Quantity countedOnHand, DateTime? occurredAt, String? note});
  Future<Result<CommandReceipt>> correct({required String movementId,
      MovementFormDraft? replacement, required String reason});
  Stream<StockPosition> watchPosition(String itemId);
  Stream<List<MovementView>> watchMovements(MovementFilter filter);
  Stream<int> watchVersion();
}

abstract interface class ForecastService {
  /// Runs the frozen engine over every planned item, persists snapshot + lines + evidence via
  /// SaveForecastSnapshot. Appends; never rewrites.
  Future<Result<ForecastSnapshotView>> generateSnapshot(String eventId);
  Stream<ForecastSnapshotView?> watchLatestSnapshot(String eventId);
  /// True when the latest snapshot's inputs_hash differs from a hash of the inputs as they are
  /// now (drives the staleness banner).
  Future<bool> isStale(String eventId);
  Future<Result<void>> setOverride({required String snapshotId, required String itemId,
      required Quantity load, required String reason});
  Future<Result<void>> clearOverride({required String snapshotId, required String itemId,
      required String reason}); // NULL-load override row
  Future<AccuracyReview> accuracyReview(String eventId); // closed-event read model, §6.6
}

abstract interface class CloseoutService {
  /// Prefill: per planned item, the latest snapshot's load (or its live override) labeled
  /// "planned load was N"; blank when no snapshot exists.
  Future<CloseoutPrefill> prefill(String eventId);
  Future<void> saveDraft(CloseoutFormDraft draft);   // upsert closeout_drafts
  Future<CloseoutFormDraft?> loadDraft(String eventId);
  Future<Result<CommandReceipt>> confirm(CloseoutFormDraft draft);
  Future<Result<CommandReceipt>> revise(CloseoutFormDraft draft);
  Stream<List<EventCloseout>> watchRevisions(String eventId);
}

abstract interface class RecipeService {
  Future<Result<String>> createRecipe(RecipeFormDraft draft); // revision 1
  Future<Result<int>> reviseRecipe({required String recipeId, required RecipeFormDraft draft});
  Future<Result<void>> setArchived({required String recipeId, required bool archived});
  Stream<List<RecipeSummary>> watchRecipes();
  Stream<RecipeDetail> watchRecipe(String recipeId);
}

/// Application facade over the infrastructure BackupService (§8): wraps its typed BackupError
/// throws into Result at the application boundary.
abstract interface class BackupFacade {
  Future<Result<BackupFileHandle>> createBackup({required String passphrase});
  Future<Result<BackupDescription>> describeBackup(String path);
  Future<Result<RestorePreview>> validateBackup({required String path, required String passphrase});
  Future<Result<void>> restoreBackup(RestorePreview preview);
}
```

### 6.6 Forecasting: frozen engine, snapshot persistence, actuals

`lib/features/forecasting/domain/forecast_engine.dart` is **FROZEN** — `PlanningPolicy`,
`EvidenceGrade`, `ConfirmedObservation`, `ForecastLine`, `ForecastEngine.forecastDirect`, and
`DeterministicForecastEngine` remain byte-for-byte as in the repository, including the existing
tests. The engine is the only arithmetic source for snapshot outputs. The recipe-derived tier
and whole-plan aggregation (`planEvent`, `RationalMicros`, `PlanHasher`) are the Gate 5 additive
extension of the same seam (§13); Gate 2 needs `forecastDirect` plus persistence only.

`generateSnapshot(eventId)` per planned item: history = §4.3 query with `LIMIT history_window`
(setting, default 12); `usableOnHand = Quantity.fromMicros(max(0, onHandMicros))`;
`confirmedInbound = Quantity.zero` (column defaults 0; **no UI in v1** — the line-detail
assumptions copy states "inbound: 0"); `packSize = item.packSizeMicros`; `policy` from event
(falling back to workspace default); `upcomingExposure = event.plannedExposure` (required — the
UI blocks Generate until set). Method `'direct_median'`; the method version is now **3**, not the
`2` this section originally specified — `forecastMethodVersion` in
`lib/features/forecasting/domain/snapshot.dart` is the single source of truth, and v3 added the
per-event demand basis (`lib/features/forecasting/application/per_event_basis.dart`).
Assumptions JSON records at minimum `reserve_percent`, `history_window`, `exposure_label`, the
sell-out rule below (`stockout_rule`, `stockout_rule_note`, `stockout_adjusted_lines`,
`stockout_all_sellout_lines`) and the per-event rule (`per_event_rule`, `per_event_rule_note`,
`per_event_lines`). **[forecasting.md](forecasting.md) is the current, verified account of how a
number is produced; this section is the original contract and predates method v3.**

**Sell-out (right-censored) observations — method v2, normative.** A closeout records a
depletion plus a `stockout` flag. "Sold 40 and ran out" is a LOWER BOUND on demand, not demand:
she might have sold 60. Feeding that into the median like any other observation biases every
forecast downward and the bias compounds — run out, record 40, forecast 40, bring 44, run out
again. Running out is the expensive failure for a stall, so the observations are corrected
before the frozen engine sees them, in
`lib/features/forecasting/application/stockout_adjustment.dart`
(`adjustForSellouts`). The engine itself is untouched.

Let rate(o) be the engine's own `depletion × 1e6 ÷ exposure` (truncated), `U` the rates of the
observations with `stockout = false` and `C` the ones with `stockout = true`:

- `C` empty → nothing happens; the engine sees the raw history.
- `U` non-empty → each censored rate becomes `max(itsOwnRate, median(U))`, using the engine's
  own median (middle value; floored mean of the two middles for an even count). A sell-out can
  only ever RAISE the estimate, never lower it.
- `U` empty (every observation censored) → the whole history is a lower bound. Every rate
  becomes the largest observed rate, and the line warns that real demand is unknown and probably
  higher. With a single censored observation there is nothing to raise it to, so the number is
  unchanged and only the warning is added — the honest answer is to say so, not to invent a
  multiplier.
- Observations with `stockout = false` are never modified.

The engine consumes depletions, not rates, so a lifted rate is realised as the smallest
depletion the engine reads back as at least that rate: `ceil(rate × exposure ÷ 1e6)`, all
integer (ADR 0001). That makes the transform **monotone** — every adjusted depletion is >= the
one it replaced, so every adjusted rate is >=, so the median is >=, so the adjusted forecast is
never below the unadjusted one. `test/domain/stockout_adjustment_test.dart` pins this as a
property over a seeded deterministic RNG.

Three invariants hold around it:

1. **Stored evidence keeps the confirmed numbers.** `forecast_evidence` rows are the real
   closeout figures with their real flags. An adjusted depletion is never written where a
   confirmed outcome belongs — it exists only in memory, on the way into the engine.
2. **Replay applies the same transform.** "Same inputs ⇒ byte-identical outputs" means
   `adjustForSellouts(storedEvidence)` then `forecastDirect`, exactly as generation did. The
   engine envelope check (below) also runs on the ADJUSTED observations, so a raised rate cannot
   slip past it.
3. **The owner is told in her own words.** Affected lines carry a plain-language warning beside
   the engine's own strings — "You ran out on 2 of these days, so demand was probably higher
   than recorded — this allows for that." — and the line-detail assumptions card shows how much
   of the history it touched. No "censored", no "quantile".

**`inputs_hash` canonical encoding (normative).** SHA-256 (`package:crypto`) lowercase hex over
the UTF-8 bytes of:

```dart
String canonicalInputs(SnapshotInputs s) {
  // s.lines sorted by itemId bytewise ascending;
  // evidence in label-query order (scheduled_date DESC, event_id DESC).
  // The leading tag is the METHOD version: it moves whenever the same inputs
  // start producing different outputs (v1 -> v2 = sell-out handling;
  // v2 -> v3 = the per-event demand basis). The live encoding interpolates
  // `forecastMethodVersion` rather than a literal, and appends the material
  // per-line fields schema v2/v3 added (|s=, |r=, |b=per_event, |pe=) — see
  // lib/features/forecasting/domain/snapshot_inputs.dart and forecasting.md.
  final b = StringBuffer()
    ..write('direct_median|3|${s.policy.name}|${s.upcomingExposure}|${s.historyWindow}');
  for (final line in s.lines) {
    b.write('\n${line.itemId}|${line.packSizeMicros}'
        '|${line.onHandMicros}|${line.confirmedInboundMicros}');
    for (final e in line.evidence) {
      b.write(';${e.closeoutId}:${e.exposure}:${e.depletionMicros}'
          ':${e.stockout ? 1 : 0}:${e.approximate ? 1 : 0}');
    }
  }
  return b.toString();
}
```

`on_hand_micros` in the encoding is the stored **signed** value. Same hash ⇒ byte-identical
outputs (reproducibility); the applier recomputes and rejects a mismatched
`SaveForecastSnapshot`; `isStale` rebuilds the encoding from live state and compares.

Because the method version tags the encoding, that implication survives a method change: every
snapshot stored by v1 now recomputes to a different hash and reads as out of date, which is
exactly what it is. The forecast screen checks the stored `method_version` first and names that
reason rather than claiming the inputs changed, so the banner is never a lie.

**Actuals are derived, never stored** — the accuracy read model joins the latest snapshot's
lines to the latest closeout revision's lines on `(event_id, item_id)`: per item
`actualDepletion`, `varianceMicros = actual − expectedUse`, `stockout`/`approximate` flags, plus
the live override (latest `forecast_overrides` row per snapshot line). This satisfies "forecasts
expose evidence, assumptions, method/version, overrides, and actuals" from one persisted record.

### 6.7 Gate 4/5 seams (declared now, one file)

```dart
// lib/features/agent/domain/seams.dart
/// Gate 4. The agent NEVER writes: it emits Proposals of the same sealed WorkspaceCommand
/// types, which park in ApprovalService.stage until a human approves. This file is the
/// LocalAgent seam named by the architecture.
abstract interface class LocalAgent {
  Stream<AgentTurn> run(AgentRequest request);
}
final class AgentRequest {
  const AgentRequest(this.utterance);
  final String utterance;
}
sealed class AgentTurn { const AgentTurn(); }
final class AgentMessageTurn extends AgentTurn {
  const AgentMessageTurn(this.text);
  final String text;
}
final class AgentProposalTurn extends AgentTurn {
  const AgentProposalTurn(this.proposal);
  final Proposal proposal; // consumed by ApprovalService.stage
}

/// Gate 5. OCR output is an untrusted RecipeFormDraft proposal that prefills the existing
/// recipe form; images live ONLY inside a ScratchSpace session ('ocr') and are swept per §10.
/// This is the RecipeOcr seam.
abstract interface class RecipeOcr {
  Future<RecipeOcrResult> extract({required String imagePath, required Directory session});
}
final class RecipeOcrResult {
  const RecipeOcrResult({required this.draft, required this.uncertainFields});
  final RecipeFormDraft draft;
  final List<String> uncertainFields;
}
```

---

## 7. Startup & key management

### 7.1 Key lifecycle

```dart
// lib/infrastructure/security/key_manager.dart
abstract interface class KeyManager {
  Future<bool> hasDatabaseKey();
  Future<Uint8List> getOrCreateDatabaseKey(); // 32 bytes; creates on first call
  Future<void> rekeyDatabase(Uint8List newKey); // PRAGMA rekey seam; no UI in v1
  Future<void> destroyDatabaseKey(); // ONLY from the workspace-reset flow
}
```

Generation: 32 bytes from `Random.secure()` (platform CSPRNG). Storage:
`flutter_secure_storage` ^11.0.0, key name `loadout.db_key.v1`, value 64-char hex:

```dart
const _storage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
```

The posture (iOS `first_unlock_this_device`, Android Keystore-wrapped encrypted preferences) is
normative — verify the exact v11 option names at implementation time.
`first_unlock_this_device`: background writes/cleanup keep working after the device re-locks,
the key stays sealed on a never-unlocked stolen device, and the key is non-migratable — it never
enters iCloud Keychain or device transfer. The only cross-device migration path is Loadout's own
encrypted backup (§8). The key never appears in logs, exports, or the DB.

### 7.2 Database open path

DB file: `getApplicationSupportDirectory()/db/loadout.db` — app-private on both platforms, never
`Documents`, never external storage. iOS: exclude the `db/` and `scratch/` directories from
backup via `NSURLIsExcludedFromBackupKey` (a ~10-line MethodChannel in `AppDelegate.swift`), and
hold every file at `NSFileProtectionCompleteUntilFirstUserAuthentication` (matches the Keychain
class; `Complete` would revoke handles mid-WAL-write). That is the platform default, so it needs
NO entitlement — `com.apple.developer.default-data-protection` exists to RAISE the default to
`Complete`, and requesting the weaker value makes the entitlement unprovisionable, failing the
device build outright. The class is proven instead against the real file on a real device by
`integration_test/device_encryption_test.dart`, which reads back what iOS actually applied.

```dart
// lib/infrastructure/db/open_database.dart
QueryExecutor openLoadoutExecutor({
  required File file,
  required Uint8List key, // exactly 32 bytes
}) {
  assert(key.length == 32);
  final hexKey = hexEncode(key); // 64 lowercase hex chars
  return NativeDatabase.createInBackground(
    file,
    // No library-override step: the pubspec `source: sqlcipher` hook makes package:sqlite3
    // load SQLCipher process-wide, in every isolate. The setup callback runs on every opened
    // connection, in whichever isolate opens it.
    setup: (db) {
      db.execute('PRAGMA key = "x\'$hexKey\'";');
      // Refuse to run if the hook is misconfigured and plain SQLite loaded.
      final v = db.select('PRAGMA cipher_version;');
      if (v.isEmpty || (v.first.values.first as String).isEmpty) {
        throw StateError('SQLCipher not linked; refusing plain SQLite');
      }
      // Wrong-key check: throws SqliteException(26) "file is not a database".
      db.select('SELECT count(*) FROM sqlite_master;');
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('PRAGMA journal_mode = WAL;'); // WAL pages are encrypted
      db.execute('PRAGMA temp_store = MEMORY;');
    },
  );
}
```

SQLCipher 4 defaults stand (AES-256-CBC, per-page HMAC-SHA512); the raw key form skips the
internal KDF. `cipher_memory_security` is deliberately OFF (CPU cost for no coverage against an
attacker who already reads app memory).

### 7.3 Five-state startup machine

Bootstrap (before the router shows anything) inspects the `db/` directory and the key store.
"Parked" means recoverable ciphertext sitting somewhere other than `db/loadout.db`: either
`db/loadout.db.pre-restore` (a restore that died mid-swap, §8.2) or a `db/orphaned-<utcstamp>.db`
archive left by an earlier start-fresh.

| DB file | Parked | Key | Behavior |
|---|---|---|---|
| absent | none | absent | `/welcome` — fresh workspace creation (key generated on create) |
| present | any | present | Normal open; wrong-key check guards mismatch → `/recovery` on failure |
| present | any | absent | **`/recovery`** — "This device can't unlock the existing data." Actions: (a) **Restore from a Loadout backup file** (§8 flow), (b) **Start fresh** — typed confirmation word, then the orphaned ciphertext is archived to `db/orphaned-<utcstamp>.db` (never deleted) and a new workspace is created with a new key |
| absent | none | present | Treat as fresh workspace; overwrite the key entry with a newly generated key, continue to `/welcome` |
| absent | **some** | any | **`/recovery`** (`StartupParkedWorkspace`) — "Your workspace is still on this device." Action (a) **Put my workspace back**, plus the two above. **No key is rotated or destroyed on this path.** |

The last row is the interrupted-restore hole, and it is why the fourth row is not enough on its
own: `restoreBackup` renames the live workspace aside while it re-encrypts the payload (§8.2), so
a process death in that window leaves no live database and a key that still opens the parked
copy. Reading that as a fresh install rotates the key over data that is sitting right there.
So bootstrap scans for parked ciphertext **before** it may conclude anything, and never rotates
or destroys a key while recoverable ciphertext exists.

Putting a copy back is validated before anything moves, with the care §8.2 takes over a restore
payload: the copy is staged in scratch, every key on the device is tried against it, and the
winner must pass `cipher_integrity_check`, `integrity_check`, `user_version >= 1` and a
`workspace_meta` singleton. Only then is the parked file **renamed** into place (never
copy-then-delete); if the real open still fails, the rename and any key change are undone. Every
refusal (`liveWorkspacePresent`, `missing`, `noKeyOnDevice`, `noMatchingKey`, `damaged`,
`openFailed`) leaves the copy byte-identical where it was.

A live `db/loadout.db` always wins over anything parked beside it — the §8.2 swap completed, so
it is the authoritative copy. The parked one is retired to an `orphaned-*` archive with its key
retained (never deleted) and logged as `parkedWorkspaceFound`, which also stops a later restore's
rollback renaming a stale `.pre-restore` back over a newer workspace.

Never silently delete a DB file; never auto-create a new DB over the present/absent case. A
wrong-key open failure routes to the same `/recovery` screen, which additionally names any parked
copies it found so they are not invisible.

---

## 8. Backup / restore

### 8.1 Container

One file, `loadout-backup-<yyyymmdd>-<hhmmss>.loadout` — a zip (STORED, no compression;
ciphertext doesn't compress) built with `package:archive`:

```
├── manifest.json      (cleartext)
└── payload.db         (standalone SQLCipher-4 database, raw-key)
```

The payload is produced from the live connection with plaintext never touching disk:
`ATTACH DATABASE '<staging>/payload.db' AS export KEY "x'<hex>'"; SELECT
sqlcipher_export('export'); DETACH DATABASE export;` under
`exportKey = Argon2id(passphrase, salt)`. SQLCipher's per-page HMAC-SHA512 is the payload's
integrity + authentication (the AEAD role).

`manifest.json` fields: `format: "loadout-backup"`, `formatVersion: 1`, `appVersion`,
`schemaVersion` (advisory), `createdAtUtc`, `kdf: {algorithm: "argon2id", saltB64,
memoryKiB: 19456, iterations: 3, parallelism: 1, hashLength: 32}`, `cipher:
"sqlcipher4-rawkey"`, `payloadSha256`, `counts: {movements, items, events}`. Manifest tampering
can only cause a refused restore (tampered KDF params → wrong key → key-check fails), never a
corrupted import; `payloadSha256` is a cheap truncation check before the KDF. KDF: `DartArgon2id`
(`package:cryptography`), parameters recorded in the manifest so future versions can raise costs
without breaking old files. Passphrase UX: entered twice, hard minimum 8 chars, advisory meter
recommending 12+, explicit "cannot be recovered" warning.

File egress/ingress: `flutter_file_dialog` only — save-file (SAF `ACTION_CREATE_DOCUMENT` /
`UIDocumentPicker` export) and pick-file. No share sheet in v1.

### 8.2 Service contract (infrastructure; Result-wrapped by `BackupFacade`)

```dart
// lib/features/backup/domain/backup_service.dart (interface)
// lib/infrastructure/backup/backup_service_impl.dart (implementation)
abstract interface class BackupService {
  Future<File> createBackup(
      {required String passphrase, void Function(BackupPhase)? onProgress});
  /// Manifest only — requires NO passphrase (manifest is cleartext).
  Future<BackupDescription> describeBackup(File container);
  /// Full validation; never touches the live DB. Throws typed BackupError.
  Future<RestorePreview> validateBackup({required File container, required String passphrase});
  /// Whole-workspace replace, atomic. No merge mode exists.
  Future<void> restoreBackup(RestorePreview preview);
}
```

`validateBackup` steps, all before the live DB is touched: (1) copy the picked file into
`support/scratch/restore/<uuid>/`; (2) zip structure + manifest schema + `formatVersion == 1`;
(3) `payloadSha256` matches; (4) derive `exportKey` with manifest KDF params, open `payload.db`
read-only — wrong passphrase fails here; (5) `PRAGMA cipher_integrity_check` then
`PRAGMA integrity_check`; (6) read **`PRAGMA user_version`** of the payload — must be ≤ the
app's current `schemaVersion`, else refuse ("backup from a newer version"); the manifest's
`schemaVersion` is advisory only; (7) domain validation on the decrypted payload, limited to
checks that exist: `PRAGMA foreign_key_check` clean; sign-per-kind scan over movements; reversal
pairing (every reversal's target exists, same item, exact delta negation, targets unique);
closeout arithmetic (worksheet CHECK re-verified, linked consume/waste movements match line
values); `RecipeGraph.detectCycles` on live revisions. There is **no sequence-number check** —
ids are ULIDs and no sequence column exists.

`restoreBackup`: confirm UI (verified counts + createdAt, typed word "REPLACE"); close live DB;
rename `db/loadout.db` (+`-wal`, `-shm`) → `db/loadout.db.pre-restore`; re-encrypt payload under
the **device key** via `sqlcipher_export` into `db/loadout.db.new`; atomic rename to
`loadout.db`; reopen; run drift migrations if the payload schema is older; post-open sanity
(key-check + workspace_meta read). On success delete staging and the `.pre-restore` copy; on any
failure rename `.pre-restore` back and reopen. Invariant: at every instant exactly one openable
authoritative DB exists.

Pre-migration safety (future schema v2+): a plain file copy of the device-key-encrypted
`loadout.db` to `db/pre-migration-v<N>.db` before `onUpgrade`; deleted on success.
Passphrase-based export is never invoked from the open path.

---

## 9. Complete screen map

Navigation: `go_router`, one `GoRouter` instance built once, redirect driven by
`refreshListenable` (a `ValueNotifier` bumped from a `workspaceProvider` listener) — never by
recreating the router. `StatefulShellRoute.indexedStack` hosts a five-tab M3 `NavigationBar`
(Home · Events · Items · Recipes · Settings); forms and detail screens push full-screen on the
root navigator. Deep links disabled at platform level (no Android link `intent-filter`;
`FlutterDeepLinkingEnabled = false`). Dirty forms intercept back with `PopScope` + discard
dialog. Bootstrap alone can route to `/recovery`. Visual language: M3,
`ColorScheme.fromSeed(0xff356859)`, brightness from the owner's own choice (`theme_mode`
setting: Follow phone / Light / Dark, `ThemeMode.system` until she picks), content columns
`maxWidth: 640`, primary buttons ≥ 56 dp.

The route table below is the one in `lib/app/router.dart` as it stands today (re-verified against
that file; it is the authority if the two ever drift):

```
/  ->  /home
/welcome  /welcome/create  /recovery
[shell] /home  /events  /items  /recipes  /settings
/events/new  /events/:eventId  /events/:eventId/edit
/events/:eventId/forecast  /events/:eventId/forecast/:itemId
/events/:eventId/closeout  /events/:eventId/closeout/report
/items/new  /items/scan-in  /items/:itemId  /items/:itemId/edit
/movements/new  /movements/:movementId  /movements/:movementId/correct
/activity
/recipes/new  /recipes/:recipeId  /recipes/:recipeId/revise
/settings/backup  /settings/restore  /settings/export  /settings/privacy
/settings/about  /settings/diagnostics  /settings/reset
```

**There is no `/production` route and no production-planning screen.** An earlier revision of
this document specified a `/production` stub; it was built and then deleted. Production planning
is a future capability with no current surface anywhere in the app — see §13.

**`/welcome` — WelcomeScreen.** Value prop + "Nothing is uploaded"; CTA → `/welcome/create`. No
commands. Empty: n/a. A11y: existing `Semantics` pattern kept.

**`/welcome/create` — CreateWorkspaceScreen.** Create the single local workspace. Widgets:
workspace name (default "My workspace"), default policy (`SegmentedButton<PlanningPolicy>` with
reserve-% captions), exposure label (default "attendance"), unconditional device-lock advisory
card ("Loadout's data is encrypted on this device. Protect it with your phone's screen lock.").
Commands: `SettingsService.createWorkspace` (key generation invisible); redirect flips to
`/home`. Errors: content-free full-width card with retry. A11y: sticky 56 dp button in
`SafeArea`.

**`/recovery` — RecoveryScreen.** Full §7.3 state machine: message per state; actions "Restore
from backup file" (embeds the §8 flow) and "Start fresh" (typed confirmation; archives orphaned
ciphertext; new workspace). Reachable only from bootstrap. A11y: labeled buttons, no icon-only
controls.

**`/home` — HomeScreen.** "What needs attention now." Widgets, in priority order: (1)
pending-closeout nudge for any `active` event past its date → `/events/:id/closeout` — the most
important nudge in the app; (2) next-event card with forecast readiness ("3 of 8 items have no
history"); (3) quick actions "Record purchase" → `/movements/new?kind=receive`, "Count stock" →
`/movements/new?kind=count` (56 dp tonal buttons); (4) data health — items with negative derived
on-hand ("Tortillas shows −2 kg — record a count to fix") → count flow; (5) last 5 movements +
"See all" → `/activity`. Commands: none (read-only). Empty (fresh workspace): illustration +
"Start by adding the items you bring to events" + Add item. A11y: cards are single semantic tap
targets ≥ 56 dp.

**`/items` — ItemListScreen.** Catalog + on-hand at a glance. Widgets: `SearchAnchor`, category
`FilterChip` row (`categorySuggestions`), tiles (name, category, `on-hand · unit` — negatives
shown signed with warning icon + label, never clamped — pack caption), archived toggle in
overflow, FAB → `/items/new`. Commands: none. Empty: "No items yet. Add what you sell or bring."
A11y: rows ≥ 56 dp; on-hand announced with unit.

**`/items/new`, `/items/:itemId/edit` — ItemEditScreen.** Widgets: name (required, live
unique-among-live check), unit (`DropdownMenu`, closed list each/g/kg/ml/L — **read-only in edit
mode once the item has any movement**; helper explains archive+recreate), pack size
(`QuantityFormField`, required > 0, helper "How many <unit> per pack you buy or load — used for
rounding"), category (free text + autocomplete), notes. Commands: `CatalogService.createItem` /
`updateItem` (plain updates — no revision log, no reason field). A11y: fields labeled; unit lock
announced via `Semantics`.

**`/items/:itemId` — ItemDetailScreen.** Derived truth for one item. Widgets: header
(name/category/unit/pack); **On hand** stat from `stockPositionProvider` (signed, warning badge
when negative); actions "Record movement" → `/movements/new?itemId=…` and "Count" →
`?kind=count`; day-grouped movement history — reversed rows struck-through with "Corrected" chip
(history never hidden); menu: Edit, Archive. Commands: `CatalogService.setArchived`. Empty
history: "No movements yet. Record a purchase or a count to establish on-hand." A11y: struck
rows get `Semantics(label: 'Corrected entry: …')`.

**`/events` — EventListScreen.** Widgets: `SegmentedButton` filter (Upcoming / Active / Closed /
All); cards (name, date, status chip — icon + text, never color-only — planned exposure); FAB →
`/events/new`. Commands: none. Empty: "Plan your first event to get a load list."

**`/events/new`, `/events/:eventId/edit` — EventEditScreen.** Widgets: name, scheduled date
(`showDatePicker`), optional start/end times, planned exposure (integer, label from
`exposure_label` setting; optional at create — required before forecasting), policy (defaulted
from workspace), planned items (multi-select bottom sheet over catalog, chips inline). Commands:
`EventService.createEvent` / `updateEvent` (plain updates; no revision badge, no reason). Edit
allowed while `planned`/`active` only.

**`/events/:eventId` — EventDetailScreen.** Lifecycle hub. Widgets: header (name, date, status
chip, planned exposure); tiles: (1) **Packing list** → `/forecast` (subtitle read from the
latest snapshot row — never hardcoded); (2) **Close out** → `/closeout` (primary-styled once the
event date passes; after closing shows "Closed on <date>" + Revise); (3) **Accuracy review**
(closed events only). Then the money — "Estimated cost" while planned/active, "Spent" once
closed — planned items, and the closeout-revisions summary for closed events. **No Load-out or
Returns tiles, and no Production tile:** the disabled "Production plan — coming soon" row
specified by an earlier revision of this document was built and then removed, along with the
`/production` stub behind it, because it never navigated anywhere. App-bar: Edit, Start this
event (planned → active), Cancel (planned ONLY — an activated event must be closed out, §12.15).
Commands: `EventService.activate` / `cancel`. A11y: tiles ≥ 56 dp. Verified against
`lib/features/events/presentation/event_detail_screen.dart`.

**`/events/:eventId/forecast` — ForecastReviewScreen.** The release-contract surface. Renders
the **persisted latest snapshot** (`latestSnapshotProvider`) — never a live recompute. Widgets:
sticky header "Method: direct_median v1 · computed <relative time>" + policy chip
("Balanced +10 %") + exposure ("for 150 attendance"); **staleness banner** when `isStale`
("Inputs changed since this forecast — Refresh to update"; Refresh →
`ForecastService.generateSnapshot`, appending a new snapshot — the old one remains); no snapshot
yet → explainer + "Generate forecast" (disabled with hint until planned exposure and items are
set); per item a `ForecastLineCard`: evidence badge (icon + text: "No history" / "1 event" /
"N events"), four figures **Expected · Planned · Load · Acquire** (nulls render "—" with CTA
"Set a baseline" → override form, reason prefilled "baseline"), warning chips (amber, icon +
text, stored strings), override indicator (engine value struck-through beside override +
"Overridden: <reason>" chip). Closed-event accuracy mode: read-only + **Actual** column and
delta caption ("forecast 36, actual 31, +16 %") from `accuracyReview`. Empty (no planned items):
"Add items to this event to see a load list." A11y: four-figure row wraps 2×2 at large type;
badges never color-only.

**`/events/:eventId/forecast/:itemId` — ForecastLineDetailScreen.** Sections: (1) Result — four
figures with the arithmetic narrated ("median of 2 observed rates × 150 attendance, +10 %
reserve, rounded up to packs of 12, minus 10 on hand"); (2) Evidence — one row per stored
`forecast_evidence` value-copy (source event + date, exposure, depletion, stockout/approximate
chips; tap → event detail) — exactly what the engine consumed; (3) Assumptions — exposure,
policy, pack size, on-hand at generation (signed) + timestamp, "inbound: 0", history window;
(4) Warnings — full stored sentences; (5) Override — `QuantityFormField` + required reason (min
3 chars); "Apply override" → `setOverride(snapshotId, …)`; "Clear override" → `clearOverride`
(appends a NULL-load override row); copy: "Overrides change this plan only. Forecasts learn from
closeouts, never from overrides."; (6) footer: method id + version.

**`/events/:eventId/closeout` — CloseoutScreen.** The label factory; single scrollable form,
autosaved (debounced 500 ms) to `closeout_drafts` via `saveDraft`, reloaded via `loadDraft`.
Widgets: (1) **Confirmed exposure** (required): "How many people actually came?" — prefilled
with the planned estimate, marked "estimate was 150"; (2) per-item `CloseoutLineCard` for each
planned item (see below); (3) optional note; (4) pinned progress header ("23 of 60 confirmed")
and a sticky 64 dp **"Finish closeout"** button with a confirmation bottom sheet ("This becomes
the history your forecasts learn from"). Commands: `CloseoutService.confirm`; after close,
Revise reopens the same screen → `revise` (revision N+1 per §5), and the flow lands on
`/events/:eventId/closeout/report`. Warnings never block — including negative on-hand.

**The line card asks ONE question** (`lib/features/closeout/presentation/closeout_line_card.dart`).
An earlier revision of this document specified a direct depletion field plus an expandable
Loaded/Returned/Waste worksheet. That worksheet is **gone**. The face of a card now carries four
controls:

- **"How many are left?"** — one `QuantityFormField`. That is the job. The leftover count is
  stored in `closeout_lines.returned_micros` — the schema and the domain keep their names, only
  the UI wording changed.
- **Loaded reads as a line of text** (`Loaded 42`), prefilled from the latest snapshot line's
  effective load (override if there is one, else the engine's, else the baseline's). It only becomes a box when the owner asks for it (More → *Change what was
  loaded*) or when the plan says nothing about the line — a leftover count needs something to
  subtract from.
- **All gone** / **None used** — the two shortcuts. `All gone` writes left = 0 and answers "did
  you run out?" Yes; `None used` writes left = loaded (used = 0).
- **More** — the overflow holding *Change what was loaded*, *Some was thrown out*, *Enter what
  was used instead*, *Skip this item*.

Arithmetic and semantics are unchanged: used = `loaded − left − thrown out`, a blank thrown-out
counting as 0 once a leftover count and a loaded value coexist, and depletion still excludes
waste. **"Ran out" is now contextual**, not a permanent chip: the card asks *"Did you run out?"*
(Yes/No `ChoiceChip`s) only when the line reads as empty (leftover 0) or the flag is already on,
and never blocks the line from confirming. **"Estimate" is gone from the card** — `approximate`
is still written by the write path but is never set here. Card states are colour + icon + word
(Confirmed / In progress / Skipped); a done card collapses to one row and reopens on tap.

**An event can be closed with NO counts at all.** `CommandValidator._closeoutShared` requires
only a confirmed exposure in 1..1 000 000 and validates each line if present, so an empty line
list is a real closeout rather than a hack. The way in is the app-bar overflow — *Close without
counting* (confirms first, collects the headcount in the same dialog if the field is empty) and
*Skip the rest and finish* — deliberately not a second button beside "Finish closeout". The
"Finish closeout" button itself stays disabled until every line is done, so the overflow is the
only path out of a partial count.

A11y: 56 dp targets; the state word moves under the item name above ~1.3× text scale.

**`/movements/new` — MovementEntryScreen.** The only manual ledger entry. Widgets: kind
`SegmentedButton` — **Purchase** (`receive`), **Waste**, **Count** (`adjust`), nothing else;
prefilled from `?kind=`; item picker (searchable sheet, on-hand inline); Count mode swaps the
quantity field for "On hand now (derived): 12 kg" + "Counted" field + signed-adjustment preview
("will record −1.5 kg adjustment"); Waste mode offers optional event association (defaults to
the active event), Purchase/Count none; occurred-at (defaults now); optional note ("stored
encrypted, never logged"); sticky "Record" + "Record & add another". Commands:
`InventoryService.record` / `recordCount` — the UI never does ledger math. Quantity > 0 (Count
may equal current); negative-result warning shown from the receipt, non-blocking. A11y:
`QuantityFormField` carries `Semantics(label: 'Quantity in <unit>')`.

**`/activity` — ActivityScreen.** Global ledger, newest first, day-grouped; `FilterChip`s
(kind/item/event); rows: kind icon + label, item, signed quantity + unit, event tag, time;
reversed rows struck-through "Corrected"; reversal rows "Correction of <entry>". Commands: none.
Empty: "Every purchase, waste, count, and closeout lands here — permanently."

**`/movements/:movementId` — MovementDetailScreen.** Read-only + provenance: occurred vs
recorded, event link, source command id, correction links. Single action "Correct this entry" —
copy: "Corrections keep the original entry visible and add a reversing entry." No delete, no
edit.

**`/movements/:movementId/correct` — CorrectionScreen.** Prefilled replacement form + required
reason + "Reverse only (no replacement)" toggle. Commands: `InventoryService.correct` (atomic
reversal + optional replacement).

**`/recipes` — RecipeListScreen.** Tiles: name, yield caption, ingredient count, "rev N"; FAB →
`/recipes/new`. Commands: none. Empty: "Recipes let Loadout plan production later. Enter one by
hand — takes a minute."

**`/recipes/new`, `/recipes/:recipeId/revise` — RecipeEditScreen.** This form **is** the Gate 5
OCR fallback — build it complete now; OCR will prefill it as an unapproved proposal. Widgets:
name, output item picker, yield (`QuantityFormField` + free-text yield label "12 tacos"), note;
repeating ingredient rows (item picker + `QuantityFormField` in the item's unit; duplicates
rejected inline); "Add ingredient"; swipe-to-remove (drafts only). Commands:
`RecipeService.createRecipe` / `reviseRecipe` (revise appends an immutable revision; validator
runs `assertFlat` / `detectCycles`).

**`/recipes/:recipeId` — RecipeDetailScreen.** Latest revision read-only; revision
`DropdownMenu` ("Revision 3 · 2026-08-02") renders any prior revision verbatim; app-bar: Revise,
Archive. Commands: `RecipeService.setArchived`.

*(A `/production` — ProductionPlanningScreen stub was specified here and shipped; it has since
been deleted along with its route. Production planning has no screen. See §13.)*

**`/settings` — SettingsScreen.** Groups: Workspace (name, default policy, exposure label,
history window); Appearance (Follow phone / Light / Dark, three radio rows — the choice is
appearance only and touches no data); Data (Backup, Restore); Privacy; Diagnostics; About;
danger zone (Reset workspace). Commands: `SettingsService.updatePreferences` and
`SettingsService.setThemeMode` (plain upserts).

The appearance choice is its own `settings` row (`theme_mode` = `"system"` / `"light"` /
`"dark"`, unset means system) with its own watch stream rather than a `Workspace` field:
`/welcome` and `/recovery` render before any workspace — and before any database — exists, and
they inherit the choice from the one `MaterialApp` like every other route. Bootstrap reads it
once before `runApp` (`startupThemeChoiceProvider`) so the first frame is already correct;
`themeChoiceProvider` falls back to that value whenever there is nothing to read.

**`/settings/backup` — BackupScreen.** Explainer ("one encrypted file; anyone with file +
passphrase can read everything"); passphrase ×2 (min 8, advisory meter recommending 12+);
"Create backup file…" → progress phases → save dialog (`flutter_file_dialog`); last-backup
timestamp. Commands: `BackupFacade.createBackup`.

**`/settings/restore` — RestoreScreen.** Pick file → manifest info shown immediately
(`describeBackup`, no passphrase) → passphrase → verified preview (`validateBackup`: counts,
created-at, schema) → typed "REPLACE" confirm → `restoreBackup` → app restarts to `/home`.
Wrong-passphrase vs corrupt-file get distinct content-free messages.

**`/settings/privacy` — PrivacyScreen.** Static: no accounts / cloud / analytics / network
permission (CI-enforced), encryption at rest, backup contents, content-free diagnostics.

**`/settings/diagnostics` — DiagnosticsScreen.** Content-free log viewer over the `Diag` ring
buffer/file; "Save diagnostics file…" via `flutter_file_dialog` — the only way logs leave the
device, deliberately.

**`/settings/reset` — WorkspaceResetScreen.** Typed-confirmation destructive reset: archives
ciphertext to `db/orphaned-<utcstamp>.db`, calls `KeyManager.destroyDatabaseKey()`, returns to
`/welcome`.

**`/settings/about` — AboutScreen.** Version/build, forecast method registry ("direct_median —
v1 — since 2026-08"), `showLicensePage` (includes the SQLCipher BSD-style license).

### 9.1 Provider architecture (Riverpod 2.x)

```dart
// infrastructure
final appDatabaseProvider    = Provider<AppDatabase>((_) => throw UnimplementedError());
final forecastEngineProvider = Provider<ForecastEngine>((_) => const DeterministicForecastEngine());
final approvalServiceProvider = Provider<ApprovalService>(...);
// application services: settingsService, catalogService, eventService, inventoryService,
// forecastService, closeoutService, recipeService, backupFacade — each a Provider wiring the
// db + approval service.

// projections (drift watch() -> streams; autoDispose below workspace level)
final workspaceProvider   = StreamProvider<Workspace?>(...);
final itemListProvider    = StreamProvider.autoDispose.family<List<ItemSummary>, ItemFilter>(...);
final itemDetailProvider  = StreamProvider.autoDispose.family<ItemDetail, String>(...);
final stockPositionProvider = StreamProvider.autoDispose.family<StockPosition, String>(
    (ref, id) => ref.watch(inventoryServiceProvider).watchPosition(id));
final eventListProvider   = StreamProvider.autoDispose.family<List<EventSummary>, EventStatusFilter>(...);
final eventDetailProvider = StreamProvider.autoDispose.family<EventDetail, String>(...);
final movementLogProvider = StreamProvider.autoDispose.family<List<MovementView>, MovementFilter>(...);
final ledgerVersionProvider = StreamProvider<int>(
    (ref) => ref.watch(inventoryServiceProvider).watchVersion());

// forecast: read PERSISTED snapshots; staleness is explicit, never silent.
final latestSnapshotProvider = StreamProvider.autoDispose.family<ForecastSnapshotView?, String>(
    (ref, eventId) => ref.watch(forecastServiceProvider).watchLatestSnapshot(eventId));
final forecastStalenessProvider = FutureProvider.autoDispose.family<bool, String>((ref, eventId) {
  ref.watch(eventDetailProvider(eventId)); // exposure/policy/item changes
  ref.watch(ledgerVersionProvider);        // on-hand + history changes
  ref.watch(latestSnapshotProvider(eventId));
  return ref.watch(forecastServiceProvider).isStale(eventId);
});
final accuracyReviewProvider = FutureProvider.autoDispose.family<AccuracyReview, String>(
    (ref, eventId) => ref.watch(forecastServiceProvider).accuracyReview(eventId));
```

Form controllers: one `AutoDisposeNotifier` family per form holding a draft +
`AsyncValue<void> submission`; `submit()` guards double-taps; screens `ref.listen` on
`submission` to pop/snack. The closeout controller debounces `saveDraft` (500 ms).

Quantity entry: shared `QuantityFormField` + `QuantityCodec` — decimal-string splitting to
micros ("1.5" → 1_500_000), `.` and `,` both accepted, ≤ 6 fraction digits, reject-at-keystroke
formatter, integer-only formatting back; `double` never appears. Exposure fields are digits-only
`int.parse`.

Cross-cutting UX: field errors inline; command failures as content-free snackbars ("Couldn't
save this entry. Try again." — names/quantities never appear in error text); fatal DB failures
route to `/recovery`. Touch targets ≥ 48 dp (primary 56 dp); no `textScaler` clamping (gate:
200 % scale on a 320 dp viewport, no clipping); meaning never color-only; icon-only buttons
carry `Semantics` labels.

---

## 10. Diagnostics & privacy hardening

**Content-free diagnostics — structural.** The logging API has no free-text parameter, so a log
line physically cannot carry content:

```dart
// lib/core/diagnostics/diag.dart
enum DiagEvent {
  dbOpenOk, dbOpenWrongKey, dbKeyMissing, dbCipherMissing,
  backupCreateOk, backupCreateFail, backupValidateFail, restoreOk, restoreRolledBack,
  scratchSweepOk, migrationOk, migrationFail, commandApplied, commandRejected,
  // closed set — additions are code-reviewed
}

abstract interface class Diag {
  void event(DiagEvent event,
      {int? count, Duration? elapsed, String? errorType, int? schemaVersion});
}
```

Allowed per line: UTC timestamp, severity, event code, integer counts/durations, exception
**type name** only (never `toString()`), schema version, random per-session correlation id.
Never: item names, quantities, event names, recipe text, file paths, SQL, exception messages.
Sink: in-memory ring buffer + 256 KB rotating file `support/diag/diag.log` (content-free ⇒
plaintext acceptable), viewed/exported only via `/settings/diagnostics`. `print`/`debugPrint`
banned (`avoid_print` lint + CI grep).

**Scratch-space hygiene.** All ephemera (restore staging, export staging, future OCR images)
live under `support/scratch/<purpose>/<uuid>/`:

```dart
// lib/infrastructure/files/scratch_space.dart
abstract interface class ScratchSpace {
  Future<Directory> createSession(String purpose); // 'ocr' | 'backup' | 'restore'
  Future<void> disposeSession(Directory session);  // try/finally at call sites
  Future<void> sweepAll(); // on every app start and AppLifecycleState.paused
}
```

**Platform hardening (asserted in CI/review):** Android `android:allowBackup="false"`,
`android:fullBackupContent="false"`,
`android:dataExtractionRules="@xml/data_extraction_rules"` with cloud-backup and device-transfer
excludes on root; no `usesCleartextTraffic`. iOS: data protection at
`NSFileProtectionCompleteUntilFirstUserAuthentication` (platform default, verified on device —
see above, and note `Runner.entitlements` is deliberately empty);
`NSURLIsExcludedFromBackupKey` on `db/`
and `scratch/`; no `NSAppTransportSecurity` exceptions; no `UIFileSharingEnabled`;
`FlutterDeepLinkingEnabled = false`.

**Consolidated CI additions** (one canonical list; extends the existing
format/analyze/test/INTERNET-grep steps in `.github/workflows/ci.yml`):

```yaml
- name: Assert no second native sqlite in dependency tree
  run: '! grep -E "^  (sqlite3_flutter_libs|sqlcipher_flutter_libs|drift_flutter|sqflite)" pubspec.lock'
- name: Assert SQLCipher source hook is configured
  run: |
    grep -A3 'user_defines' pubspec.yaml | grep -q 'source: sqlcipher'
- name: Assert no network-capable packages
  run: '! grep -E "^  (http|dio|web_socket_channel|grpc|firebase_[a-z_]+|connectivity_plus):" pubspec.lock'
- name: Assert no raw sockets or HttpClient in app code
  run: '! grep -RE "HttpClient|(Raw)?(Secure)?Socket\.connect" lib/'
- name: Assert Android backups disabled
  run: |
    grep -q 'android:allowBackup="false"' android/app/src/main/AndroidManifest.xml
    grep -q 'android:dataExtractionRules="@xml/data_extraction_rules"' android/app/src/main/AndroidManifest.xml
    ! grep -R 'usesCleartextTraffic="true"' android/app/src/main
- name: Assert no debugPrint in lib
  run: '! grep -R "debugPrint(" lib/'
- name: Assert committed drift schema dump is current
  run: |
    dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/loadout/
    git diff --exit-code drift_schemas/
- name: Assert release manifest has no INTERNET permission
  run: |
    flutter build apk --release --target-platform android-arm64
    $ANDROID_HOME/build-tools/*/aapt dump permissions \
      build/app/outputs/flutter-apk/app-release.apk | (! grep INTERNET)
```

The release-artifact `aapt` check is the authoritative INTERNET gate: Flutter debug/profile
builds inject INTERNET for the VM service, so source greps and debug builds cannot prove the
shipped artifact is clean. The existing source grep stays for fast feedback.

---

## 11. Test plan

### 11.1 Gate 2 unit-test families (pure Dart, `flutter test`)

**A. Quantity / UnitRatio.** `fromMicros` rejects negative, accepts 0 and `maxMicros`, throws
over cap; `plus` checked add at/over cap; `subtractFloor` clamps exactly; `multiplyRatio` ceil
direction (1 micro × 1/3 → 1 micro), exact multiples unrounded, invalid ratios throw;
`roundUpTo` boundaries, zero increment throws; `UnitRatio` gcd normalization, equality,
`applyCeil` matches `multiplyRatio` in range and **throws** where legacy math would wrap int64.

**B. Ledger fold.** Empty ledger → zero; per-kind sign effects; fold determinism under
permutation (tie-break `occurredAt, recordedAt, id`); as-of inclusive boundary (movement at
exactly `asOf` counts, +1 µs doesn't); reversal negates at its own `occurredAt` (as-of before
shows the original); double-reversal and reversing-a-reversal rejected; negative on-hand allowed
with `NEGATIVE_ON_HAND` warning in the receipt (never a rollback); `recordedAt` monotonic under
a same-microsecond `FixedClock` (1 µs tie-bump).

**C. Frozen forecast tier.** Keep the existing tests byte-for-byte, add pins:
`upcomingExposure <= 0` throws; zero-exposure observations filtered, all filtered ⇒
`insufficientData` all-null; even-count median truncating mean pinned to exact micros;
exposure-range warning boundaries (== min/max ⇒ no warning, ±1 ⇒ warning); `acquireQuantity`
floors at zero; envelope pin (depletion 1e12, exposures at caps → exact value, no wrap); one
observation ⇒ `singleEvent`, two ⇒ `observedRange`.

**D. Recipe guards.** `assertFlat`: line referencing a live recipe's output →
`RecipeNestingError` with path; archived recipe's output allowed; output item among own
ingredients rejected. `detectCycles`: self/2/3-cycles detected with deterministic path; flat
graph passes. (Expansion math tests ship with Gate 5.)

**E. Snapshot hash.** Canonical-encoding determinism (line order by itemId regardless of
construction order); sensitivity to every material field (one micro, policy, exposure, window,
evidence id/flags); insensitivity to timestamps and snapshot/command ids; golden vector (fixed
inputs → fixed 64-hex digest) to catch canonicalization drift.

**F. Approval / single write path.** Unknown ids in every command type → `NotFoundError`,
nothing written; archived-item and cancelled-event writes rejected; closeout worksheet mismatch
rejected; closeout confirm writes header + lines + movements with correct
kinds/deltas/`source_command_id` and event → closed; revise writes mirroring reversals + fresh
movements + revision N+1 in one transaction; the label query returns only latest revisions of
closed events; envelope caps enforced; `SaveForecastSnapshot` with tampered hash rejected;
snapshot allowed for planned|active only; override requires reason ≥ 3 and never mutates lines;
NULL-load override reverts display; idempotency (same commandId twice → one write + original
receipt; different payload → `DuplicateIdError`); `stage`/`approve`/`reject` return
`NotAvailableError` and `pending()` is empty in v1; unit-lock on `UpdateItem` after first
movement.

### 11.2 DB/DAO host tests (macOS host, no device)

The pubspec `source: sqlcipher` hook produces a **real SQLCipher build under `flutter test` on
the host** (verified: `PRAGMA cipher_version` returns a version and a keyed DB file is
unreadable without its key — `test/db/cipher_smoke_test.dart` in the repo pins this). Tests open
real encrypted `NativeDatabase`s directly; there are no brew/apt sqlcipher installs, no library
overrides, and no opt-in tags. CI needs network only at build time to fetch the prebuilt
libraries; the app has none at runtime.

Tier 1 (schema/DAO, in-memory): `AppDatabase.forTesting(NativeDatabase.memory())`. Covers: every
CHECK violation throws `SqliteException`; append-only triggers reject UPDATE/DELETE on all nine
tables; the commands trigger permits only staged→applied|rejected; partial unique indexes (live
item names, live recipe per output item); on-hand SQL sum equals a Dart `LedgerMath` fold over
the same rows (property test); reversal round-trips restore on-hand exactly; the §4.3 label
query returns only current revisions of closed events and never reads forecast tables.

Tier 2 (encryption/backup, temp-file DBs, same test run): keep the repo's cipher smoke test and
extend — **DB unreadable without key**: create a keyed DB with a marker string, reopen with
no/wrong key → `SqliteException(26)`; raw file bytes lack the `SQLite format 3\0` magic and the
marker in db/-wal/-shm; the cipher-version guard throws before any write when `cipher_version`
is empty; backup round-trip byte-identical; tamper suite (flipped payload byte →
`cipher_integrity_check` fails; edited manifest KDF params → key-check fails; truncated zip →
sha pre-check fails; wrong passphrase → key-check fails; every failure leaves the live DB
untouched); restore rollback (injected failure → `.pre-restore` restored and openable); Argon2id
pinned against RFC 9106 vectors; Diag line format regex + `DiagEvent` exhaustiveness.

Tier 3 (`integration_test/device_encryption_test.dart`, emulator/simulator or a physical
device): the proofs a host test cannot give, because they are about what the OS actually loads
and stores. Four assertions — the sqlite3 in the app bundle answers `PRAGMA cipher_version`;
the workspace file the app writes carries neither the plain SQLite header nor a canary written
into it (sidecars included); the platform keystore hands the key back to a second service
instance, as after a restart; a rekeyed store yields `StartupRecovery(wrongKey)` with the
ciphertext still on disk. Run with a device attached:

```sh
fvm flutter test integration_test/device_encryption_test.dart -d <device-id>
```

Two environment facts this depends on. **Debug and profile builds carry the INTERNET
permission** (`android/app/src/{debug,profile}/AndroidManifest.xml`): the Dart VM service binds
a local socket, and without it hot reload, DevTools, and this whole tier fail with
`Connection closed before test suite loaded`. Those variants are never shipped, and the release
artifact is what the §10 `aapt` gate inspects. **`compileSdk` is pinned to 37.0**: the plugins
require API 37, which now ships only as minor releases (`android-37.0`, `android-37.1`), while
Flutter's auto-bump asks for a plain `android-37` platform that no longer exists.

What this tier does NOT establish, and a physical device must: latency and memory (an emulator
runs on host CPU), hardware-backed key storage (emulator Keystore is software-backed, and the
iOS Simulator has no Secure Enclave), and iOS Data Protection (the Simulator does not enforce
file protection classes at all).

### 11.3 Gate 3 widget tests (one per workflow)

Create workspace → lands on Home; add item (validation; unit lock in edit after a movement);
record purchase / waste / count (count computes the signed adjust; negative warning shown, not
blocking); correction (reversal + optional replacement; original struck-through in activity);
create/edit event; activate; cancel blocked once active; generate forecast (snapshot persisted;
header shows method/version; refresh appends; staleness banner appears after a ledger write);
override apply + clear (reason enforced ≥ 3); closeout direct path and worksheet path (derived
depletion; excludes waste; draft autosave survives screen kill; confirm closes event and writes
movements); closeout revise; recipe create/revise (duplicate ingredient rejected; nesting
rejected); backup screen passphrase rules; restore preview + typed confirm; recovery screen
states (db-only and wrong-key); reset flow; 200 %-text-scale accessibility pass on Home,
ForecastReview, Closeout.

### 11.4 CI wiring

Jobs: (1) format/analyze + the full `flutter test` run (unit, widget, and DB tiers 1–2 — the
SQLCipher hook makes them all run in one job, no special setup); (2) the §10 assertion steps;
(3) release APK build + `aapt` INTERNET gate; (4) drift schema dump diff. Device integration
(tier 3) runs on the release branch pipeline.

---

## 12. Adopted defaults for open product questions

1. **Money:** quantities-only in v1 — no costs, no prices anywhere.
2. **Exposure:** one integer per event, meaning headcount attendance; the UI label is a
   workspace setting (`exposure_label`, default "attendance").
3. **Waste vs demand:** depletion **excludes** waste — forecasts learn "what sells"; the
   worksheet makes this structural.
4. **Negative stock:** record with warning, never block; Home surfaces it.
5. **Units:** closed list each/g/kg/ml/L; no custom units, no conversions.
6. **Unit lock:** unit immutable after an item's first movement; escape hatch is
   archive + recreate.
7. **Pack size:** single item-level pack size; no per-purchase override.
8. **Categories:** free-text with `DISTINCT` autocomplete; no managed list.
9. **Recipes:** at most one live recipe per output item; nesting forbidden.
10. **History window:** last-N closed events, `history_window_events` setting, default 12,
    recorded in every snapshot.
11. **Comparable-event filtering:** none in v1 — last N regardless of venue.
12. **Confirmed inbound:** column exists, defaults 0, no UI in v1.
13. **Live mid-event tracking:** none — plan sheet + closeout only; no locations, no load-out
    movements.
14. **Closed events:** permanently locked; corrections only via closeout revisions.
15. **Cancelled events:** cancel allowed only pre-activation; an activated event is closed out
    (approximate if needed); existing movements stand.
16. **Reserve:** per-plan policy only (lean/balanced/cautious); no per-item reserve overrides.
17. **Override reason:** mandatory, ≥ 3 characters, including on clear.
18. **App lock:** none in v1; OS-lock advisory card; optional biometric re-prompt is Gate 6.
19. **Backup egress:** save-file-only (`flutter_file_dialog`); no share sheet.
20. **Backup passphrase:** hard minimum 8 chars, advisory meter suggesting 12+.
21. **Restore:** whole-workspace replace only; merge-restore is out of scope.
22. **Retention:** snapshots/overrides kept forever; `.pre-restore` deleted on success; backup
    nudging is an in-app banner only (no notification permission). iOS export-compliance
    declarations (`ITSAppUsesNonExemptEncryption`, ANSSI) are decided at Gate 6.

---

## 13. Deferred beyond v1

Cut from Gates 2–3; the schema and seams are shaped so each returns additively:

- **Quarantine pool** (`quarantine`/`release`/`disposal` kinds, two-pool `StockPosition`,
  usable-vs-on-hand distinction).
- **Unit system** (`units`/`unit_conversions` tables, dimensions, entered-amount/entered-unit
  audit columns on movements).
- **`item_packs`** (multiple named pack sizes) and the **`item_categories`** table.
- **`tracking_kind`** and **`low_stock_threshold_micros`** on items.
- **`opening` movement kind** (initial stock is an `adjust`).
- **Recipe-derived forecasting and whole-plan aggregation** (Gate 5): `RationalMicros`,
  `forecastRecipeDerived`, `planEvent`, `DemandContribution`, sum-then-ceil aggregation,
  `PlanHasher` canonical-JSON machinery, `RecipeExpansion`, and their test families.
  `forecastDirect` stays frozen; new tiers are additive methods on the same `ForecastEngine`
  seam.
- **ApprovalService staged lifecycle** (Gate 4): `stage`/`approve`/`reject`/`pending` bodies and
  the `commands.status = 'staged'` path; the interface, table column, and triggers already
  exist.
- **`LocalAgent` execution** (Gate 4) and **`RecipeOcr` execution** (Gate 5): seams declared in
  §6.7; OCR images bound to `ScratchSpace('ocr')`.
- **Item/event revision logs with reasons** (master data stays plainly mutable).
- **Deterministic production planning** (Gate 5): a future capability with **no current screen
  and no route**. The `/production` stub this document once specified was built and then
  deleted, together with its tile on the event screen, because a disabled dead end taught the
  owner nothing. Nothing in `lib/` references production planning today; a
  `ProductionPlanService` interface and whatever surface it needs both land at Gate 5.
- **Migration verifier CI** (`SchemaVerifier`) and the pre-migration safety copy: activate with
  the first real migration (schema v2).
- **Ledger checkpoints** (`item_stock_checkpoints`): only if ledgers outgrow index-scan sums.
- **Gate 6 hardening:** optional biometric re-prompt, share-sheet export decision,
  `.pre-restore` retention policy, snapshot pruning setting, FLAG_SECURE/screenshot policy,
  export-compliance declarations, manual device QA (reboot-no-unlock data inaccessibility,
  mid-export backgrounding, cross-device restore).
