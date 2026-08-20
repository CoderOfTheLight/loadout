# Architecture docs

Index of everything in `docs/architecture/`. In this repo the docs are treated as spec: where a
document and the code disagree, that is a bug in one of them, and the document says which file is
authoritative for each claim.

## Start here

**[gates-2-3-design.md](gates-2-3-design.md)** — the implementation contract. It is the single
authoritative design for Gate 2 (domain, database, deterministic forecast engine) and Gate 3
(every workflow without AI): principles, package set and SQLCipher sourcing, the complete schema,
ledger and closeout semantics, the single write path, startup and key management, backup/restore,
the screen map, diagnostics and platform hardening, the test plan. Long, and self-contained —
read §1 for the six principles that decide everything else, then jump to the section you need.

Because it is the *original* contract, parts of it have been overtaken by later work. Those
places now carry an explicit correction and a pointer; the two documents below are the current,
re-verified accounts of the areas that moved most.

## The rest

| Document | What it covers |
|---|---|
| [data-model.md](data-model.md) | The schema as it stands at **v7**: append-only history vs mutable master data, the triggers and foreign keys that enforce it, the one write path (Proposal → `CommandValidator` → `DriftCommandApplier`), the migration discipline and why it exists, and what each of the seven schema versions added. |
| [forecasting.md](forecasting.md) | How a number on the packing list is produced: confirmed closeouts as the only evidence, the frozen median-of-rates engine, method versions v1–v3, demand-basis resolution, cold-start baselines, what an override does and does not do, and the integer-only rule. |
| [gates-2-3-design.md](gates-2-3-design.md) | The implementation contract — see above. |
| [gate-1-ai-options.md](gate-1-ai-options.md) | Gate 1 decision document (12 Aug 2026): the on-device FunctionGemma + OCR stack, what it costs in app size, RAM and latency, and the recommendation to ship the OCR half and kill-spike the model half. Decision record, not a design. |

## Elsewhere

- [../security/THREAT_MODEL.md](../security/THREAT_MODEL.md) — assets, adversaries, what is
  protected and how, and — at least as important — what is not. The authority for the app's
  privacy claims.
- [../RELEASE.md](../RELEASE.md) — everything between a green test run and an installable app;
  the current blocker list for a store submission.
- [../adr/0001-authoritative-deterministic-core.md](../adr/0001-authoritative-deterministic-core.md)
  — deterministic Dart is authoritative; generated values cannot become records without
  validation and approval.
- [../../PRODUCT_PLAN.md](../../PRODUCT_PLAN.md) — release contract and the seven delivery gates.
