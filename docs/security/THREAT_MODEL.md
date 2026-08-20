# Threat model

Loadout is a single-owner, offline app. It holds one person's business records — what she sells,
what she brings, what actually went, and now what it costs — on one phone, with no account, no
server, and no network permission on Android. That shape decides everything below: there is no
attacker on the wire, because there is no wire.

This document is the authority for the privacy claims the app makes on `/settings/privacy` and
for the "Privacy (threat model)" notes in
`lib/features/catalog/application/barcode_scan_service.dart` and
`lib/features/recipes/application/recipe_ocr_service.dart`. Every claim below names the file that
implements it. Where something is asserted but not proven, it says so.

Related: design [gates-2-3-design.md](../architecture/gates-2-3-design.md) §7 (key lifecycle,
open path, startup machine), §8 (backup/restore), §10 (diagnostics and platform hardening);
[ADR 0001](../adr/0001-authoritative-deterministic-core.md).

---

## 1. Assets

| Asset | Where it lives | What it is worth |
|---|---|---|
| Workspace database | `support/db/loadout.db` (+ `-wal`, `-shm`) — `lib/infrastructure/files/loadout_paths.dart` | Everything: item names, counts, prices, events, attendance, closeouts, recipes, forecasts, notes |
| Database key | Platform secure store, entry `loadout.db_key.v1` — `lib/infrastructure/security/key_manager.dart` | The database, in one 32-byte value |
| Retained keys | Same store, prefix `loadout.db_key.v1.retained.` | Opens archived/parked ciphertext left by resets and interrupted restores |
| Backup containers | Wherever the owner saved them — `lib/infrastructure/backup/backup_service_impl.dart` | A full copy of the workspace, portable, off the device |
| CSV exports | Wherever the owner saved them — `lib/features/export/` | A **plaintext** copy of items, events, one event's count, or recipes |
| Diagnostics log | `support/diag/diag.log` (+ `.log.1`) — `lib/infrastructure/diagnostics/diag_sink.dart` | Nothing, by construction (§4) |
| Scratch space | `support/scratch/<purpose>/<id>/` — `lib/infrastructure/files/scratch_space.dart` | Backup containers, restore staging, CSV files in flight |
| Camera frames and OCR text | Process memory only — `ios/Runner/RecipeOcrChannel.swift`, `ios/Runner/BarcodeScanChannel.swift` | A photographed recipe; a scanned barcode |

Parked and orphaned ciphertext (`db/loadout.db.pre-restore`, `db/orphaned-<utcstamp>.db`) is the
workspace database under an older or retained key, and is treated as the same asset.

## 2. Adversaries

1. **Someone holding the unlocked phone.** The owner's phone, handed over or picked up while
   unlocked. **Not defended against** — see §5.
2. **Someone holding the locked phone.** Defended: the database key is sealed until first unlock
   after boot, and file ciphertext is useless without it.
3. **A lost or stolen device, powered off.** Defended: nothing decrypts until someone unlocks the
   phone once.
4. **A malicious app on the same device.** Partially defended: app-private storage and the
   platform secure store separate Loadout from other apps. On a rooted or jailbroken device this
   separation is gone and so is the key.
5. **Someone with a backup file.** Defended only by the passphrase the owner chose. The file's
   *contents* need Argon2id + SQLCipher; the file's *manifest* is cleartext (§3.3).
6. **Cloud and OS backup channels** (iCloud, Android Auto Backup, device-to-device transfer).
   Defended: the database is excluded from all of them, and the key is non-migratable.
7. **A future untrusted local model** (Gate 4 FunctionGemma, Gate 5 OCR). Structurally defended
   by ADR 0001: generated values reach records only as validated, approved commands. Nothing
   AI-generated writes today because nothing AI-generated exists today.

Explicitly **out of scope**: a network attacker (there is no runtime network), a malicious
server (there is no server), another user of the same workspace (there is exactly one owner), and
a physical attacker with chip-off/forensic hardware against a powered-on device.

---

## 3. What is protected, and how

### 3.1 The database at rest — SQLCipher with a device-bound key

