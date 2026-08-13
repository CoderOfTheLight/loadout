// Drift's documented self-referencing `check(column.…)` pattern trips the
// recursive_getters lint; the getters never run at runtime (drift_dev extracts
// the expression and the generated table overrides every column).
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

// ---------------------------------------------------------------- workspace

class WorkspaceMeta extends Table {
  IntColumn get id => integer().check(id.equals(1))(); // singleton row
  TextColumn get workspaceUid => text().withLength(min: 26, max: 26)();
  TextColumn get displayName =>
      text().withDefault(const Constant('My workspace'))();
  IntColumn get createdAtMicros => integer()();
  TextColumn get createdByAppVersion => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text().withLength(min: 1, max: 64)();
  TextColumn get value => text()(); // JSON-encoded scalar
  IntColumn get updatedAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {key};
}

// ---------------------------------------------------------------- commands

/// Audit + idempotency for the single write path. v1 rows are inserted with a
/// terminal status ('applied'|'rejected') in the same transaction as their
/// effects; 'staged' exists for Gate 4. Triggers (§4.1) forbid DELETE and any
/// UPDATE other than staged -> applied|rejected touching only
/// status/applied_at/rejected_reason.
class Commands extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get origin => text().check(origin.isIn(['form', 'agent']))();
  TextColumn get kind => text().withLength(min: 1, max: 64)();
  TextColumn get payloadJson => text()();
  TextColumn get status =>
      text().check(status.isIn(['staged', 'applied', 'rejected']))();
  IntColumn get createdAtMicros => integer()();
  IntColumn get appliedAtMicros => integer().nullable()();
  TextColumn get rejectedReason => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------- items

/// Hard cap for `items.serves_per_unit_micros`: 10 000 people served by one
/// unit. Anything larger is a typo, not a product ("1 urn serves 200" is the
/// realistic top end). Mirrored by [maxServesPerUnitMicros] in the validator.
const int servesPerUnitCapMicros = 10000000000;

/// An item is a NAME + HOW MANY YOU HAVE (derived from the ledger) +
/// optionally HOW MANY PEOPLE ONE SERVES. `unit` and `pack_size_micros`
/// survive from v1 but are no longer part of the product surface: every item
/// created from v2 on is 'each' with a pack size of one unit, which means
/// "round to whole things" — exactly what counted goods want, and exactly
/// what the frozen engine's packSize parameter needs. Goods bought by weight
/// live in the name ("Mince (500g packs)") and are counted as whole packs;
/// the app never does weight arithmetic.
///
/// Unit is locked after the item's first movement (validator-enforced;
/// escape hatch: archive+recreate).
class Items extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get unit =>
      text().check(unit.isIn(['each', 'g', 'kg', 'ml', 'L']))();

  /// Purchase/load rounding increment in micros of [unit]. Engine packSize.
  IntColumn get packSizeMicros =>
      integer().check(packSizeMicros.isBiggerThanValue(0))();

  /// v2. How many people ONE unit of this item serves ("1 pizza serves 4"),
  /// in micros of people. NULL when the owner never said — the honest
  /// default, and the reason the column is nullable. It is a PLANNING
  /// assumption and never a forecasting label: the §4.3 label query cannot
  /// reach it.
  IntColumn get servesPerUnitMicros => integer().nullable().check(
    servesPerUnitMicros.isBetweenValues(1, servesPerUnitCapMicros),
  )();
  TextColumn get category => text().nullable().withLength(min: 1, max: 60)();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get archivedAtMicros => integer().nullable()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {id};
}
// Live-name uniqueness is the partial index uidx_items_name_live (§4.1):
// UNIQUE ON items(lower(name)) WHERE archived_at_micros IS NULL.

// ---------------------------------------------------------------- events

/// Mutable until closed. planned_exposure is a PREDICTION and never a label;
/// confirmed exposure lives on the append-only closeout header.
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
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK (scheduled_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')",
    "CHECK (status != 'closed' OR closed_at_micros IS NOT NULL)",
    'CHECK (ends_at_micros IS NULL OR starts_at_micros IS NULL '
        'OR ends_at_micros >= starts_at_micros)',
  ];
}

