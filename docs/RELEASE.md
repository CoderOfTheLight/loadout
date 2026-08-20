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
  **Android** binary has no network permission at all; iOS has no equivalent
  permission to withhold, so there the claim rests on the dependency and
  source gates only (see §6.1).
- **Age rating**, support URL, and a **privacy policy hosted at a public
  URL** — both stores require one, and there is no such page today. A short
  page saying the app collects nothing and stores everything on the device is
  enough, but it has to exist somewhere reachable.

## 3b. iOS privacy manifest — **BLOCKER**

`ios/Runner/PrivacyInfo.xcprivacy` **does not exist**. Apple has required a
privacy manifest since May 2024 for apps using "required reason" APIs, and
submission without one is an automatic rejection rather than a review note.

This app needs one because SQLCipher/`package:sqlite3` reaches for
required-reason APIs in the ordinary course of opening and writing a
database — file timestamps (`NSPrivacyAccessedAPICategoryFileTimestamp`) and
available disk space (`NSPrivacyAccessedAPICategoryDiskSpace`) at minimum.
The manifest also carries the tracking/collected-data declarations, which for
Loadout are all "none".

> The two categories above are the ones a SQLite-backed app normally has to
> declare; **confirm the exact list against the built binary** (Xcode's
> privacy report, or a symbol scan of the linked `libsqlcipher`) before
> filling the file in. Getting the list wrong is a second rejection.

## 4. Version numbering — **two places, not one**

`pubspec.yaml` carries `version: <name>+<build>` (today `1.0.0+1`). The name
is what users see; the build number must increase on every upload to either
store. Bump it in `pubspec.yaml`, not in Xcode or Gradle, so both platforms
stay in step — Android `versionCode`/`versionName` and iOS
`CFBundleShortVersionString`/`CFBundleVersion` are all interpolated from it.

**That is not the only place the version lives.** `seedAppVersion` in
`lib/data/db/app_database.dart` is a hand-copied duplicate of the same
string:

```dart
/// Seeded into `workspace_meta.created_by_app_version`. Keep in sync with
/// pubspec.yaml; runtime version lookup is deliberately absent (no
/// package_info dependency in v1).
const String seedAppVersion = '1.0.0+1';
```

It is not cosmetic. It is written into `workspace_meta.created_by_app_version`
on every fresh workspace, stamped into **every backup manifest**
(`backup_service_impl.dart`), and shown to the owner on `/settings/about`.
Nothing enforces that the two agree — no test, no CI step, no analyzer rule.
Forget it and the About screen lies, and every backup file made afterwards
carries a version stamp for a build that never shipped.

**So the release step is: bump `pubspec.yaml` AND `seedAppVersion`, in the
same commit.** (The honest fix is a `package_info_plus` lookup or a generated
constant; neither exists today.)

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
INTERNET permission. That check is the authoritative offline guarantee **on
Android** — debug and profile builds deliberately carry the permission so the
Dart VM service can attach, which is exactly why a source grep is not the
gate. iOS has no equivalent permission, so nothing there is enforced by the
OS; see §6.2.

Two checks CI does **not** do, so do them by hand:

```sh
# 1. seedAppVersion must equal pubspec's version — nothing enforces this (§4).
grep -n '^version:' pubspec.yaml
grep -n 'seedAppVersion' lib/data/db/app_database.dart

# 2. The shipped artifact must advertise arm64-v8a and nothing else (§6.1 #7).
"$ANDROID_HOME"/build-tools/*/aapt dump badging \
  build/app/outputs/flutter-apk/app-release.apk | grep native-code
```

## 6. Still outstanding for v1

Tracked here so it is visible rather than remembered. Split into what *stops*
a submission, what is a known gap in the app, and what has simply never been
done on real hardware.

### 6.1 Store-submission blockers

Nothing can be uploaded until every one of these is cleared. None is
technically hard; all of them are undone.