Every byte of the workspace is SQLCipher-encrypted. `lib/infrastructure/db/open_database.dart`
opens it with a raw 32-byte key (`PRAGMA key = "x'<64 hex>'"`), which skips SQLCipher's internal
KDF, and keeps SQLCipher 4 defaults: **AES-256-CBC with a per-page HMAC-SHA512**. WAL pages are
encrypted too, and `temp_store = MEMORY` keeps spill pages out of files.

Two guards run on **every** connection, in this order, before anything else touches the file:

- **Cipher-presence guard.** `PRAGMA cipher_version` must answer. If the pubspec
  `hooks.user_defines.sqlite3.source: sqlcipher` block were ever misconfigured and plain SQLite
  loaded, the app throws `StateError('SQLCipher not linked; refusing plain SQLite')` and refuses
  to run rather than silently writing plaintext. A cipher-missing bootstrap failure rethrows out
  of `main` on purpose (`lib/main.dart`).
- **Wrong-key check.** `SELECT count(*) FROM sqlite_master` fails with `SqliteException` code 26
  on a key mismatch; `isWrongKeyError` classifies it, and the startup machine routes to
  `/recovery` instead of touching the file.

CI proves the dependency graph cannot smuggle in a second, unencrypted SQLite:
`.github/workflows/ci.yml` fails on `sqlite3_flutter_libs`, `sqlcipher_flutter_libs`,
`drift_flutter` or `sqflite` in `pubspec.lock`, and asserts the `source: sqlcipher` hook is
present. `test/db/cipher_smoke_test.dart` pins that a keyed file is unreadable without its key on
the host; `integration_test/device_encryption_test.dart` pins the same on a real device, plus
that the file carries neither the plain SQLite header nor a canary string.

### 3.2 The key — platform secure store, `first_unlock_this_device`

`lib/infrastructure/security/key_manager.dart`: 32 bytes from `Random.secure()` (the platform
CSPRNG), hex-encoded into `flutter_secure_storage` under `loadout.db_key.v1`.

- **iOS:** `KeychainAccessibility.first_unlock_this_device`. Three consequences, all deliberate.
  Background writes keep working after the screen re-locks (a `Complete` class would revoke file
  handles mid-WAL-write). The key stays sealed on a stolen device that has not been unlocked
  since boot. And `ThisDevice` makes the key **non-migratable**: it never enters iCloud Keychain
  and never rides a device transfer.
- **Android:** Keystore-wrapped AES-GCM encrypted preferences — in `flutter_secure_storage` v11
  this is the package's only Android backend. `resetOnError: false`, because silently erasing the
  key on a transient Keystore error would destroy the workspace; a broken key must surface as
  `/recovery`, never as a wipe.

The key never appears in a log, an export, a CSV, a backup manifest, or the database itself.
`destroyDatabaseKey()` is reachable only from workspace reset and recovery's start-fresh — and
both go through the same `StartupService.startFreshFromRecovery`, which archives the ciphertext
(`db/orphaned-<utcstamp>.db`, never deleted) and **retains a copy of the key** under
`loadout.db_key.v1.retained.<label>` before destroying the live entry. Archiving a file without
its key destroys the data as surely as deleting it, and a retained key nobody can enumerate is as
good as no key at all — hence `retainedKeyLabels()`.

> **Known discrepancy between behaviour and in-app copy.** `/settings/reset` tells the owner:
> *"The encrypted data file is kept in an archive on this device — it is never deleted — but its
> key is destroyed, so the archive becomes permanently unreadable."* Only the **live** key entry
> is destroyed; `startFreshFromRecovery` retains a copy under the archive's label first, on
> purpose, so a reset the owner regrets is not unrecoverable. The archive is therefore **not**
> permanently unreadable, and a reset is **not** a secure erase of the old workspace. The
> behaviour is the right one; the sentence is wrong and should be corrected
> (`lib/features/settings/presentation/workspace_reset_screen.dart` — a code change, out of
> scope here).

**iOS file protection** is the platform default,
`NSFileProtectionCompleteUntilFirstUserAuthentication`, matching the Keychain class.
`ios/Runner/Runner.entitlements` is deliberately empty: the
`com.apple.developer.default-data-protection` entitlement exists to *raise* the default, and
requesting the weaker value makes it unprovisionable. Because it is a default rather than a
declaration, it is verified at runtime against a real file on a real device by
`integration_test/device_encryption_test.dart`, not asserted in a build setting.

