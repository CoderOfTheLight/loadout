# Forecasting: how a number is produced

Everything between "she closed out three events" and "bring 44". This is the current, verified
account; [gates-2-3-design.md](gates-2-3-design.md) §6.6 is the original contract and predates
method v3.

The rule that shapes the whole subsystem: **`lib/features/forecasting/domain/forecast_engine.dart`
is FROZEN.** It is the only thing in the app allowed to turn confirmed history into a forecast.
Every improvement since has been made as a *transform on the observations handed to it*, or as a
clearly-separated *baseline* stored in its own columns — never as a change to the engine.

---

## 1. The only evidence: confirmed closeouts

A forecast label comes from exactly one query, `ForecastDao.labelQuerySql`
(`lib/data/db/daos/forecast_dao.dart`):

```sql
SELECT h.id AS closeout_id, h.event_id, h.confirmed_exposure,
       l.depletion_micros, l.stockout, l.approximate
FROM closeout_lines l
JOIN event_closeouts h ON h.id = l.closeout_id
JOIN events e ON e.id = h.event_id
WHERE l.item_id = ?1
  AND e.status = 'closed'
  AND h.revision = (SELECT MAX(h2.revision) FROM event_closeouts h2
                    WHERE h2.event_id = h.event_id)
ORDER BY e.scheduled_date DESC, e.id DESC
LIMIT ?2
```

It reads only the **latest revision** of the closeout of a **closed** event. It is structurally
unable to reference `forecast_snapshots`, `forecast_lines`, `forecast_overrides`,
`events.planned_exposure`, or `closeout_drafts` — a test pins that. So "confirmed outcomes are the
only forecasting labels" is a property of the SQL, not a promise: a prediction cannot become
evidence for the next prediction, and an override cannot teach the app anything.

`?2` is `history_window_events` (a workspace setting, default 12), and its value is recorded on
every snapshot.

**What a closeout line actually says.** `depletion_micros` is demand — what was used or sold —
and it **excludes waste**, which is recorded separately. `stockout` means "we ran out", which
makes the depletion a *lower bound* on demand rather than demand (§4). `approximate` marks a
guessed count. All three are written by the closeout flow (see gates-2-3-design.md §9,
CloseoutScreen).

## 2. The frozen engine

`DeterministicForecastEngine.forecastDirect`, in full, in order:

1. `upcomingExposure <= 0` throws `ArgumentError`.
2. Observations with `exposure <= 0` are filtered out. If none remain, the line is
   `EvidenceGrade.insufficientData` with all four figures `null` and the warning
   *"No comparable confirmed outcomes. Create a baseline plan."*
3. **Rate per observation:** `depletion.micros × 1e6 ÷ exposure`, integer-truncated.
4. **Median of the sorted rates:** the middle value for an odd count; the **floored mean of the
   two middles** for an even count.
5. **Expected use:** `ceil(medianRate × upcomingExposure ÷ 1e6)`.
6. **Planned:** `expected × (100 + reservePercent) ÷ 100`, rounded **up**
   (`Quantity.multiplyRatio` ceils). `PlanningPolicy`: `lean` 0 %, `balanced` 10 %,
   `cautious` 20 %.
7. **Load:** `planned` rounded up to `packSize`. Every item created since schema v2 has a pack
   size of exactly one unit, so in practice this means "round up to whole things".
8. **Acquire:** `load − (usableOnHand + confirmedInbound)`, floored at zero.
   `confirmedInbound` is always `Quantity.zero` today — the column exists, there is no UI.
9. **Evidence grade:** one usable observation ⇒ `singleEvent`; two or more ⇒ `observedRange`.
10. **Warnings** (verbatim strings, stored on the line): upcoming exposure outside the observed
    range; *"History includes lower-bound stockout demand."*; *"History includes approximate
    closeouts."*

The caller passes `usableOnHand = max(0, onHandMicros)` — a negative derived on-hand is stored
signed on the line and shown signed on screen, but the engine is never handed a negative.

**Every step is exact integer arithmetic on micros** (`Quantity`, scale 1e6, hard cap
`maxMicros = 1e15`). No `double` appears anywhere in this subsystem, no `REAL` column exists, and
rounding direction is a decision, not a floating-point accident (ADR 0001).