| # | Blocker | Where |
|---|---|---|
| 1 | **No Android signing key.** `android/key.properties` does not exist, so release builds silently fall back to **debug keys**. They install and run; Play refuses them | §1 |
| 2 | **`ITSAppUsesNonExemptEncryption` is unanswered.** Deliberately absent from `ios/Runner/Info.plist` — an owner legal determination, not a repo default. Every submission will ask until it is decided and written in | §2 |
| 3 | **No `PrivacyInfo.xcprivacy`.** Missing entirely; an automatic App Store rejection for an app that touches required-reason APIs, which SQLCipher does | §3b |
| 4 | **No privacy policy at a URL.** Both stores require a reachable page. None exists | §3 |
| 5 | **No store metadata at all.** No screenshots at the required device sizes, no description, no subtitle, no privacy labels filled in, no age rating, no support URL | §3 |
| 6 | **No AAB and no IPA have ever been built.** `build/` contains a release APK and a `Runner.app`; there is no `.aab`, no `.xcarchive` and no `.ipa` anywhere. The upload formats have therefore never been produced, let alone validated by App Store Connect or the Play console | — |
| 7 | **The release APK advertises ABIs it cannot run.** `aapt dump badging` on `build/app/outputs/flutter-apk/app-release.apk` reports `native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'`, but only `lib/arm64-v8a/` contains `libflutter.so` and `libapp.so` — the other two hold a stray `libdartjni.so` (from the transitive `jni` package) and nothing else. Play derives device targeting from those folders, so a 32-bit-only or x86_64 device could install a build with no engine in it. `abiFilters += "arm64-v8a"` in `android/app/build.gradle.kts` did **not** strip them. Fix before the first upload, and re-check the badging output of the artifact you actually ship | — |
| 8 | **Play's closed-testing requirement.** For a *personal* Google Play developer account created after 13 November 2023, production access requires a closed test with at least **12 testers opted in continuously for 14 days**. If this account qualifies, that is a two-week floor between "ready" and "published", and it has to be scheduled rather than discovered. Confirm the account type and creation date — this repo cannot | — |

### 6.2 Known gaps in the app

- **The v5 white-screen failure class — both halves now closed.**
  - **The data-integrity half.** Migrations are atomic (a failure at any step
    rolls the file back to the bytes it arrived with) and re-entrant (a file
    stranded part-way through completes the remainder instead of dying on
    `duplicate column name`), with a `PRAGMA foreign_key_check` after every
    upgrade and a test that runs the real keyed open path rather than the
    harness. A migration can no longer strand a workspace. See
    [architecture/data-model.md](architecture/data-model.md) §3.
  - **The presentation half.** `bootstrapOrFail` (`lib/app/bootstrap.dart`)
    wraps the pre-`runApp` bootstrap: a throw — a corrupt key entry, an
    unreadable support directory, an unanticipated drift error, and
    deliberately the cipher-missing guard — becomes
    `StartupFailureApp`/`StartupFailureScreen` instead of a blank frame. The
    screen says in plain words that Loadout could not start, offers **Try
    again** (re-runs the same bootstrap over the same services) and
    **Restore from backup file** (the §8.2 flow, which needs no open
    database), and can **save the diagnostics file** — until now the log
    lived behind the app that would not open. `DiagEvent.startupFailed` is
    recorded before the screen appears. `ErrorWidget.builder` is set to a
    readable, content-free widget in every build mode, so a widget-build
    failure is not a grey rectangle either. Error handling is
    `PlatformDispatcher.instance.onError`, **not** `runZonedGuarded`:
    binding and `runApp` stay in the root zone together, which is what
    Flutter 3.44 wants (see `lib/app/error_handling.dart`). The §7.2
    cipher-missing refusal is unchanged — it still refuses to run on plain
    SQLite, it just refuses onto a screen. Covered by
    `test/app/startup_failure_test.dart`.
