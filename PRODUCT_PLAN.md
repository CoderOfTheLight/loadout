# Loadout product plan

Loadout is a private, offline event-inventory application for attendance-driven
small businesses and groups. The authoritative implementation brief is the
product and implementation plan supplied at repository bootstrap.

## Release contract

- Android 10/API 29+ and iOS 16+, ARM64 devices; desktop is post-MVP.
- One local owner workspace with no account, cloud sync, analytics, or runtime network.
- Confirmed outcomes—not predictions or overrides—are the only forecasting labels.
- Forecasts expose evidence, assumptions, method/version, overrides, and actuals.
- Recipe OCR and FunctionGemma remain local and always have form fallbacks.
- Inventory is derived from append-only movements; revisions are immutable.

## Delivery gates

0. Bootstrap repository, docs, CI, pinned SDK, and platform targets.
1. Prove model, encrypted database, OCR, offline behavior, latency, and memory on devices.
2. Complete domain/database and deterministic forecast engine.
3. Complete every workflow without AI.
4. Integrate the bounded FunctionGemma controller.
5. Complete OCR recipe review and deterministic production planning.
6. Harden recovery, privacy, accessibility, packaging, and releases.

No later AI-dependent feature is release-ready until gate 1 passes.
