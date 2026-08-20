# Data model

The schema as it stands at **version 7**. Source of truth is
`lib/data/db/tables.dart` (Dart table definitions), `lib/data/db/schema_sql.dart` (indices and
triggers) and `lib/data/db/app_database.dart` (version, migrations, seed). The frozen per-version
shapes are committed under `drift_schemas/loadout/drift_schema_v1..v7.json` and CI fails if the
dump drifts from the Dart.

This document explains the *shape and the rules*. The original contract — every column, every
CHECK — is [gates-2-3-design.md](gates-2-3-design.md) §4 and §5; where the two disagree, the code
wins and this document says so.

---

## 1. The division that decides everything

Nineteen tables, split into two kinds.

**Append-only history.** Facts about what happened. Once written, a row is frozen: SQL triggers
`RAISE(ABORT)` on any `UPDATE` or `DELETE`. Corrections are *new rows* — a reversal, a superseding
revision — never an edit. Nine tables carry the blanket forbid-triggers
(`appendOnlyTables` in `lib/data/db/schema_sql.dart`):

| Table | What it records |
|---|---|
| `inventory_movements` | Every signed stock change. On-hand is `SUM(delta_micros)`, never a stored column |
| `event_closeouts` | Confirmed-outcome header, one row per (event, revision) |
| `closeout_lines` | Per-item confirmed depletion — the only forecasting labels |
| `recipe_revisions` | A recipe's content at a point in time |
| `recipe_lines` | v1-era recipe lines; frozen at v5. The recipe feature neither reads nor writes it; it survives as the historical record, and only the item-delete blocker check and the pre-v5 backup validator still look at it |
| `forecast_snapshots` | One engine run over one event |
| `forecast_lines` | Per-item frozen inputs + engine outputs |
| `forecast_evidence` | Value-copies of exactly the observations the engine consumed |
| `forecast_overrides` | The override log; latest row per (snapshot, item) wins for display |

**Mutable master data.** What things *are* now, not what happened. Plain in-place updates through
the command path, no revision log: `workspace_meta`, `settings`, `folders`, `items`, `events`,
`event_items` (plan rows, mutable until the event closes), `closeout_drafts` (an upsert-mutable
autosave; a draft is not a record, and the applier deletes the row on confirm), and `recipes`
(identity and output binding only — the *content* lives in the append-only revisions).

Two tables sit deliberately in between, with **limited-update** triggers rather than blanket
forbids:

- **`commands`** — `DELETE` forbidden; `UPDATE` permitted only for `staged` → `applied|rejected`
  and only on `status`/`applied_at`/`rejected_reason`. v1 never stages anything; the transition
  exists for the Gate 4 agent path.
- **`recipe_lines_v2`** (v5) — `DELETE` forbidden; `UPDATE` permitted only when nothing but
  `ingredient_item_id` changes. The recipe's *content* is append-only exactly as before, but the
  catalog *link* is mutable metadata (`LinkRecipeLineToItem` / `UnlinkRecipeLine`). Every line
  always carries its own `ingredient_name`, so unlinking can never leave a line with no identity.

`folders` is deliberately absent from the append-only set: folders are master data like items —
renameable, reorderable, archivable in place.

### Archiving, not deleting

Nothing user-facing deletes history. `items`, `folders` and `recipes` carry
`archived_at_micros`, and live-uniqueness is enforced by *partial* indices so archiving frees a
name for reuse:

- `uidx_items_name_live` — `UNIQUE(lower(name)) WHERE archived_at_micros IS NULL`
- `uidx_items_barcode_live` (v6) — `UNIQUE(barcode) WHERE archived_at_micros IS NULL AND barcode IS NOT NULL`
- `uidx_folders_name_live` (v3), `uidx_recipes_output_live` (at most one live recipe per output item)

