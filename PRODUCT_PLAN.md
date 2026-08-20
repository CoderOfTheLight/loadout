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

## Gate 5 status

Gate 5 is **half built**, and the two halves are unrelated in everything but
the gate number.

**OCR recipe review — shipped on iOS.** Apple Vision text recognition
(revision 3, the iOS 16 floor) sits behind a MethodChannel
(`ios/Runner/RecipeOcrChannel.swift`,
`lib/features/recipes/application/recipe_ocr_service.dart`) and feeds the same
review pipeline as "Paste ingredients" — OCR is a second producer, not a
second reviewer, so the typed form remains the fallback it always was.
Availability is treated as a capability rather than an error: the probe
returns false on Android, where the ML Kit half has not been built, and the
affordance simply does not appear.

**Deterministic production planning — not built, and it has no screen.** An
earlier design specified a `/production` route with a "coming soon" stub
screen and a disabled tile on the event detail screen. Both were built and
then **deleted**: a disabled dead end taught the owner nothing. Nothing under
`lib/` references production planning today — no route, no screen, no service,
no seam beyond the frozen `ForecastEngine` interface it will extend. It is a
future capability, and when it arrives it brings its own surface with it. See
[docs/architecture/gates-2-3-design.md](docs/architecture/gates-2-3-design.md)
§13.