### 3.3 Backups — Argon2id over a standalone SQLCipher payload

`lib/infrastructure/backup/backup_service_impl.dart`. A backup is one file,
`loadout-backup-<yyyymmdd>-<hhmmss>.loadout`: a STORED (uncompressed) zip of a cleartext
`manifest.json` and a `payload.db` that is itself a standalone SQLCipher-4 database.

- The payload is produced from the **live connection** with `sqlcipher_export` into an
  `ATTACH`ed file under the export key. Plaintext never touches disk at any point.
- `exportKey = Argon2id(passphrase, 16-byte salt)`, `DartArgon2id` from `package:cryptography`.
  Production cost parameters: **19 456 KiB memory, 3 iterations, parallelism 1, 32-byte output**
  (`Argon2Cost.production`). The salt is fresh per backup from `Random.secure()`.
- The parameters are recorded in the manifest so future versions can raise costs without
  breaking old files. On restore they are read from the manifest but **bounds-checked** first
  (hashLength == 32, memory 8 KiB..1 GiB, iterations 1..64, parallelism 1..16) so a hostile
  manifest cannot turn the KDF into a memory bomb.
- SQLCipher's per-page HMAC-SHA512 is the payload's integrity and authentication. Restore runs
  `PRAGMA cipher_integrity_check` (whole-file HMAC sweep) then `PRAGMA integrity_check`, then a
  set of domain invariants — foreign keys, movement sign-per-kind, reversal pairing, closeout
  arithmetic, recipe-cycle detection — before anything touches the live database.
- Manifest tampering can only cause a *refused* restore, never a corrupted import: altered KDF
  parameters derive a wrong key and fail the key-check.

**What the manifest leaks.** `manifest.json` is cleartext by design (so `describeBackup` can show
the owner what a file is without asking for the passphrase). Anyone holding a backup file learns:
the app version, the schema version, the UTC creation timestamp, and the **row counts** for
movements, items and events. No names, quantities, prices or dates from the data itself. That is
a deliberate trade and it is worth knowing before mailing a backup to yourself.

**Restore is atomic, and never deletes.** The live workspace is *renamed* aside to
`db/loadout.db.pre-restore`, the payload is re-encrypted under the device key into
`db/loadout.db.new`, and only then renamed into place. At every instant exactly one openable
authoritative database exists. A failure at any stage rolls back. A process death mid-swap leaves
recoverable ciphertext, which the startup machine finds *before* it may conclude "fresh install",
and it never rotates or destroys a key while such ciphertext exists (design §7.3).

### 3.4 No network, and no OS backup channel

- **Android has no `INTERNET` permission in the shipped artifact.** This is enforced where it
  counts: CI builds a **release APK** and runs `aapt dump permissions` over it, failing if
  `INTERNET` appears. Debug and profile builds deliberately carry the permission so the Dart VM
  service can attach, which is exactly why a source grep is not the gate. CI additionally fails
  on network-capable packages in the `--no-dev` dependency graph and on `HttpClient` or
  `Socket.connect` anywhere in `lib/`.
- **Android backups are off.** `android:allowBackup="false"`, `android:fullBackupContent="false"`,
  and `android/app/src/main/res/xml/data_extraction_rules.xml` excludes every domain (`root`,
  `file`, `database`, `sharedpref`, `external`) from **both** `<cloud-backup>` and
  `<device-transfer>`. CI asserts the manifest attributes are present.
- **iOS excludes the data from iCloud.** Bootstrap sets `NSURLIsExcludedFromBackupKey` on the
  `db/` and `scratch/` directories through a MethodChannel in `ios/Runner/AppDelegate.swift`
  (`lib/infrastructure/files/ios_backup_exclusion.dart`, called from
  `lib/infrastructure/startup/startup_service.dart`). The call is best-effort: a failure is
  reported as `false` and never throws, because bootstrap must not die on a resource-attribute
  hiccup. Combined with the non-migratable Keychain class, a restored iCloud backup on a new
  phone contains neither the database nor the key.
- Files live in the app-support directory on both platforms — never `Documents`, never external
  storage. `UIFileSharingEnabled` is absent; `FlutterDeepLinkingEnabled` is `false`.