- **The "no network permission" claim is Android-only — the screen now says
  so.** The CI gate is real and authoritative *for Android*: it builds a
  release APK and greps `aapt dump permissions` for `INTERNET`. iOS has no
  such permission to withhold — an iOS app can open a socket whenever it
  likes — so on that platform the guarantee rests entirely on the dependency
  gate (`flutter pub deps --no-dev`), the `HttpClient`/`Socket` source grep,
  and review. `/settings/privacy` leads with the half that is true
  everywhere ("neither the app nor anything it is built from contains code
  that opens a network connection, and an automated release check fails the
  build if that ever changes") and names Android for the OS-enforced half
  ("on Android it goes further: the app ships without network permission at
  all").
- **`/settings/privacy` covers the CSV export.** "What leaves this device" is
  now "only files you save yourself, through the save dialog", and it
  distinguishes the encrypted, passphrase-protected backup from the plain
  CSV that `/settings/export` writes ("treat one like a printout"). See
  [security/THREAT_MODEL.md](security/THREAT_MODEL.md) §4.5.
- **`/settings/reset` describes what a reset actually does.** It used to say
  the archived data file's "key is destroyed, so the archive becomes
  permanently unreadable". `StartupService.startFreshFromRecovery`
  deliberately *retains* a copy of the key under the archive's label before
  destroying the live entry — the right behaviour, because a regretted reset
  should be recoverable — so the screen now says the key is kept with the
  archive, that the old workspace can still be recovered, and that this is
  **not** a way to erase it from the device. See
  [security/THREAT_MODEL.md](security/THREAT_MODEL.md) §3.2.
- **There is still no "erase this workspace permanently".** Reset archives
  and retains; recovery's start-fresh archives and retains. Nothing in the
  app destroys an old workspace, and after a reset the archive is only
  offered again by `/recovery`, which appears solely when no live workspace
  exists. An owner who resets *in order to* wipe the device is not served by
  either flow — the honest completion of `/settings/reset` is a second,
  separate, typed-confirmation "erase the archives" action. Not built.
- **No app lock and no `FLAG_SECURE`.** An unlocked phone in someone else's
  hands is undefended, and screenshots and app-switcher thumbnails are
  unrestricted. Both are deliberate v1 decisions (design §12.18, §13), both
  are worth an explicit "still true at ship" before submitting. See
  [security/THREAT_MODEL.md](security/THREAT_MODEL.md) §4.1–4.2.
- **Accessibility pass** — screen reader labels, 200 % text scale, contrast.
  Individual screens are built for it and some tests assert it; there has been
  no end-to-end pass.
- **Interrupted restore has a route back** (fixed): if the process dies
  mid-swap, bootstrap finds the parked workspace before it can conclude
  "fresh install", never rotates a key while recoverable ciphertext is on
  disk, and `/recovery` offers to put the workspace back. What remains open
  is the crossed case — a live database that cannot be unlocked *and*
  archives on disk: the screen reports the copies but cannot offer to swap
  one in, because recovery refuses to act while a live file exists. See §7.3
  of [gates-2-3-design.md](architecture/gates-2-3-design.md).
- **Sell-outs no longer bias forecasts downward** (fixed in forecast method
  v2; the method is now at v3): a sell-out is treated as a lower bound on
  demand, so it can only raise the estimate. What remains open is that the
  size of the correction is a floor, not a model — when every past event sold
  out, the app says outright that real demand is unknown and plans for the
  busiest day rather than guessing beyond it. See
  [architecture/forecasting.md](architecture/forecasting.md) §4.

### 6.3 Never done on real hardware

- **Latency and memory on a physical device.** Gate 1's remaining half.
  The encrypted backup (Argon2id at 19 MiB × 3 iterations) is the one to
  watch — it is deliberately expensive and has never been timed on a phone.
- **Recovery drill.** Make a backup, delete the app, reinstall, restore.
  Automated tests cover the round trip and every rollback phase; no human has
  done it end to end, and it is the only migration path that exists (see
  [security/THREAT_MODEL.md](security/THREAT_MODEL.md) §4.4).
- **Physical Android device** — only the emulator so far. An emulator's
  Keystore is software-backed, so hardware-backed key storage is unproven on
  both platforms (the iOS Simulator has no Secure Enclave either).
- **iOS Data Protection in force.** `integration_test/device_encryption_test.dart`
  reads back the class iOS actually applied, but the Simulator does not
  enforce protection classes at all — this assertion only means something on
  a real device.
