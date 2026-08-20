# How this app was actually built

The README tells the story of the method. This document is the evidence: the
roles, the contracts, the verification, and the places it failed.

Loadout's implementation was written by AI agents working under my direction,
from planning documents I wrote, against contracts I specified. I want that to
be legible rather than implied, including the parts that did not work.

---

## 1. Roles, and which class of model did each

The single most useful decision was refusing to treat "the AI" as one thing.
Different jobs have different failure modes, and paying for deep reasoning on
mechanical work wastes money without improving the result.

| Role | Model class | What it did | Why that tier |
|---|---|---|---|
| **Lead / verifier** | Strongest available | Wrote contracts, reviewed every agent's diff, ran the gates independently, integrated, decided what to escalate | Judgement, cross-cutting consistency, and catching what a specialist could not see from inside its own territory |
| **Feature builder** | Strong | Schema migrations, the command write path, forecasting surfaces, closeout — anything where being wrong is expensive and silent | Correctness under invariants; these touch data that cannot be un-corrupted |
| **UI rebuilder** | Strong | Screen-by-screen redesign against a measured brief | Needs taste and constraint-following simultaneously |
| **Researcher / auditor** | Strong, read-only | Design research, security audit, accessibility audit, release-readiness audit | Adversarial reading; explicitly told not to reassure |
| **Mechanical** | Lighter | Screenshot and GIF harnesses, doc corrections, glyph sweeps, format/lint fixes | Deterministic, verifiable by inspection |

Auditors were given **read-only** scope on purpose. An agent that can both find
and fix a problem tends to do both quietly, and I wanted the findings before the
patches so I could decide which were worth acting on. Two audit findings I
deliberately left unfixed for weeks are still listed in
[`RELEASE.md`](RELEASE.md) — that was a choice, not an oversight.

---

## 2. A task contract, sanitised

Agents were never given a goal alone. Every one received: the job, its file
territory, an explicit do-not-touch list, the constraints it could not violate,
the tests it had to add, the gate it had to pass, and the shape of the report it
owed back. This is a real brief, lightly trimmed:

> You OWN: `lib/features/closeout/**` and its tests. Do NOT touch
> `lib/features/catalog/presentation/**` (a concurrent agent owns it),
> `lib/features/forecasting/domain/forecast_engine.dart` (FROZEN), schema or
> migration code, or `lib/app/theme.dart` (consume it, do not edit it).
>
> **Owner feedback, verbatim:** "The closeout is still too complicated and needs
> to option to closeout without doing inventory."
>
> Ship this: the default card is ONE number box and two shortcuts... `Ran out`
> becomes contextual, not permanent. It only appears once the line reads as
> empty. It MUST remain reachable, because it drives stockout handling in the
> forecast — a sold-out item that is not marked teaches the forecast that demand
> was exactly what you brought.
>
> THIS IS ALREADY LEGAL IN THE WRITE PATH — I verified:
> `CommandValidator._closeoutShared` requires only `confirmedExposure` in
> 1..1000000 and validates each line if present, so an EMPTY line list is a real
> closeout, not a hack.
>
> Quality bar: `fvm dart analyze` clean, `fvm dart format` clean, full
> `fvm flutter test` passing (1122 currently; if a failure is clearly a
> concurrent agent's, report rather than fix).
>
> Return: files changed, the exact control inventory of a default card (count
> them), where `Close without counting` lives and its exact wording, test
> counts, **what was lost**.

Four things in that brief did most of the work:

- **The user's words, verbatim.** Not my paraphrase of them.
- **A verified fact the agent would otherwise have to guess at.** I checked the
  validator myself before writing the brief, so the agent did not invent a
  workaround for a constraint that did not exist.
- **The reason behind a rule**, not just the rule. "Keep `Ran out` reachable"
  invites a loophole; explaining what it costs the forecast does not.
- **"What was lost" as a required section.** Agents report wins by default.
  Asking for the losses is how you find out what a refactor quietly deleted.

---

## 3. File ownership, and why parallelism needed it

Up to four agents ran at once. They did not coordinate with each other — they
coordinated through me, and through disjoint territory.

Each brief named an `OWN` list and a `do NOT touch` list, and the lists were
constructed so no two concurrent agents shared a file. When one agent needed
something inside another's territory, it reported the need instead of reaching
in. Real example, from the round that rebuilt four areas of the UI at once:

> Another agent edited `lib/features/catalog/presentation/tidy_folders_screen.dart`
> (my directory) — its two test failures appeared mid-session and they fixed
> them; I did not touch it.

Where two agents genuinely had to build opposite halves of one feature, **the
contract between them was written and committed first** — before either started.
The Swift↔Dart method channel for the camera work
(`lib/features/catalog/application/barcode_scan_service.dart`) and the money and
prediction types for event costing
(`lib/features/forecasting/domain/event_cost.dart`) both exist as standalone
commits for this reason. Neither agent could drift from the other, because the
boundary predated both of them.

---

## 4. What verification actually meant

"The agent said it was done" is not evidence. Every agent had to clear the same
bar, and the lead re-ran it independently rather than trusting the report:

1. `fvm dart analyze` clean — zero issues, not zero errors.
2. `fvm dart format` clean.
3. **The entire test suite**, not the agent's own tests. This is the one that
   catches cross-feature breakage, and agents were explicitly told to report a
   failure they believed belonged to a concurrent agent rather than "fix" it
   blind.
4. Tests added that would have caught the specific bug being fixed. A fix
   without a regression test was sent back.
5. For UI work: the screens were **re-rendered and looked at**. The capture
   harness in `test/tooling/` exists because reading a diff is not the same as
   seeing the screen, and several problems were only visible in the image.

The lead also caught integration problems no individual agent could see. When
two agents built event costing in parallel, both were correct in isolation and
wrong together: the item picker totalled "one of each at today's price" while the
event screen totalled forecast quantities × price. Same list, totals differing by
nearly 3×, with nothing on screen explaining why. The fix was a label, and it
came from reviewing the two reports side by side.

---

## 5. A failure the agents missed

The most instructive one is recent, and it is not the dramatic one.

Every agent that touched the repo for four days reported the full test suite
passing. Every one was telling the truth. **CI was red the entire time**, and
nobody noticed — because "run the test suite" meant running it on the machine it
was written on.

A screenshot harness had been added with its output directory defaulting to an
absolute path from that machine (`/private/tmp/claude-501/…`). On Linux the path
does not exist, the test fails, and because CI steps run in sequence, the failure
skipped all nine of the privacy and security assertions after it. The gates that
justify the project's central claim had not run since the commit that introduced
the harness.

Three lessons, all of which are now structural rather than remembered:

- **A local green is not a green.** The agent's environment was not the
  environment that matters.
- **Developer tools do not belong in the product test suite.** Both harnesses
  now skip unless explicitly opted into, matching the GIF harness that had
  already been written correctly.
- **A machine-specific path in a public repo is its own problem**, separate from
  CI. There are now none anywhere in `lib`, `test` or `tool`.

The other failure worth naming is the one the README tells: a half-applied
migration that opened the app to a blank screen. No agent found it, and no test
suite could have — the tests migrated in-memory databases while the phone
migrated a real encrypted file. **A physical device found it in under a minute.**

---

## 6. A decision I overruled

An accessibility and complexity audit recommended deleting per-item waste
tracking from the counting screen. Its reasoning was sound on its own terms: the
card carried too many controls, waste was rarely used, and removing it would
measurably simplify the screen the volunteers use most.

I kept it, and told the agent to hide it instead — behind a "Some was thrown
out" control that reveals one box and defaults to zero.

Waste is what separates *what sold* from *what got thrown away*. The forecast
learns from depletion, and depletion deliberately excludes waste; if waste stops
being recorded it silently becomes demand, and every future packing list inherits
the error. The screen would have gotten simpler and the product would have gotten
quietly wrong, in a way no test would fail and no user would notice for months.

That is the class of judgement I do not delegate: **simplification that is
locally correct and globally destructive.** An agent optimising the screen in
front of it cannot see the forecast three months later.

I was also overruled, and the record should say so. I cut the unit field from the
new-item form to hit a four-field target; the owner's response was that "18
quarts" is how a kitchen names an amount and that saving an item just to reopen
it and add "quarts" was worse than one more box. She was right, and it went back.

---

## 7. What "done" required

An agent's work was accepted only when all of this held:

- **It worked on a physical phone**, in a real flow, not a demo path. Every
  round was installed on an iPhone and used before it counted as finished.
- The full suite, analyzer and formatter were clean **on a re-run by the lead**.
- A regression test existed for the specific failure being fixed.
- The change did not violate the frozen invariants: the forecast engine
  untouched, history append-only, integer arithmetic only, one write path.
- **No number was invented.** If something could not be computed honestly —
  an unpriced item, an event with no history — the UI omits it and says why,
  rather than showing a zero.
- Any capability the change removed was reported explicitly and accepted by me,
  not discovered later.

The last two are the ones I would keep if I could keep only two. Most of what
makes this app trustworthy is not what it computes; it is what it refuses to
claim.