**iOS caveat, stated plainly:** iOS has no equivalent of Android's `INTERNET` permission. The
"no network permission" claim is verified for Android only. On iOS the guarantee rests on the
dependency and source gates above, not on anything the OS enforces — see
[../RELEASE.md](../RELEASE.md) §6.

### 3.5 Diagnostics that physically cannot carry content

`lib/core/diagnostics/diag.dart` is the whole argument:

```dart
void event(DiagEvent event, {int? count, Duration? elapsed,
                             String? errorType, int? schemaVersion});
```

There is no free-text parameter. `DiagEvent` is a closed enum. A log line therefore cannot carry
an item name, a quantity, an event name, recipe text, a file path, SQL, or an exception message —
not by policy, but because no API accepts them. `errorType` is defended in depth by
`RingFileDiag.sanitizeErrorType`, which strips everything outside `[A-Za-z0-9_$<>]` and caps the
result at 64 characters, so even a caller passing something other than `runtimeType.toString()`
cannot smuggle content through. The file is a 256 KB rotating plaintext log plus a 512-line
in-memory ring; plaintext is acceptable precisely because the contents are content-free.
`print`/`debugPrint` are banned by the `avoid_print` lint and a CI grep. The only way logs leave
the device is the owner saving them from `/settings/diagnostics`.

### 3.6 Camera and OCR stay in the OS

Both are native, iOS-only today, behind MethodChannels (`ios/Runner/BarcodeScanChannel.swift`,
`ios/Runner/RecipeOcrChannel.swift`). No third-party camera or ML package is in `pubspec.yaml`.
Recognition models live inside the OS (Apple Vision, revision 3). Frames stay in the camera
pipeline; the decoded barcode payload and recognized text lines stay in process memory; nothing
is written to disk and nothing reaches the diagnostics log — failures surface as stable channel
*codes*, never payloads. A barcode is meaningless to the app until the owner tells it which of
her items it is (`items.barcode`, schema v6): recognition, not lookup.

### 3.7 Scratch hygiene

Everything ephemeral — backup containers awaiting a save dialog, restore staging, CSV files in
flight — lives under `support/scratch/<purpose>/<id>/`, is disposed in a `finally` at each call
site, and is swept on every app start and on `AppLifecycleState.paused`. Live sessions are
excluded from the sweep on purpose: the OS pauses the app whenever a system file picker takes the
screen, which is the exact moment a container is sitting in scratch waiting to be copied out.
Anything left behind by a previous run is swept, because the live-session set starts empty each
launch.

---

## 4. What is NOT protected

This section matters more than the one above. None of the following is a bug; each is a decision
with a cost the owner should know about.

### 4.1 An unlocked phone in someone else's hands

**There is no app lock.** No PIN, no biometric re-prompt, nothing (design §12.18; an optional
biometric re-prompt is deferred to Gate 6, §13). Once the phone is unlocked, Loadout is open, and
everything in it is readable and editable by whoever is holding it. Encryption at rest defends
against a *lost device*, not against a *borrowed* one. The onboarding screen's device-lock
advisory card — "Loadout's data is encrypted on this device. Protect it with your phone's screen
lock." — is the entire mitigation, and it is advice, not enforcement.

### 4.2 Screenshots and app-switcher thumbnails

`FLAG_SECURE` is not set on Android and there is no iOS snapshot blanking; grep confirms neither
appears anywhere in `lib/`, `android/` or `ios/`. Consequences:

- Anyone can screenshot any screen, including a full closeout with prices.
- The OS writes an app-switcher thumbnail of the last visible screen to disk. That thumbnail is
  in the OS's storage, not Loadout's, and is therefore **not** covered by SQLCipher, by
  `allowBackup="false"`, or by the iCloud exclusion.
- Screen recording and remote-assist screen sharing capture everything.

A screenshot/`FLAG_SECURE` policy is explicitly deferred to Gate 6 (design §13).

### 4.3 A forgotten backup passphrase is the end of that backup

Argon2id is doing exactly what it is for. There is no recovery question, no escrow, no hint, no
reset, and no back door — the passphrase is not stored anywhere, so nobody, including the owner,
can recover the file's contents without it. The backup screen says "cannot be recovered" before
the file is written; that sentence is literally true.

### 4.4 A new phone means total data loss unless a backup file exists

