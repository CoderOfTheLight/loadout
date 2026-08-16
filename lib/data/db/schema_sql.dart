const schemaV1Indices = <String>[
  // HOT: on-hand = SUM(delta_micros); covering index answers per-item and
  // GROUP BY sums entirely from the index.
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

/// The `folders` table exactly as schema v3 shipped it. The `from < 3`
/// onUpgrade block runs THIS, not `Migrator.createTable`, because the
/// migrator always builds the CURRENT Dart shape — which grew appearance
/// columns in v4 — and a stepwise migration must land each version's exact
/// schema (the SchemaVerifier tests stop at intermediate versions). The v4
/// block then ALTERs the two columns on, identically for a phone climbing
/// v2 → v4 and one that was already on v3.
const schemaV3FoldersCreate =
    'CREATE TABLE IF NOT EXISTS "folders" ('
    '"id" TEXT NOT NULL, '
    '"name" TEXT NOT NULL, '
    '"position" INTEGER NOT NULL CHECK("position" >= 0), '
    '"demand_basis" TEXT NOT NULL '
    "CHECK(\"demand_basis\" IN ('per_person', 'per_event')), "
    '"always_planned" INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("always_planned" IN (0, 1)), '
    '"archived_at_micros" INTEGER NULL, '
    '"created_at_micros" INTEGER NOT NULL, '
    '"updated_at_micros" INTEGER NOT NULL, '
    'PRIMARY KEY ("id"))';

/// v3 (folders): run by onCreate on fresh databases and by the `from < 3`
/// onUpgrade block on migrated ones — the same statements either way, so a
/// migrated phone ends up with exactly the fresh-install indices.
const schemaV3Indices = <String>[
  'CREATE UNIQUE INDEX uidx_folders_name_live ON folders (lower(name)) '
      'WHERE archived_at_micros IS NULL',
  'CREATE INDEX idx_items_folder ON items (folder_id) '
      'WHERE folder_id IS NOT NULL',
];

/// Belt-and-braces append-only enforcement (ADR 0001: triggers forbid, never
/// compute). The Dart layer never issues UPDATE/DELETE on these tables.
/// `folders` is deliberately absent: folders are master data like items —
/// renameable, reorderable, archivable in place through the command path.
const appendOnlyTables = [
  'inventory_movements',
  'event_closeouts',
  'closeout_lines',
  'recipe_revisions',
  'recipe_lines',
  'forecast_snapshots',
  'forecast_lines',
  'forecast_evidence',
  'forecast_overrides',
];

/// v5 (recipe decoupling): `recipe_lines_v2` is append-only in CONTENT but
/// its catalog link is mutable metadata — DELETE forbidden, UPDATE allowed
/// ONLY when nothing but `ingredient_item_id` changes (the `commands` table's
/// limited-update pattern). `IS NOT` makes the nullable comparisons
/// null-safe. Run by onCreate on fresh databases and by the `from < 5`
/// onUpgrade block on migrated ones.
const schemaV5RecipeLinesV2Triggers = <String>[
  'CREATE TRIGGER trg_recipe_lines_v2_no_delete '
      'BEFORE DELETE ON recipe_lines_v2 '
      "BEGIN SELECT RAISE(ABORT, 'recipe_lines_v2 is append-only'); END",
  'CREATE TRIGGER trg_recipe_lines_v2_limited_update '
      'BEFORE UPDATE ON recipe_lines_v2 '
      'WHEN NEW.revision_id != OLD.revision_id '
      'OR NEW.line_index != OLD.line_index '
      'OR NEW.ingredient_name != OLD.ingredient_name '
      'OR NEW.unit_label IS NOT OLD.unit_label '
      'OR NEW.quantity_per_batch_micros != OLD.quantity_per_batch_micros '
      "BEGIN SELECT RAISE(ABORT, "
      "'recipe_lines_v2: only the item link may change'); END",
];

/// v5: copies every legacy `recipe_lines` row into `recipe_lines_v2`,
/// backfilling `ingredient_name` from the linked item's name (the join can
/// never miss: `ingredient_item_id` is NOT NULL and FK-enforced in v1..v4).
/// An INSERT is legal on an append-only table; the legacy table itself is
/// left byte for byte and simply stops being read.
const schemaV5RecipeLinesBackfill =
    'INSERT INTO recipe_lines_v2 '
    '(revision_id, line_index, ingredient_name, unit_label, '
    'ingredient_item_id, quantity_per_batch_micros) '
    'SELECT rl.revision_id, rl.line_index, i.name, NULL, '
    'rl.ingredient_item_id, rl.quantity_per_batch_micros '
    'FROM recipe_lines rl JOIN items i ON i.id = rl.ingredient_item_id';

/// v5: `uidx_recipes_output_live` recreated verbatim after the `recipes`
/// copy-rewrite (dropping a table drops its indexes). On the now-nullable
/// column, NULLs never collide — "not added to items yet" rows are unlimited;
/// one LIVE recipe per output item stays enforced.
const schemaV5RecipesOutputIndex =
    'CREATE UNIQUE INDEX uidx_recipes_output_live ON recipes (output_item_id) '
    'WHERE archived_at_micros IS NULL';

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