## 3. Method versions

`lib/features/forecasting/domain/snapshot.dart` holds the single source of truth:
`forecastMethodDirectMedian = 'direct_median'`, `forecastMethodVersion = 3`.

| Version | What changed | Constant |
|---|---|---|
| **v1** | Direct median of per-person rates, raw observations straight into the engine | — |
| **v2** | Sell-out days treated as a **lower bound** on demand before the engine sees them | `selloutAwareMethodVersion = 2` |
| **v3** | Items whose demand basis is `per_event` are forecast from the median of **per-event usage**, attendance ignored | `perEventAwareMethodVersion = 3` |

The engine is byte-identical across all three. What changed is what it is *handed*.

Every snapshot stores its own `method_version`, so a v1 snapshot stays readable exactly as it was
computed and nothing on screen may describe it as having allowed for the days that ran out —
because it did not. The version also tags the canonical input encoding (§8), which is what keeps
"same hash ⇒ byte-identical outputs" true across a method change rather than merely usually true:
every older snapshot honestly recomputes to a different hash and reads as out of date. The
forecast screen checks `method_version` first and names *that* as the reason, rather than
claiming an input changed.

## 4. Sell-outs (method v2)

`lib/features/forecasting/application/stockout_adjustment.dart`, `adjustForSellouts`.

"Sold 40 and ran out" is the most we could observe, not the most she could have sold. Feeding it
into the median like a day that ended with stock left over biases every forecast downward, and the
bias feeds itself: run out, record 40, forecast 40, bring 44, run out again. For a stall, running
out is the expensive failure.

Let `U` be the rates of the observations that did **not** sell out and `C` the ones that did:

- `C` empty → nothing happens; the engine sees the raw history (`kind: none`).
- `U` non-empty → each sell-out rate becomes `max(itsOwnRate, median(U))`, using the engine's own
  median definition. A sell-out can only ever **raise** the estimate (`kind: liftedToTypical`).
- `U` empty — every day sold out → the whole history is a lower bound. Every rate becomes the
  **largest observed rate**, and the line says outright that real demand is unknown and probably
  higher (`kind: everyDaySoldOut`). With a single sell-out observation there is nothing to raise
  it to, so the number is unchanged and only the warning is added.
- Days that did not sell out are never modified.

The engine takes depletions, not rates, so a lifted rate is realised as the smallest depletion
that reads back as at least that rate: `ceil(rate × exposure ÷ 1e6)`. That makes the transform
**monotone** — every adjusted depletion is ≥ the one it replaced, so every adjusted rate is ≥, so
the median is ≥, so the adjusted forecast is never below the unadjusted one.
`test/domain/stockout_adjustment_test.dart` pins that as a property over a seeded RNG. If the
lifted depletion would leave the exact-integer envelope the observation is left alone: that can
only forecast *lower*, never wrongly higher.

Three invariants hold around it:

1. **Stored evidence keeps the confirmed numbers.** `forecast_evidence` rows carry the real
   closeout figures with their real flags. An adjusted depletion is never written where a
   confirmed outcome belongs — it exists only in memory, on the way into the engine.
2. **Replay applies the same transform**, in the same order, so reproducibility survives.
3. **The owner is told in her own words** — *"You ran out on 2 of these days, so demand was
   probably higher than recorded — this allows for that."* No "censored", no "quantile". The rule
   itself is recorded in every snapshot's assumptions as `stockout_rule:
   sellouts_raise_never_lower` plus a one-sentence `stockout_rule_note`, so a stored forecast can
   still explain its own numbers years later.

**What this is not.** The size of the correction is a **floor, not a model**. When every past
event sold out, the app plans for the busiest day and says demand is unknown, rather than
inventing a multiplier.

## 5. Demand basis (method v3)

The one question every item answers: *does how much you bring depend on how many people come?*

`lib/features/catalog/domain/demand_basis.dart` holds **the** resolution rule, and nothing
re-derives it:

```dart
DemandBasis effectiveDemandBasis({DemandBasis? itemOverride, DemandBasis? folderBasis}) =>
    itemOverride ?? folderBasis ?? DemandBasis.perPerson;