This is the single most likely way for the owner to lose everything, and it follows directly from
the protections in §3:

- The database key is `first_unlock_this_device` on iOS and Keystore-wrapped on Android. It is
  **non-migratable by design** — it does not ride iCloud Keychain, Android Auto Backup, or a
  device-to-device transfer.
- The database file is excluded from every OS backup and transfer channel on both platforms.

So a new phone starts as a fresh install. **The `.loadout` backup file is the only migration
path that exists**, and it needs both the file and its passphrase. A phone that dies before a
backup is made takes the workspace with it. No amount of "I had iCloud on" changes this.

The app currently nudges for backups in-app only (no notification permission), and **no human has
yet done a full backup → delete → reinstall → restore drill on a real device** — automated tests
cover the round trip and the rollback paths, but see [../RELEASE.md](../RELEASE.md) §6.

### 4.5 Plaintext CSV export

`/settings/export` writes four **unencrypted** CSV documents (items, events, one event's count,
recipes) through the same save-dialog-only egress as backups. This is the feature working as
intended — a backup file is useless to a treasurer — but it is a plaintext copy of the workspace
leaving the device with no passphrase on it, and it is protected only by wherever the owner puts
it. Two things deliberately never leave with it: **internal ULIDs** (the count export keys rows by
item name) and **barcode payloads** (the items export says whether an item has one, never what it
is).

> **Known stale in-app copy:** `/settings/privacy` still says "What leaves this device:
> Nothing — except backup files you explicitly save through the save dialog." The CSV export
> post-dates that sentence. This document is correct; the screen needs updating.
> (`lib/features/settings/presentation/privacy_screen.dart` — a code change, out of scope here.)

### 4.6 A rooted, jailbroken, or forensically imaged live device

The Keystore/Keychain boundary is the OS's, not Loadout's. Root breaks it. And because the key is
available to the app from first unlock after boot, an attacker who compromises a *running,
already-unlocked* device can obtain it. `cipher_memory_security` is deliberately off — it costs
CPU for no coverage against an attacker who can already read process memory.

### 4.7 Metadata that is not encrypted

The presence and size of `support/db/loadout.db`, the timestamps and sizes of backup files, the
diagnostics log's event codes and timings, and the backup manifest's row counts (§3.3) are all
visible without any key. None of it names anything; all of it says roughly how much there is and
when it happened.

### 4.8 Not the app's problem, and not solved by it

App integrity and tamper detection (a modified build is a different app), supply-chain integrity
of the Flutter/Dart toolchain and the SQLCipher build produced by the pubspec hook, and the
security of whatever cloud drive the owner chooses to put a backup file into.

---

## 5. Verified, asserted, and unproven

Docs credibility depends on this table being honest.

| Claim | Status |
|---|---|
| Release APK carries no `INTERNET` permission | **Verified in CI** on every push, against the built release artifact |
| No second native SQLite; SQLCipher hook configured | **Verified in CI** |
| Android backup/data-extraction excludes | **Verified in CI** (manifest attributes) — the *effect* is asserted from the platform contract, not tested |
| Keyed database unreadable without its key | **Verified**, host (`test/db/cipher_smoke_test.dart`) and device (`integration_test/device_encryption_test.dart`) |
| Argon2id implementation correctness | **Verified** against RFC 9106 vectors (`test/backup/argon2_test.dart`) |
| Backup tamper resistance and restore rollback | **Verified** (`test/backup/backup_tamper_test.dart`, `restore_rollback_test.dart`) |
| Diagnostics cannot carry content | **Structural** — no API accepts free text; line format pinned by test |
| iOS `NSURLIsExcludedFromBackupKey` applied | **Asserted** — best-effort channel call; return value is not surfaced or tested in CI |
| iOS file protection class in force | **Device-verified only**, by the integration test, on a real device; the Simulator does not enforce protection classes at all |
| Hardware-backed key storage | **Unproven.** Emulator Keystore is software-backed; the iOS Simulator has no Secure Enclave. Needs a physical device |
| "No network permission" on iOS | **Not applicable / unverifiable.** iOS has no such permission; the claim rests on the dependency and source gates only |
| Backup → wipe → restore on a real device | **Never done by a human.** Automated round-trip only |