There *are* `DeleteItem` and `DeleteAllItems` commands, and they are more subtle than their names:
`DriftCommandApplier._deleteOrArchiveItem` first clears the item's **mutable** references
(recipe-line links, the recipe output binding, plan rows on not-yet-closed events), then checks
whether any **history** row still points at it — a movement, a closeout line, a frozen v1 recipe
line, a forecast line/evidence/override, or a closed-event plan row. No history ⇒ a genuine hard
delete. Any history ⇒ the item is archived instead. History is never deleted to make a delete
succeed.

### Foreign keys

Every reference between tables is a real FK with `onDelete: restrict`, and `PRAGMA foreign_keys`
is turned `ON` in `beforeOpen` and in the connection `setup` (`lib/infrastructure/db/open_database.dart`).
A rename can therefore never orphan an item; a folder rename cannot strand its contents. Notable
self-references: `inventory_movements.reverses_movement_id` (with `UNIQUE`, so a movement is
reversible at most once) and `event_closeouts.supersedes_closeout_id` (also `UNIQUE`, plus
`CHECK ((revision = 1) = (supersedes_closeout_id IS NULL))`).

### CHECKs: SQL enforces shape, Dart enforces semantics

SQL owns enums, signs, ranges and uniqueness — movement kinds and their required signs, exposure
in `1..1 000 000`, depletion in `0..1e12` micros, prices in `1..100 000 000` cents, the closeout
worksheet identity `depletion = loaded − returned − waste` whenever all three are present.
`CommandValidator` mirrors the same caps in Dart (`maxExposure`, `maxDepletionMicros`,
`maxUnitPriceCents`, …) so the owner gets a sentence instead of a `SqliteException`, and enforces
everything SQLite cannot see: `withLength` bounds, cross-column pairings that an `ALTER TABLE`
could not carry, recipe-cycle detection, and the unit lock after an item's first movement.

All quantities are **micros** (`Quantity`, scale 1e6) and all money is **integer cents**. There is
no `REAL` column anywhere and no `double` ever touches either (ADR 0001).

---

## 2. The single write path

Every record mutation in the app — from a form, and from a Gate 4 agent when one exists — travels
one road:

```
Proposal { commandId (ULID), origin: form|agent, command: WorkspaceCommand, createdAt }
   │
   ▼  ApprovalService.submit          lib/features/approval/domain/approval_service.dart
DriftCommandApplier.submit            lib/features/approval/infrastructure/drift_command_applier.dart
   │  ONE db.transaction() around everything below
   ├─ encodeCommandPayload(command)   canonical JSON — fixed key order, micros, UTC epoch micros
   ├─ existing commands row?  ──yes─▶ replay: identical payload ⇒ original outcome
   │                                          different payload ⇒ DuplicateIdError
   ├─ DriftStateLoader.load(command)  the read model this command needs
   ├─ CommandValidator.validate(...)  pure, no I/O
   │     ├─ Err ⇒ insert commands row status='rejected' + reason; return Err
   │     └─ Ok  ⇒ ValidatedCommand (a proof token only the validator can construct)
   ├─ apply every effect + insert the commands audit row (status='applied')
   ▼
CommandReceipt { commandId, appliedAt, createdRecordIds, warnings }
```

Four properties fall out of that shape:

- **Atomic.** The audit row and every effect are in the same transaction. There is no state where
  a movement exists without the command that caused it, or vice versa. Every history root —
  `inventory_movements`, `event_closeouts`, `forecast_snapshots` — carries a `source_command_id`
  FK back to that audit row; their child tables hang off the root.
- **Idempotent.** `commandId` is the idempotency key, generated by the caller. Submitting it twice
  returns the original receipt; submitting the same id with a *different* payload is a
  `DuplicateIdError`. Same-process caches hold receipts and rejections; across restarts a receipt
  is reconstructed from the audit trail (warnings are best-effort and not persisted).