```

Item override wins, else the folder's answer, else `per_person` — which is exactly how every item
behaved before folders existed, so upgrade day changes no number. It is resolved once, in
`DriftForecastService._buildInputs`, and stored on the snapshot line so a stored forecast can
still say which question it answered.

**`per_person`** ("more people, more of it" — food, disposables, merch) is the original path
above, unchanged.

**`per_event`** ("about the same every event" — soap, scrubbers, signs, the cash box) is
`lib/features/forecasting/application/per_event_basis.dart`. Two containers of soap used at each
of three 200-person events means "bring about two", not "0.01 per person" — the per-person
reading turns a 2 000-person event into a demand for 17 containers of soap. The honest forecast
is the median of what past events actually used, attendance ignored. The trick is that this needs
**no engine change at all**:

- Every confirmed observation is mapped to `exposure: 1`, depletion untouched.
- The engine is called with `upcomingExposure: 1`.
- Its rate becomes `depletion × 1e6 ÷ 1`, so its median-of-rates *is* the median of per-event
  depletions, and `medianRate × 1 ÷ 1e6` hands the median depletion straight back.

**Ordering matters:** map to exposure 1 **first**, then apply the sell-out lift. On exposure-1
observations the lift raises a ran-out day's *depletion* to the median depletion of the days that
did not — the per-event reading of "demand was probably higher". Lifting first would raise it to
an attendance-relative rate, which is the arithmetic this basis exists to escape.

Because a per-event estimate deliberately ignores attendance, a line warns when the upcoming
event is **more than twice** the largest exposure among its own evidence (checked against the
*real* stored exposures, not the mapped ones): *"This estimate comes from much smaller events —
bring more than usual and count what you use."* A warning only; no scaling is invented. Recorded
in assumptions as `per_event_rule: per_event_median_exposure_1`.

## 6. The engine envelope

`DriftForecastService._exceedsEngineEnvelope`. The schema and the validator both accept a
depletion of 1e12 micros against an exposure of 1 — a plausible typo — and the engine's
`rate × upcomingExposure` product would then silently wrap int64 and return a plausible-looking
wrong number. So before calling the engine, every **adjusted** rate is checked against
`Quantity.maxMicros ÷ upcomingExposure`. Over the limit, the line is stored with null figures,
`insufficient_data`, and one warning: *"Confirmed history for this item is too large to scale to
this event. Check the recorded outcomes and attendance."* A blank line with a reason is honest; a
wrong load quantity is not.

Per-event lines skip the check: at exposure 1 the schema caps *are* the envelope (depletion
≤ 1e12 micros ⇒ rate ≤ 1e18 < 2⁶³−1, and the even-count median sums two of them: ≤ 2e18, still
safe), and the per-person limit would wrongly refuse large legitimate per-event depletions.

## 7. Cold start: baselines are not forecasts

An item with no confirmed outcomes gets `insufficient_data` and no number — correct as evidence,
useless as a plan. `lib/features/forecasting/application/baseline_estimator.dart` produces a
starting number instead, **only** when the engine graded the line `insufficientData` *and* the
evidence list is genuinely empty. Three sources, one per cold-start question the owner may have
answered:

| Source | Column | Expected use |
|---|---|---|
| "1 serves N" | `items.serves_per_unit_micros` | `ceil(attendance × 1e6 ÷ serves)` whole units |
| "N per person" (flipped ratio) | `items.per_person_numerator` / `_denominator` | `UnitRatio.applyCeil` — exact, BigInt inside, so 200 people × 3/person is exactly 600, never the 601 a micros reciprocal gives |
| "How many do you usually bring?" | `items.per_event_baseline_micros` | that number; attendance plays no part |

Per-event lines use the third; per-person lines try serves-per-unit and fall back to the ratio (an
item never carries both — validator-enforced). Each then reuses the engine's *shape* — same
reserve percent, same pack rounding, same acquire subtraction — so the two read alike on screen.

A baseline **never reads history and never becomes history**. It is stored in its own
`forecast_lines.baseline_*` columns while `expected_use_micros` stays NULL and `evidence_grade`
stays `insufficient_data`; a SQL CHECK keeps that pairing honest, and the validator rejects a
baseline that arrives beside real evidence. Each carries a warning that says what it is not:
*"Estimate only: worked out from "1 serves 4", not from confirmed outcomes. Close out this event
and the next forecast uses what actually happened."*

If the arithmetic would leave the exact-integer envelope, the baseline is `null` — a blank line is
honest, a wrapped number is not.

## 8. Snapshots, reproducibility, and staleness

A forecast is **persisted, never recomputed for display**. `generateSnapshot` builds a draft and
submits `SaveForecastSnapshot` through the one write path (see
[data-model.md](data-model.md) §2), which appends a `forecast_snapshots` header, one
`forecast_lines` row per item, and `forecast_evidence` value-copies of exactly what the engine
consumed. Regenerating **appends** a new snapshot; the old one remains. Screens read the latest
(`MAX(id)`) via `watchLatestSnapshot`.

**`inputs_hash`** is SHA-256 (lowercase hex) over the UTF-8 bytes of a canonical encoding
(`lib/features/forecasting/domain/snapshot_inputs.dart`):

```
direct_median|<methodVersion>|<policy>|<upcomingExposure>|<historyWindow>
<itemId>|<packSizeMicros>|<onHandMicros>|<confirmedInboundMicros>[|s=…][|r=n/d][|b=per_event][|pe=…]
  ;<closeoutId>:<exposure>:<depletionMicros>:<stockout 0|1>:<approximate 0|1>  (repeated)
