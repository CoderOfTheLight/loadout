import 'package:drift/native.dart';
import 'package:loadout/data/db/app_database.dart';

/// Fresh in-memory SQLCipher-backed database (design §11.2 Tier 1).
AppDatabase openTestDb() => AppDatabase.forTesting(NativeDatabase.memory());

/// Deterministic 26-char id: [seed] uppercased, right-padded with '0'.
/// Lexicographic order of equal-length seeds is preserved.
String tid(String seed) {
  final s = seed.toUpperCase();
  assert(s.length <= 26, 'seed too long: $seed');
  return s.padRight(26, '0');
}

Future<void> insertCommand(
  AppDatabase db,
  String id, {
  String origin = 'form',
  String kind = 'Test',
  String payloadJson = '{}',
  String status = 'applied',
  int createdAtMicros = 1,
}) => db.customStatement(
  'INSERT INTO commands '
  '(id, origin, kind, payload_json, status, created_at_micros) '
  'VALUES (?, ?, ?, ?, ?, ?)',
  [id, origin, kind, payloadJson, status, createdAtMicros],
);

Future<void> insertItem(
  AppDatabase db,
  String id, {
  String? name,
  String unit = 'each',
  int packSizeMicros = 1000000,
  int? servesPerUnitMicros,
  int? archivedAtMicros,
}) => db.customStatement(
  'INSERT INTO items '
  '(id, name, unit, pack_size_micros, serves_per_unit_micros, '
  'archived_at_micros, created_at_micros, updated_at_micros) '
  'VALUES (?, ?, ?, ?, ?, ?, 1, 1)',
  [
    id,
    name ?? 'Item $id',
    unit,
    packSizeMicros,
    servesPerUnitMicros,
    archivedAtMicros,
  ],
);

Future<void> insertEvent(
  AppDatabase db,
  String id, {
  String? name,
  String scheduledDate = '2026-08-01',
  String status = 'planned',
  int? closedAtMicros,
  int? plannedExposure,
}) => db.customStatement(
  'INSERT INTO events '
  '(id, name, scheduled_date, status, planned_exposure, closed_at_micros, '
  'created_at_micros, updated_at_micros) '
  'VALUES (?, ?, ?, ?, ?, ?, 1, 1)',
  [
    id,
    name ?? 'Event $id',
    scheduledDate,
    status,
    plannedExposure,
    closedAtMicros,
  ],
);

Future<void> insertMovement(
  AppDatabase db,
  String id, {
  required String itemId,
  required String kind,
  required int deltaMicros,
  required String sourceCommandId,
  String? eventId,
  String? reversesMovementId,
  int occurredAtMicros = 1,
  int recordedAtMicros = 1,
  String note = '',
}) => db.customStatement(
  'INSERT INTO inventory_movements '
  '(id, item_id, kind, delta_micros, event_id, reverses_movement_id, '
  'source_command_id, occurred_at_micros, recorded_at_micros, note) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    id,
    itemId,
    kind,
    deltaMicros,
    eventId,
    reversesMovementId,
    sourceCommandId,
    occurredAtMicros,
    recordedAtMicros,
    note,
  ],
);

Future<void> insertCloseout(
  AppDatabase db,
  String id, {
  required String eventId,
  required int revision,
  required int confirmedExposure,
  required String sourceCommandId,
  String? supersedesCloseoutId,
  int confirmedAtMicros = 1,
}) => db.customStatement(
  'INSERT INTO event_closeouts '
  '(id, event_id, revision, supersedes_closeout_id, confirmed_exposure, '
  'source_command_id, confirmed_at_micros) '
  'VALUES (?, ?, ?, ?, ?, ?, ?)',
  [
    id,
    eventId,
    revision,
    supersedesCloseoutId,
    confirmedExposure,
    sourceCommandId,
    confirmedAtMicros,
  ],
);

Future<void> insertCloseoutLine(
  AppDatabase db, {
  required String closeoutId,
  required String itemId,
  required int depletionMicros,
  int? loadedMicros,
  int? returnedMicros,
  int? wasteMicros,
  bool stockout = false,
  bool approximate = false,
}) => db.customStatement(
  'INSERT INTO closeout_lines '
  '(closeout_id, item_id, loaded_micros, returned_micros, waste_micros, '
  'depletion_micros, stockout, approximate) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  [
    closeoutId,
    itemId,
    loadedMicros,
    returnedMicros,
    wasteMicros,
    depletionMicros,
    stockout ? 1 : 0,
    approximate ? 1 : 0,
  ],
);

