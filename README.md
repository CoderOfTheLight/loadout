# Loadout

**Know what to bring. Know what it cost. Keep it on your phone.**

Loadout is an inventory and planning app for people who feed a crowd — community
kitchens, church halls, market stalls, anyone who packs a van, serves a few
hundred people, and has to work out what to buy for next time.

It runs entirely on your phone. No account, no cloud, no analytics, and no
network permission at all. Your supply lists, your costs, and your event history
never leave the device.

<table>
  <tr>
    <td align="center"><img src="docs/media/add-item.gif" width="300" alt="Adding an item: four fields and Save"></td>
    <td align="center"><img src="docs/media/closeout.gif" width="300" alt="Counting after an event: one question per item"></td>
    <td align="center"><img src="docs/media/event-cost.gif" width="300" alt="Planning an event, with the cost adding up live"></td>
  </tr>
  <tr>
    <td align="center"><b>Add what you have</b><br>Name, how many, unit, folder.</td>
    <td align="center"><b>Count what came back</b><br>One question per item.</td>
    <td align="center"><b>See what it costs</b><br>Totals as you pick.</td>
  </tr>
</table>

---

## The loop

Loadout is built around one cycle, and everything in it exists to serve that
cycle:

1. **Organise** your supplies into folders — cooked on site, bought ready to
   serve, cleaning, paper goods, the sales table.
2. **Plan an event.** Say how many people you expect. Loadout works out a
   packing list and what it should cost.
3. **Count what's left** afterwards. One number per item.
4. **Next time is better.** That count — and only that count — is what the
   forecast learns from.

The fourth step is the point. Loadout never learns from a guess, a plan, or an
estimate. Only from what you confirmed actually happened.

## What it does

**Supplies.** Items live in colour-coded folders with an amount, an optional
unit ("18 quarts"), an optional price, and an optional barcode. The items screen
totals what's on your shelves.

**Events.** Build a list by hand, copy the whole list from a previous event, or
let Loadout suggest one. See the estimated cost before you shop, and what
similar events actually cost afterwards.

**Packing lists.** A deterministic forecast — no AI, no black box. It takes the
median of what you actually used at past events, adjusts for how many people are
coming, and tells you what to bring. Tap any line and it explains itself in a
sentence: *"Bring 16. Last time you used 16 for 165 people; before that, 14 for
150. You have 18."*

**Counting after an event.** Each item asks one thing: how many are left. It
already knows what you loaded, so it works out what got used. Sold out? Say so,
and the forecast knows demand might have been higher than what you brought. In a
hurry? Close the event without counting at all — it records honestly that
nothing was learned.

**Recipes.** Write them, or photograph a printed one and let the phone read it.
Scale a batch to an event. See what a batch costs at today's prices.

**Scanning.** Scan a barcode once, tell Loadout what it is, and it recognises
that item forever. Restocking becomes scan, type a number, scan the next thing.
Counting after an event works the same way.

**Spreadsheets.** Export items, events, a single event's count, or recipes as
CSV files that open properly in Excel — for a treasurer, a committee, or
whoever takes over the kitchen next year.

**Backups.** One encrypted file, protected by a passphrase you choose, saved
wherever you keep files.

## Status

**This is version 1: phones only.** Desktop support (macOS, Windows, Linux) is
planned for version 2.

| | iOS 16+ | Android 10+ |
|---|---|---|
| Everything above | ✅ | ✅ |
| Barcode scanning | ✅ | ❌ not yet |
| Recipe photos (OCR) | ✅ | ❌ not yet |
| Tested on real hardware | ✅ | ⚠️ emulator only |

Both scanning features degrade honestly on Android — the buttons simply don't
appear rather than appearing and failing.

**Not in an app store yet.** The app is feature-complete for version 1 and
heavily tested, but store packaging is unfinished: no signing key, no privacy
policy URL, no iOS privacy manifest, and no store listing. See
[docs/RELEASE.md](docs/RELEASE.md) for the full, honest checklist of what
remains — including one known gap worth naming here: if the app fails to start,
it currently shows a blank screen instead of an explanation.

## Privacy, concretely

Most apps say "we respect your privacy". Here is what that means in this
codebase, and how each claim is enforced rather than promised:

- **No network permission.** The Android release build declares exactly one
  permission, and it isn't internet access. CI unpacks a real release APK and
  fails the build if `INTERNET` ever appears.
- **Encrypted at rest.** The database is SQLCipher-encrypted with a key held in
  the iOS Keychain / Android Keystore. If the encryption library is ever missing,
  the app refuses to run rather than quietly writing plain text.
- **Excluded from cloud backups** and from phone-to-phone transfer, deliberately.
  The trade-off is real and worth knowing: **a new phone means starting over
  unless you have a backup file.**
- **Diagnostics cannot leak your data.** The logging function has nowhere to put
  free text — it accepts event codes, counts and durations, and nothing else.
- **Camera stays local.** Barcode and recipe scanning use Apple's on-device
  frameworks. Photos are never written to disk or sent anywhere.

The full model, including what is *not* protected, is in
[docs/security/THREAT_MODEL.md](docs/security/THREAT_MODEL.md).

## Building it

Requires [FVM](https://fvm.app) — the Flutter SDK is pinned to **3.44.7**.

```bash
fvm install          # fetch the pinned SDK
fvm flutter pub get
fvm flutter test     # 1,138 tests
fvm flutter run      # on a connected phone or simulator
```

Release builds:

```bash
fvm flutter build ios --release
fvm flutter build apk --release
```

Regenerate the demo GIFs and screenshots after a UI change:

```bash
LOADOUT_GIFS=1 fvm flutter test test/tooling/gif_capture_test.dart
LOADOUT_SCREENS_OUT=/tmp/shots fvm flutter test test/tooling/screen_capture_test.dart
```

## How it's built

Loadout is a Flutter app over an encrypted SQLite database, with a few rules it
holds strictly:

- **History is append-only.** Movements, closeouts and recipe revisions can never
  be edited or deleted — corrections are new entries that reverse old ones. This
  is enforced three ways at once: SQL triggers, foreign-key restrictions, and a
  validator.
- **One write path.** Every change is a command that goes
  `Proposal → CommandValidator → DriftCommandApplier`, in one transaction. There
  is no second way to write to the database.
- **Integer arithmetic only.** Quantities are fixed-point micros; money is whole
  cents. No floating point anywhere in the maths, so totals never drift.
- **Migrations are all-or-nothing.** Every schema upgrade runs in a single
  transaction and can be safely re-run, and is tested from every previous version
  through the real production open path. This discipline came from a real
  incident — a half-applied migration once left a phone showing a white screen —
  and there is now a test that recreates exactly that stranded state.
- **The forecast engine is frozen.** It is pure, deterministic, and takes no
  dependencies. Prices, display formatting and policy live outside it.

| Document | What's in it |
|---|---|
| [docs/architecture/README.md](docs/architecture/README.md) | Index — start here |
| [docs/architecture/data-model.md](docs/architecture/data-model.md) | The schema, the write path, migration discipline |
| [docs/architecture/forecasting.md](docs/architecture/forecasting.md) | How a number gets produced |
| [docs/security/THREAT_MODEL.md](docs/security/THREAT_MODEL.md) | What's protected, what isn't |
| [docs/RELEASE.md](docs/RELEASE.md) | Shipping checklist and known gaps |
| [PRODUCT_PLAN.md](PRODUCT_PLAN.md) | Delivery gates and scope |

## Testing

1,138 tests, run with `fvm flutter test`. They cover more than units:

- **Migration tests** upgrade real encrypted database files from every past
  schema version through the production code path, including deliberately
  half-migrated ones.
- **Contrast tests** measure every text-and-background pair in the app against
  WCAG 2.2, in both light and dark.
- **Route tests** walk every screen at a real phone viewport across four
  different workspace states, asserting nothing overflows and no screen is a
  dead end.
- **Text-scale tests** render the dense screens at 200% text size on a narrow
  phone, because the people using this app often need large text.
- **Screenshot and GIF harnesses** render the real app with realistic data, so
  the images in this README can never drift from what the app actually looks
  like.

## Roadmap

**Version 1 (now):** phones, everything above.

**Version 2:** desktop — macOS, Windows and Linux — plus Android parity for
scanning and recipe photos.

**Under consideration:** a shareable count report, production planning (working
backwards from a menu to a prep schedule), and voice entry for hands-free
counting.
