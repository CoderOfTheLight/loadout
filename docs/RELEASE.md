# Releasing Loadout

Everything that stands between a green test run and an app someone else can
install. Gate 6 of [PRODUCT_PLAN.md](../PRODUCT_PLAN.md).

Items marked **OWNER** need a decision or a credential only the owner has;
nothing else can proceed past them.

---

## 1. Android signing

Release builds currently fall back to **debug keys** when no keystore is
configured. They install and run, and Play will refuse them.

**OWNER — create the upload keystore once:**

```sh
keytool -genkey -v -keystore ~/loadout-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (git-ignored, never committed):

```properties
storePassword=<the store password you just chose>
keyPassword=<the key password you just chose>
keyAlias=upload
storeFile=/Users/<you>/loadout-upload.jks
```

`android/app/build.gradle.kts` picks it up automatically and signs release
builds with it; without the file it silently falls back to debug keys.

> **Back the keystore up somewhere you will still have in five years.**
> Losing it means you can never ship an update to the same Play listing —
> only a new listing with a new identity, and your users do not migrate.
> If you enrol in Play App Signing, this file is your *upload* key and Google
> holds the app signing key; that is the safer arrangement, and it is what to
> pick if asked during setup.

Verify a signed build:

```sh
fvm flutter build appbundle --release
```

## 2. iOS export compliance — **OWNER**

The app encrypts the workspace database (SQLCipher/AES) and derives backup
keys with Argon2id, so App Store Connect will ask about encryption on every
submission. `ITSAppUsesNonExemptEncryption` is deliberately **absent** from
`ios/Runner/Info.plist`: this is a legal determination about your product,
and it is not one this repo should silently make for you.

The two outcomes:

- **`false`** — you are asserting your use of encryption is exempt. Common
  for apps that only protect the user's own data on the device, but the
  exemption depends on specifics, and asserting it wrongly is an export
  violation, not a paperwork slip.
- **`true`** — non-exempt. You then owe an annual self-classification report
  to BIS and may need a CCATS/ERN, and submissions ask for the documentation.

Read Apple's *Complying with Encryption Export Regulations*, and if there is
any doubt, ask someone qualified — this is cheap to get right once and
expensive to get wrong. Once decided, add the key to `Info.plist` so every
submission stops asking.

## 3. Store metadata — **OWNER**

Both stores need material that does not exist yet:

- **Screenshots** at the required device sizes. Take them once the redesign
  has settled, from a workspace with realistic data (a few items, one past
  event with a closeout, one upcoming event with a forecast) — empty screens
  sell nothing.
- **Description and subtitle.** The app's own words are a good start: plan
  what to bring, record what you actually used, get better at guessing.
- **Privacy labels.** These are unusually easy here and worth stating
  confidently: no data collected, no data shared, no tracking, no analytics,
  no account. The CI gates in `.github/workflows/ci.yml` prove the shipped
  binary has no network permission at all.
- **Age rating**, support URL, and a privacy policy URL (a short page saying
  the app collects nothing and stores everything on the device).

## 4. Version numbering

`pubspec.yaml` carries `version: <name>+<build>`. The name is what users
see; the build number must increase on every upload to either store. Bump it
in `pubspec.yaml`, not in Xcode or Gradle, so both platforms stay in step.

## 5. Pre-flight

Run before every release build:

```sh
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze
fvm flutter test
fvm flutter test integration_test/device_encryption_test.dart -d <device>
```

CI runs the first three plus the hardening assertions on every push,
including dumping the **release** APK's permissions to prove there is no
INTERNET permission. That check is the authoritative offline guarantee —
debug and profile builds deliberately carry the permission so the Dart VM
service can attach.

## 6. Still outstanding for v1

Tracked here so it is visible rather than remembered:

- **Latency and memory on a physical device.** Gate 1's remaining half.
  The encrypted backup (Argon2id) is the one to watch — it is deliberately
  expensive and has never been timed on a phone.
- **Recovery drill.** Make a backup, delete the app, reinstall, restore.
  Automated tests cover the round trip; no human has done it end to end.
- **Interrupted restore has no route back.** If the process dies mid-swap
  the data survives (the key is retained) but the app reports a fresh
  install and offers no way to recover the parked workspace.
- **Stockouts bias forecasts downward.** A sellout is recorded as demand
  rather than as a lower bound on demand, so forecasts drift down and cause
  more sellouts. See the forecasting notes in
  [gates-2-3-design.md](architecture/gates-2-3-design.md).
- **Accessibility pass** — screen reader labels, 200% text scale, contrast.
- **Physical Android device** — only the emulator so far.