Future<void> insertRecipe(
  AppDatabase db,
  String id, {
  required String outputItemId,
  String? name,
  int? archivedAtMicros,
}) => db.customStatement(
  'INSERT INTO recipes '
  '(id, output_item_id, name, archived_at_micros, created_at_micros) '
  'VALUES (?, ?, ?, ?, 1)',
  [id, outputItemId, name ?? 'Recipe $id', archivedAtMicros],
);

Future<void> insertRecipeRevision(
  AppDatabase db,
  String id, {
  required String recipeId,
  int revision = 1,
  int yieldMicros = 1000000,
  String sourceKind = 'form',
}) => db.customStatement(
  'INSERT INTO recipe_revisions '
  '(id, recipe_id, revision, yield_micros, source_kind, created_at_micros) '
  'VALUES (?, ?, ?, ?, ?, 1)',
  [id, recipeId, revision, yieldMicros, sourceKind],
);

Future<void> insertRecipeLine(
  AppDatabase db, {
  required String revisionId,
  required String ingredientItemId,
  int lineIndex = 0,
  int quantityPerBatchMicros = 1000000,
}) => db.customStatement(
  'INSERT INTO recipe_lines '
  '(revision_id, line_index, ingredient_item_id, quantity_per_batch_micros) '
  'VALUES (?, ?, ?, ?)',
  [revisionId, lineIndex, ingredientItemId, quantityPerBatchMicros],
);

Future<void> insertSnapshot(
  AppDatabase db,
  String id, {
  required String eventId,
  required String sourceCommandId,
  String policy = 'balanced',
  int upcomingExposure = 100,
  int historyWindow = 12,
}) => db.customStatement(
  'INSERT INTO forecast_snapshots '
  '(id, event_id, method, method_version, policy, upcoming_exposure, '
  'history_window, inputs_hash, source_command_id, created_at_micros) '
  "VALUES (?, ?, 'direct_median', 1, ?, ?, ?, ?, ?, 1)",
  [
    id,
    eventId,
    policy,
    upcomingExposure,
    historyWindow,
    'a' * 64,
    sourceCommandId,
  ],
);

Future<void> insertForecastLine(
  AppDatabase db, {
  required String snapshotId,
  required String itemId,
  int packSizeMicros = 1000000,
  int onHandMicros = 0,
  int? expectedUseMicros,
  String evidenceGrade = 'insufficient_data',
  int? baselineServesPerUnitMicros,
  int? baselineExpectedUseMicros,
  int? baselinePlannedMicros,
  int? baselineLoadMicros,
  int? baselineAcquireMicros,
}) => db.customStatement(
  'INSERT INTO forecast_lines '
  '(snapshot_id, item_id, pack_size_micros, on_hand_micros, '
  'expected_use_micros, evidence_grade, baseline_serves_per_unit_micros, '
  'baseline_expected_use_micros, baseline_planned_micros, '
  'baseline_load_micros, baseline_acquire_micros) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    snapshotId,
    itemId,
    packSizeMicros,
    onHandMicros,
    expectedUseMicros,
    evidenceGrade,
    baselineServesPerUnitMicros,
    baselineExpectedUseMicros,
    baselinePlannedMicros,
    baselineLoadMicros,
    baselineAcquireMicros,
  ],
);

Future<void> insertEvidence(
  AppDatabase db, {
  required String snapshotId,
  required String itemId,
  required String closeoutId,
  required String sourceEventId,
  int position = 0,
  int exposure = 100,
  int depletionMicros = 1000000,
  bool stockout = false,
  bool approximate = false,
}) => db.customStatement(
  'INSERT INTO forecast_evidence '
  '(snapshot_id, item_id, position, closeout_id, source_event_id, '
  'exposure, depletion_micros, stockout, approximate) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    snapshotId,
    itemId,
    position,
    closeoutId,
    sourceEventId,
    exposure,
    depletionMicros,
    stockout ? 1 : 0,
    approximate ? 1 : 0,
  ],
);

Future<void> insertOverride(
  AppDatabase db,
  String id, {
  required String snapshotId,
  required String itemId,
  int? overrideLoadMicros,
  String reason = 'baseline',
}) => db.customStatement(
  'INSERT INTO forecast_overrides '
  '(id, snapshot_id, item_id, override_load_micros, reason, created_at_micros) '
  'VALUES (?, ?, ?, ?, ?, 1)',
  [id, snapshotId, itemId, overrideLoadMicros, reason],
);
