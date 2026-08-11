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

/// Belt-and-braces append-only enforcement (ADR 0001: triggers forbid, never
/// compute). The Dart layer never issues UPDATE/DELETE on these tables.
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