- **Semantics are pure.** `CommandValidator` is 29 sealed command types checked against an
  in-memory `WorkspaceReadModel` — no drift, no Flutter, no I/O. It is the same class whether the
  proposal came from a form or a model.
- **Rejections are recorded.** A refused command still writes its `commands` row with
  `status='rejected'` and the reason, so "why did nothing happen?" has an answer.

Diagnostics see `commandApplied` (with a count) or `commandRejected` (with an exception *type
name*) and nothing else — see [../security/THREAT_MODEL.md](../security/THREAT_MODEL.md) §3.5.

### Reads

Reads bypass all of this: DAOs under `lib/data/db/daos/` and drift `watch()` streams feed Riverpod
providers directly. One trap is worth knowing, and `lib/data/db/table_watch.dart` exists for it:
drift caches query streams by **statement text plus variables**, not by `readsFrom`, so two
watchers sharing one sentinel statement share a single stream and later subscribers silently
inherit the first one's invalidation set. `watchTables(label, tables)` requires a unique label per
call site to keep the statements distinct.

The most important read is the **label query** (`ForecastDao.labelQuerySql`, design §4.3): it
reads only `closeout_lines` joined to the latest revision of `event_closeouts` for events with
`status = 'closed'`. It is structurally unable to reach `forecast_*`, `events.planned_exposure`,
or drafts — which is what makes "confirmed outcomes are the only forecasting labels" a property of
the schema rather than a promise. See [forecasting.md](forecasting.md).

---

## 3. Migration discipline, and the incident that caused it

`AppDatabase.migration` in `lib/data/db/app_database.dart`. Four rules, each with a scar.

### Atomic, or not at all

```dart
await customStatement('PRAGMA foreign_keys = OFF');   // outside — pragmas are
try {                                                 // ignored inside a transaction
  await transaction(() => _migrationSteps(m, from, to));
  final violations = await customSelect('PRAGMA foreign_key_check').get();
  if (violations.isNotEmpty) throw StateError(...);
} finally {
  await customStatement('PRAGMA foreign_keys = ON');
}
```

**Why.** The v5 rollout shipped without this. The first launch on the owner's real phone applied
`ADD COLUMN unit_label`, failed at a later step, and — with no transaction — left the column
behind with `user_version` still 4. Every subsequent launch re-ran the block, hit `duplicate
column name`, and died before the first frame: a **white screen** with the owner's data intact
and unreachable. Now a failure at any step rolls the file back to exactly the bytes it arrived
with, and a dangling reference is caught before the transaction is trusted.

### Re-entrant

The v5, v6 and v7 blocks guard every step (`_columnExists`, `_tableExists`, `IF NOT EXISTS`) so a
file stranded part-way through completes the remainder instead of tripping over its own earlier
work. This is not theoretical: phones stranded by the pre-atomic v5 rollout carry part of that
block, and the guards are how they finish. Additive blocks written *before* the transaction
existed stay plain — under the transaction they can no longer strand anything.

### Staircase

Every block checks `to` as well as `from`. Production always upgrades to the latest version, but
the `SchemaVerifier` tests stop at intermediate versions and must get *exactly* that version's
schema. Two consequences:

- `test/db/migration_vN_to_vN+1_test.dart` — six files, v1→v2 through v6→v7. Each verifies the
  single step produces *exactly* that version's declared schema, and (from v2→v3 onward) that
  **every earlier version climbs the whole staircase** to it. Each then asserts that real seeded
  data survives byte for byte.
- Where a table's Dart shape later grew columns, the migration must run **frozen SQL** rather than
  `Migrator.createTable`, which always builds the *current* shape. `schemaV3FoldersCreate` is
  exactly that: the `folders` table as v3 shipped it, so a phone climbing v2→v4 lands on real v3
  before the v4 block ALTERs the appearance columns on.

### The real open path

