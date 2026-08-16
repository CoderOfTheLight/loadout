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

// ---------------------------------------------------------------- folders

/// Hard cap for `items.per_event_baseline_micros` and
/// `forecast_lines.baseline_per_event_micros`: the 1e12-micros closeout
/// depletion envelope. "How many do you usually bring" can never exceed what
/// a closeout could ever confirm.
const int perEventBaselineCapMicros = 1000000000000;

/// Hard cap for each part of the flipped "N per person" ratio
/// (`items.per_person_numerator/denominator`): 10 000 — the same order as
/// [servesPerUnitCapMicros], and far beyond any real hand-out rate.
const int perPersonRatioPartCap = 10000;

/// v3. One folder per item, chosen from a short managed list the owner
/// renames, adds to, and reorders. NO nesting — one level, in her order.
/// `demand_basis` answers "does how much you bring depend on how many people
/// come?" for the whole folder ('per_person' | 'per_event'); items may
/// override it. `always_planned` folders have their live items pre-added to
/// every new event. Archiving moves the folder's items to Unfiled (NULL
/// folder_id) and never deletes anything. Folders are master data like
/// items: plain in-place updates through the command path, not append-only.
class Folders extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get position => integer().check(position.isBiggerOrEqualValue(0))();
  TextColumn get demandBasis =>
      text().check(demandBasis.isIn(['per_person', 'per_event']))();
  BoolColumn get alwaysPlanned =>
      boolean().withDefault(const Constant(false))();

  // --------------------------------------------------- v4 appearance
  // Both nullable and CHECKed at column level only, so the v4 ALTER TABLE
  // ADD COLUMN carries the constraint and v3 rows ride it byte for byte.
  // NULL = never chose: effective hue is assigned by position order and the
  // effective icon by the starter-name table (core/folder_appearance.dart).

  /// v4. One of the eight named hues (spec §3's bounded palette); the CHECK
  /// list mirrors [FolderHue] exactly.
  TextColumn get hueName => text().nullable().check(
    hueName.isIn([
      'fern',
      'lake',
      'plum',
      'berry',
      'clay',
      'honey',
      'olive',
      'stone',
    ]),
  )();

  /// v4. A curated Material glyph name; membership in the ~32-name grid is
  /// validator-enforced (the grid may grow without a migration), SQL only
  /// bounds the length.
  TextColumn get iconName =>
      text().nullable().check(iconName.length.isBetweenValues(1, 40))();
  IntColumn get archivedAtMicros => integer().nullable()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {id};
}
// Live-name uniqueness is the partial index uidx_folders_name_live (v3):
// UNIQUE ON folders(lower(name)) WHERE archived_at_micros IS NULL.

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

  // --------------------------------------------------------- v3 folders
  // Every column below is nullable and CHECKed at column level only, so the
  // v3 ALTER TABLE ADD COLUMN carries the constraint and existing rows
  // survive byte for byte.

  /// v3. The folder this item lives in; NULL = "Unfiled" (shown last, never
  /// hidden). A rename can never orphan an item: this is an FK, not text.
  TextColumn get folderId => text().nullable().references(
    Folders,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// v3. Per-item override of the folder's demand basis; NULL inherits the
  /// folder's answer (and per_person when unfiled). Resolved ONLY by
  /// `effectiveDemandBasis` — no screen re-derives it.
  TextColumn get demandBasis =>
      text().nullable().check(demandBasis.isIn(['per_person', 'per_event']))();

  /// v3. "How many do you usually bring?" — the per-event cold-start
  /// baseline, in micros of units. A planning assumption like
  /// serves_per_unit_micros: never a forecasting label, never history.
  IntColumn get perEventBaselineMicros => integer().nullable().check(
    perEventBaselineMicros.isBetweenValues(1, perEventBaselineCapMicros),
  )();

  /// v3. The flipped "N per person" cold-start ratio ("3 napkins per
  /// person" = 3/1; "1 urn per 200 people" = 1/200), stored as an exact
  /// integer pair so 200 people × 3/person is exactly 600 — never the lossy
  /// micros reciprocal. Both parts set together or both NULL
  /// (validator-enforced; the pairing CHECK cannot ride an ALTER TABLE).
  /// Mutually exclusive with serves_per_unit_micros (validator-enforced).
  IntColumn get perPersonNumerator => integer().nullable().check(
    perPersonNumerator.isBetweenValues(1, perPersonRatioPartCap),
  )();
  IntColumn get perPersonDenominator => integer().nullable().check(
    perPersonDenominator.isBetweenValues(1, perPersonRatioPartCap),
  )();

  // --------------------------------------------------------- v5 unit label
  /// v5. Optional DISPLAY label for the amount ("tsp", "cup", "lbs",
  /// "package") — free text, suggestion-chip assisted on the form. The app
  /// NEVER converts between units and never does unit arithmetic; forecasting
  /// works on the bare amounts exactly as before. NULL = counted things, no
  /// label shown. Nullable + column-level CHECK only, so the v5 ALTER TABLE
  /// ADD COLUMN carries the constraint and v4 rows ride it byte for byte.
  TextColumn get unitLabel =>
      text().nullable().check(unitLabel.length.isBetweenValues(1, 24))();

  // ----------------------------------------------------------- v6 barcode
  /// v6. The item's barcode: the RAW payload string exactly as the scan
  /// detector delivers it. The app never interprets it — no symbology
  /// rules, no check digits, no normalization; payloads are stored and
  /// compared verbatim. NULL = never scanned, the honest default for every
  /// pre-v6 row. Nullable + column-level CHECK only, so the v6 ALTER TABLE
  /// ADD COLUMN carries the constraint and v5 rows ride it byte for byte.
  TextColumn get barcode =>
      text().nullable().check(barcode.length.isBetweenValues(1, 64))();

  IntColumn get archivedAtMicros => integer().nullable()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();
  @override
  Set<Column> get primaryKey => {id};
}
// Live-name uniqueness is the partial index uidx_items_name_live (§4.1):
// UNIQUE ON items(lower(name)) WHERE archived_at_micros IS NULL.
// Live-barcode uniqueness is the partial index uidx_items_barcode_live (v6):
// UNIQUE ON items(barcode) WHERE archived_at_micros IS NULL AND barcode IS
// NOT NULL — archiving an item frees its barcode exactly as it frees names.

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
/// unique index uidx_recipes_output_live, §4.1; NULLs never collide there, so
/// any number of not-yet-added recipes coexist).
///
/// v5 (recipe decoupling): `output_item_id` is NULLABLE — NULL means "this
/// recipe has not been added to the item list yet". `AddRecipeToItems` creates
/// the output item and binds it here in one transaction. The column was NOT
/// NULL in v1; recipes is mutable master data (NOT append-only — it has no
/// forbid-triggers and is absent from [appendOnlyTables]), so the v5 migration
/// widens it with SQLite's documented copy-rewrite (drift `TableMigration`),
/// preserving every row byte for byte. The design doc's "never rewrite" rule
/// protects append-only history tables; this is not one.
class Recipes extends Table {
  TextColumn get id => text().withLength(min: 26, max: 26)();
  TextColumn get outputItemId =>
      text().nullable().references(Items, #id, onDelete: KeyAction.restrict)();
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
///
/// FROZEN AT v5 (recipe decoupling): `ingredient_item_id` is NOT NULL here
/// and this table is trigger-enforced append-only, so it could not be widened
/// or backfilled without rewriting history. [RecipeLinesV2] supersedes it:
/// the v5 migration COPIES every row into the v2 table (an INSERT — legal on
/// an append-only table) with `ingredient_name` backfilled from the linked
/// item, and this table keeps its rows byte for byte as the historical
/// record. Nothing reads or writes it after v5.
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

/// v5. The decoupled recipe line: every line has its OWN name (and optional
/// display-only unit label); the catalog link is optional. A recipe no longer
/// pulls ingredients from the item list — a line may point at a catalog item
/// (rendered as that item) or stand alone as plain text.
///
/// Immutability contract (trigger-enforced, [schemaV5RecipeLinesV2Triggers]):
/// DELETE is forbidden and every column except `ingredient_item_id` is
/// frozen with its revision — the recipe's CONTENT is append-only exactly as
/// before, but the LINK is mutable metadata (LinkRecipeLineToItem /
/// UnlinkRecipeLine), the same limited-update pattern the `commands` table
/// uses for its status transition. `ingredient_name` is ALWAYS set — the
/// applier snapshots the linked item's name when a draft line carries none —
/// so unlinking can never leave a line with no identity.
@DataClassName('RecipeLineV2')
class RecipeLinesV2 extends Table {
  @override
  String get tableName => 'recipe_lines_v2';

  TextColumn get revisionId =>
      text().references(RecipeRevisions, #id, onDelete: KeyAction.restrict)();
  IntColumn get lineIndex =>
      integer().check(lineIndex.isBiggerOrEqualValue(0))();

  /// The line's own name — the pasted/typed text, or a snapshot of the
  /// linked item's name at write time. Display prefers the live item name on
  /// linked lines; this is what remains when a line is unlinked.
  TextColumn get ingredientName =>
      text().check(ingredientName.length.isBetweenValues(1, 120))();

  /// Display label for the amount ("tsp", "cup", "lbs"); never converted,
  /// never computed with. Same 24-char bound as `items.unit_label`.
  TextColumn get unitLabel =>
      text().nullable().check(unitLabel.length.isBetweenValues(1, 24))();

  /// Optional catalog link; NULL = free line. The ONLY mutable column.
  TextColumn get ingredientItemId =>
      text().nullable().references(Items, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantityPerBatchMicros =>
      integer().check(quantityPerBatchMicros.isBiggerThanValue(0))();
  @override
  Set<Column> get primaryKey => {revisionId, lineIndex};
  @override
  List<String> get customConstraints => [
    // NULLs are distinct in SQLite UNIQUE: any number of free lines, but an
    // item may be linked at most once per revision.
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
      // Stored, not assumed: v1 snapshots predate the sell-out correction and
      // stay readable exactly as they were computed (§6.6).
      integer().check(methodVersion.isBiggerThanValue(0))();
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
  IntColumn get baselineExpectedUseMicros => integer().nullable().check(
    baselineExpectedUseMicros.isBiggerOrEqualValue(0),
  )();
  IntColumn get baselinePlannedMicros => integer().nullable().check(
    baselinePlannedMicros.isBiggerOrEqualValue(0),
  )();
  IntColumn get baselineLoadMicros =>
      integer().nullable().check(baselineLoadMicros.isBiggerOrEqualValue(0))();
  IntColumn get baselineAcquireMicros => integer().nullable().check(
    baselineAcquireMicros.isBiggerOrEqualValue(0),
  )();

  // ------------------------------------------------- v3 demand basis
  // Which question this line's numbers answered, recorded so a stored
  // forecast can still explain itself ("2 per event" vs "0.4 per person").
  // NULL only on rows stored before v3 — all of which were per-person.
  TextColumn get demandBasis =>
      text().nullable().check(demandBasis.isIn(['per_person', 'per_event']))();

  /// v3. The per-event cold start: the item's "how many do you usually
  /// bring" as it was at generation time. Shares the baseline_* output
  /// columns above; exactly one of baseline_serves_per_unit_micros, the
  /// baseline_per_person pair, or this may accompany them
  /// (validator-enforced — the pairing CHECKs cannot ride an ALTER TABLE).
  IntColumn get baselinePerEventMicros => integer().nullable().check(
    baselinePerEventMicros.isBetweenValues(1, perEventBaselineCapMicros),
  )();

  /// v3. The flipped "N per person" ratio that produced a per-person
  /// baseline, exact integer pair, both set together (validator-enforced).
  IntColumn get baselinePerPersonNumerator => integer().nullable().check(
    baselinePerPersonNumerator.isBetweenValues(1, perPersonRatioPartCap),
  )();
  IntColumn get baselinePerPersonDenominator => integer().nullable().check(
    baselinePerPersonDenominator.isBetweenValues(1, perPersonRatioPartCap),
  )();

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