/// Planned items per event. Mutable until the event closes (validator rule).
class EventItems extends Table {
  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer().check(position.isBiggerOrEqualValue(0))();
  @override
  Set<Column> get primaryKey => {eventId, itemId};
}

// ---------------------------------------------------------------- ledger

/// APPEND-ONLY. UPDATE/DELETE blocked by triggers. On-hand = SUM(delta_micros);
/// negative sums are legal and surfaced. Kinds and sign (CHECK-enforced):
///   receive  +  purchase arrives     | consume - confirmed event depletion, written ONLY by
///   waste    -  spoilage/damage      |           closeout application, event_id required
///   adjust   +/- count reconciliation| reversal +/- exact negation of a prior row
class InventoryMovements extends Table {
  TextColumn get id =>
      text().withLength(min: 26, max: 26)(); // ULID = time-sorted
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.restrict)();
  TextColumn get kind => text().check(
    kind.isIn(['receive', 'consume', 'waste', 'adjust', 'reversal']),
  )();
  IntColumn get deltaMicros => integer()(); // signed micros; never zero
  TextColumn get eventId =>
      text().nullable().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get reversesMovementId => text().nullable().references(
    InventoryMovements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get sourceCommandId =>
      text().references(Commands, #id, onDelete: KeyAction.restrict)();
  IntColumn get occurredAtMicros => integer()(); // business time (backdatable)
  IntColumn get recordedAtMicros => integer()(); // applier clock, monotonic
  TextColumn get note => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
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

/// APPEND-ONLY confirmed-outcome HEADER: one row per (event, revision).
/// Current outcome = MAX(revision). Confirmed exposure here is the ONLY
/// exposure ever used as a forecasting label.
class EventCloseouts extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  IntColumn get revision => integer().check(revision.isBiggerThanValue(0))();
  TextColumn get supersedesCloseoutId => text().nullable().references(
    EventCloseouts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get confirmedExposure =>
      integer().check(confirmedExposure.isBetweenValues(1, 1000000))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get sourceCommandId =>
      text().references(Commands, #id, onDelete: KeyAction.restrict)();
  IntColumn get confirmedAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    'UNIQUE (event_id, revision)',
    'UNIQUE (supersedes_closeout_id)',
    'CHECK ((revision = 1) = (supersedes_closeout_id IS NULL))',
  ];
}

/// APPEND-ONLY closeout LINES. Worksheet fields loaded/returned/waste are
/// optional; when all three are present the arithmetic must reconcile:
/// depletion = loaded - returned - waste. Depletion EXCLUDES waste: it is the
/// demand label ("what sells"), not "what left the van".
class CloseoutLines extends Table {
  TextColumn get closeoutId =>
      text().references(EventCloseouts, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get loadedMicros =>
      integer().nullable().check(loadedMicros.isBiggerOrEqualValue(0))();
  IntColumn get returnedMicros =>
      integer().nullable().check(returnedMicros.isBiggerOrEqualValue(0))();
  IntColumn get wasteMicros =>
      integer().nullable().check(wasteMicros.isBiggerOrEqualValue(0))();

  /// The confirmed demand label. Envelope cap 1e12 micros (frozen engine).
  IntColumn get depletionMicros =>
      integer().check(depletionMicros.isBetweenValues(0, 1000000000000))();
  BoolColumn get stockout => boolean().withDefault(const Constant(false))();
  BoolColumn get approximate => boolean().withDefault(const Constant(false))();

  /// Ledger rows written when this revision was applied (evidence links).
  TextColumn get consumptionMovementId => text().nullable().references(
    InventoryMovements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get wasteMovementId => text().nullable().references(
    InventoryMovements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @override
  Set<Column> get primaryKey => {closeoutId, itemId};
  @override
  List<String> get customConstraints => [
    'CHECK (loaded_micros IS NULL OR returned_micros IS NULL OR waste_micros IS NULL '
        'OR depletion_micros = loaded_micros - returned_micros - waste_micros)',
  ];
}

/// Upsert-mutable autosave for the closeout form. A draft is not a record;
/// append-only does not apply. Row is deleted on confirm.
class CloseoutDrafts extends Table {
  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get payloadJson => text()();
  IntColumn get updatedAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {eventId};
}

// ---------------------------------------------------------------- recipes

/// Identity + output binding. At most one live recipe per output item (partial
/// unique index uidx_recipes_output_live, §4.1).
class Recipes extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get outputItemId =>
      text().references(Items, #id, onDelete: KeyAction.restrict)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get archivedAtMicros => integer().nullable()();
  IntColumn get createdAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

/// APPEND-ONLY. Editing a recipe inserts revision+1; current = MAX(revision).
/// source_kind 'ocr' is allowed in the CHECK now so Gate 5 needs no migration.
class RecipeRevisions extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.restrict)();
  IntColumn get revision => integer().check(revision.isBiggerThanValue(0))();
  IntColumn get yieldMicros =>
      integer().check(yieldMicros.isBiggerThanValue(0))();
  TextColumn get yieldLabel => text().nullable()(); // e.g. "12 tacos"
  TextColumn get sourceKind => text().check(sourceKind.isIn(['form', 'ocr']))();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => ['UNIQUE (recipe_id, revision)'];
}

/// APPEND-ONLY (immutable with its revision). Amount is micros of the
/// ingredient's own base unit per batch. Expansion math is Gate 5.
class RecipeLines extends Table {
  TextColumn get revisionId =>
      text().references(RecipeRevisions, #id, onDelete: KeyAction.restrict)();
  IntColumn get lineIndex =>
      integer().check(lineIndex.isBiggerOrEqualValue(0))();
  TextColumn get ingredientItemId =>
      text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantityPerBatchMicros =>
      integer().check(quantityPerBatchMicros.isBiggerThanValue(0))();
  @override
  Set<Column> get primaryKey => {revisionId, lineIndex};
  @override
  List<String> get customConstraints => [
    'UNIQUE (revision_id, ingredient_item_id)',
  ];
}

// ---------------------------------------------------------------- forecasts

/// APPEND-ONLY. One snapshot per engine run over a WHOLE EVENT; per-item rows
/// in forecast_lines; evidence value-copied per line. Latest per event =
/// MAX(id). Regenerating appends; nothing is rewritten. Actuals are NEVER
/// stored here — they are derived by join (§6.6).
class ForecastSnapshots extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get eventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  TextColumn get method => text()(); // 'direct_median'
  IntColumn get methodVersion =>
      integer().check(methodVersion.isBiggerThanValue(0))(); // 1
  TextColumn get policy =>
      text().check(policy.isIn(['lean', 'balanced', 'cautious']))();
  IntColumn get upcomingExposure =>
      integer().check(upcomingExposure.isBetweenValues(1, 1000000))();

  /// The last-N history window in force when this snapshot was generated.
  IntColumn get historyWindow =>
      integer().check(historyWindow.isBiggerThanValue(0))();

  /// SHA-256 lowercase hex over the canonical input encoding (§6.6).
  TextColumn get inputsHash => text().withLength(min: 64, max: 64)();

  /// JSON, e.g. {"reserve_percent":10,"history_window":12,
  /// "rate_normalization":"per_exposure_median","exposure_label":"attendance"}.
  TextColumn get assumptionsJson => text().withDefault(const Constant('{}'))();
  TextColumn get sourceCommandId =>
      text().references(Commands, #id, onDelete: KeyAction.restrict)();
  IntColumn get createdAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

/// APPEND-ONLY per-item snapshot lines: frozen inputs + engine outputs.
/// on_hand_micros stores the SIGNED derived on-hand at generation time; the
/// engine consumed max(0, on_hand_micros). Warnings are the frozen engine's
/// strings verbatim (the DB is encrypted; content-free binds diagnostics
/// only).
class ForecastLines extends Table {
  TextColumn get snapshotId =>
      text().references(ForecastSnapshots, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get packSizeMicros =>
      integer().check(packSizeMicros.isBiggerThanValue(0))();
  IntColumn get onHandMicros => integer()(); // signed
  IntColumn get confirmedInboundMicros => integer()
      .withDefault(const Constant(0))
      .check(confirmedInboundMicros.isBiggerOrEqualValue(0))();
  IntColumn get expectedUseMicros =>
      integer().nullable().check(expectedUseMicros.isBiggerOrEqualValue(0))();
  IntColumn get plannedMicros =>
      integer().nullable().check(plannedMicros.isBiggerOrEqualValue(0))();
  IntColumn get loadMicros =>
      integer().nullable().check(loadMicros.isBiggerOrEqualValue(0))();
  IntColumn get acquireMicros =>
      integer().nullable().check(acquireMicros.isBiggerOrEqualValue(0))();
  TextColumn get evidenceGrade => text().check(
    evidenceGrade.isIn(['insufficient_data', 'single_event', 'observed_range']),
  )();
  TextColumn get warningsJson => text().withDefault(const Constant('[]'))();

  // ------------------------------------------------- v2 serves baseline
  // A first-ever event has no confirmed outcomes, so the frozen engine
  // returns insufficient_data and the owner gets no number at all. When the
  // item says "1 serves N" the application layer computes a BASELINE plan
  // (attendance ÷ serves, then the same reserve percent and pack rounding)
  // and stores it here.
  //
  // These columns are deliberately separate from the engine outputs above:
  // expected_use_micros stays NULL and evidence_grade stays
  // 'insufficient_data' because the confirmed evidence really is zero — the
  // §4 CHECK keeps that pairing honest and no append-only table had to be
  // rewritten to add this. All five are written together or all NULL.
  // Nothing here is ever a label.
  IntColumn get baselineServesPerUnitMicros => integer().nullable().check(
    baselineServesPerUnitMicros.isBetweenValues(1, servesPerUnitCapMicros),
  )();
  IntColumn get baselineExpectedUseMicros => integer()
      .nullable()
      .check(baselineExpectedUseMicros.isBiggerOrEqualValue(0))();
  IntColumn get baselinePlannedMicros =>
      integer().nullable().check(baselinePlannedMicros.isBiggerOrEqualValue(0))();
  IntColumn get baselineLoadMicros =>
      integer().nullable().check(baselineLoadMicros.isBiggerOrEqualValue(0))();
  IntColumn get baselineAcquireMicros => integer()
      .nullable()
      .check(baselineAcquireMicros.isBiggerOrEqualValue(0))();

  @override
  Set<Column> get primaryKey => {snapshotId, itemId};
  @override
  List<String> get customConstraints => [
    "CHECK ((evidence_grade = 'insufficient_data') = (expected_use_micros IS NULL))",
  ];
}

/// APPEND-ONLY value-copies of the exact observations the engine saw, frozen
/// at generation time. Later closeout revisions never rewrite forecast
/// history.
class ForecastEvidence extends Table {
  TextColumn get snapshotId =>
      text().references(ForecastSnapshots, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer().check(position.isBiggerOrEqualValue(0))();
  TextColumn get closeoutId =>
      text().references(EventCloseouts, #id, onDelete: KeyAction.restrict)();
  TextColumn get sourceEventId =>
      text().references(Events, #id, onDelete: KeyAction.restrict)();
  IntColumn get exposure =>
      integer().check(exposure.isBetweenValues(1, 1000000))();
  IntColumn get depletionMicros =>
      integer().check(depletionMicros.isBetweenValues(0, 1000000000000))();
  BoolColumn get stockout => boolean()();
  BoolColumn get approximate => boolean()();
  @override
  Set<Column> get primaryKey => {snapshotId, itemId, position};
}

/// APPEND-ONLY override log per (snapshot, item). Latest row (MAX(id)) wins
/// for display. override_load_micros NULL means "revert to the engine value"
/// (implements clear-override). Reason mandatory, >= 3 chars. Overrides are
/// plans, never labels: no history query reads this.
class ForecastOverrides extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get snapshotId =>
      text().references(ForecastSnapshots, #id, onDelete: KeyAction.restrict)();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get overrideLoadMicros =>
      integer().nullable().check(overrideLoadMicros.isBiggerOrEqualValue(0))();
  TextColumn get reason => text().withLength(min: 3, max: 500)();
  IntColumn get createdAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {id};
}