`test/db/migration_real_open_path_test.dart` exists because the harness lies. `SchemaVerifier` and
`AppDatabase.forTesting(NativeDatabase.memory())` migrate on a bare connection, but production
opens through `openLoadoutExecutor`, whose `setup:` callback runs `PRAGMA foreign_keys = ON`
**before** drift's `onUpgrade` — and a migration that rebuilds a table (v5's copy-rewrite of
`recipes`) behaves differently under live enforcement. The test builds a genuine v4 database on a
real **keyed file** via the frozen generated schema, seeds it the way a used phone is seeded, and
reopens it through the production executor.

### One more rule: never rewrite an append-only table

SQLite's copy-rewrite (drift's `TableMigration`) is legal only on mutable master data. That is why
v5 widened `recipes.output_item_id` with a copy-rewrite (`recipes` has no forbid-triggers and is
absent from `appendOnlyTables`) but superseded `recipe_lines` with a new table instead: an
`INSERT` is legal on an append-only table, a rewrite is not. Additive nullable `ADD COLUMN`s are
always safe on append-only tables, because the forbid-triggers are blanket aborts that enumerate
no columns — v7's `closeout_lines.unit_price_cents` disturbs neither the triggers nor a single
existing row.

---

## 4. The seven versions

| Version | Added | Migration notes |
|---|---|---|
| **v1** | The base schema: `workspace_meta`, `settings`, `commands`, `items`, `events`, `event_items`, `inventory_movements`, `event_closeouts`, `closeout_lines`, `closeout_drafts`, `recipes`, `recipe_revisions`, `recipe_lines`, `forecast_snapshots`, `forecast_lines`, `forecast_evidence`, `forecast_overrides`; the append-only triggers and the `commands` limited-update trigger; the hot indices | `onCreate` also seeds the `workspace_meta` singleton and four default settings in the same transaction |
| **v2** | `items.serves_per_unit_micros` ("1 serves N"); five `forecast_lines.baseline_*` columns for the no-history baseline plan | Plain additive. An item became *name + how many + optionally how many one serves*; `unit`/`pack_size_micros` keep their v1 values on old rows and stop being surfaced |
| **v3** | The `folders` table; `items.folder_id`, `.demand_basis`, `.per_event_baseline_micros`, `.per_person_numerator`, `.per_person_denominator`; `forecast_lines.demand_basis` and three `baseline_per_*` columns; `uidx_folders_name_live`, `idx_items_folder` | `folders` is created **empty** from frozen v3 SQL — a migrated workspace gets folders from the owner's tidy-up flow, never from migration. Every added column is nullable and NULL means "unanswered". Nothing moves and no number changes until the owner acts |
| **v4** | `folders.hue_name`, `folders.icon_name` | Two nullable columns; NULL = "never chose", so effective hue comes from position order and effective icon from the starter-name table. Existing folders keep every byte |
| **v5** | `items.unit_label`; `recipe_lines_v2` + its limited-update triggers + a backfill from `recipe_lines`; `recipes.output_item_id` widened `NOT NULL` → nullable | The most invasive migration. Three different techniques for three different table kinds: plain `ADD COLUMN`; supersede-and-copy for the append-only `recipe_lines`; documented copy-rewrite (`TableMigration`) for the mutable `recipes`, with `uidx_recipes_output_live` recreated verbatim. First re-entrant block |
| **v6** | `items.barcode`; `uidx_items_barcode_live` | Nullable `ADD COLUMN` + a partial unique index mirroring the live-name index, so archiving an item frees its barcode exactly as it frees its name. Payloads are stored and compared **verbatim** — no symbology rules, no check digits, no normalisation |
| **v7** | `items.unit_price_cents` (current price, mutable), `closeout_lines.unit_price_cents` (the price **snapshotted** at confirm time) | Two nullable additive columns, integer cents only. The snapshot is why "what this event cost" survives later price edits; a revision re-snapshots, because a correction is made at today's knowledge. Pre-v7 rows stay NULL = "price unknown then", never 0 |