```

Lines are sorted by `itemId` bytewise regardless of construction order; evidence keeps
label-query order. Timestamps and snapshot/command ids are deliberately absent, so **the same
hash means byte-identical outputs**. The four optional per-line fields are appended only when
material, which leaves the encoding byte-identical for items that never answered a cold-start
question — and `_buildInputs` only carries the inputs material *under this line's basis*, so
editing the irrelevant one never reads as "inputs changed". `on_hand_micros` in the encoding is
the stored **signed** value.

`CommandValidator._saveForecastSnapshot` **recomputes the hash from the draft's own inputs** and
rejects a mismatch — a snapshot cannot be persisted with inputs that do not produce it.

**Staleness** (`isStale`) rebuilds the encoding from live state and compares it to the stored
hash. It returns `false` when the inputs can no longer be rebuilt at all — a closed or cancelled
event, or a cleared exposure — because a closed event's snapshot is frozen history, not stale.

## 9. Overrides change the plan, never the learning

`forecast_overrides` is append-only. `setOverride` appends a row; `clearOverride` appends a row
with a NULL `override_load_micros`, which means "revert to the engine value". The latest row per
(snapshot, item) wins for display. A reason of at least 3 characters is mandatory, including on
clear.

The line detail screen states the contract in the owner's words: *"Overrides change this plan
only. Forecasts learn from closeouts, never from overrides."* That is enforced structurally — the
label query in §1 cannot reach `forecast_overrides`, so an override is invisible to every future
forecast. The same is true of `events.planned_exposure`: only `event_closeouts.confirmed_exposure`
is ever an exposure label.

## 10. Actuals are derived, never stored

`accuracyReview` joins the latest snapshot's lines to the latest closeout revision's lines on
`(event_id, item_id)` and computes `varianceMicros = actualDepletion − expectedUse` per item, plus
the stockout/approximate flags and the live override. Nothing is written. That is what lets the
release contract — "forecasts expose evidence, assumptions, method/version, overrides, and
actuals" — be satisfied from one persisted record with no second source of truth to keep in step.

## 11. Where the tests are

| Area | Test |
|---|---|
| Frozen engine | `test/forecast_engine_test.dart` |
| The label query cannot read predictions | `test/db/derived_queries_test.dart` ("the SQL is structurally unable to read predictions") |
| Sell-out rule, incl. the monotonicity property | `test/domain/stockout_adjustment_test.dart` |
| Per-event basis and its int64 headroom | `test/domain/per_event_basis_test.dart` |
| Basis resolution | `test/domain/demand_basis_test.dart` |
| Cold-start baselines | `test/domain/baseline_estimator_test.dart`, `test/db/forecast_baseline_test.dart` |
| Canonical encoding and hash (incl. a golden vector) | `test/domain/snapshot_hash_test.dart` |
| Snapshot persistence through the write path | `test/db/forecast_write_test.dart`, `test/db/forecast_per_event_test.dart` |
