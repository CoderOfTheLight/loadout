# Loadout — Gate 1 AI & OCR Decision Document

**Prepared:** 12 August 2026 · **For:** owner decision · **Scope:** Gate 1 ("prove model, encrypted database, OCR, offline behavior, latency, memory on devices"), and by extension whether Gates 4–5 are worth scheduling.

Binding constraints read from `PRODUCT_PLAN.md` and `docs/security/THREAT_MODEL.md`: Android 10/API 29+, iOS 16+, ARM64; no account, cloud sync, analytics, or runtime network; recipe OCR and FunctionGemma remain local and always have form fallbacks; no AI-dependent feature is release-ready until Gate 1 passes.

---

## 1. The recommended stack, and the recommendation about whether to build it

### 1.1 The stack

**Model artifact:** FunctionGemma 270M (`google/functiongemma-270m-it`), converted to `.litertlm` at `dynamic_int8`, eventually fine-tuned on ~1,000 synthetic examples (~100 per typed command).
**Runtime:** `flutter_gemma` 1.5.2 + `flutter_gemma_litertlm` 1.3.1 (LiteRT-LM 0.14.0), **CPU backend on iOS**, tool-calling mode.
**Delivery:** bundled as a native app-bundle resource via `FlutterGemma.installModel(.fromBundled(...))`, `mmap`'d in place from the read-only bundle. No runtime fetch, no user import, no copy to Documents.
**OCR:** Apple `VNRecognizeTextRequest` (revision 3) behind a ~120-line custom Swift `MethodChannel` on iOS; ML Kit *bundled* text recognition on Android at Gate 5, with `tools:node="remove"` on `INTERNET`/`ACCESS_NETWORK_STATE` and a CI assertion that those directives are still present.

**What it costs:**

- **App size:** +~285 MB installed on iOS (~240 MB compressed on Play; quantized weights compress to only ~92–95%). That trips the >200 MB mobile-data warning on both stores and means a full ~285 MB re-download on every app update. OCR adds **0 bytes** on iOS and **+13.8 MB** on Android (measured, arm64 release).
- **RAM:** Google's own figure is ~550 MB peak RSS for this model at `dynamic_int8` on a Samsung S25 Ultra. If weights stay `mmap`'d clean, iOS `phys_footprint` (the number jetsam enforces) should land far below that — but **that is an assumption, not a measurement**, and iOS 16 admits 2–3 GB devices where the footprint budget is roughly 700 MB–1.4 GB.
- **Worst-case failure mode:** you ship ~285 MB of weights and the feature is slower than the form it replaces. The single published measurement of *this exact model* on *this exact device class* — GitHub issue [DenisovAV/flutter_gemma#307](https://github.com/DenisovAV/flutter_gemma/issues/307), open since 2026-06-06 — reports **~10 s per call on an iPhone 13 CPU, drifting 5 s→10 s under thermal load, with both GPU paths broken** (int8 → `<pad>` spam, fp16 → `EXC_RESOURCE` OOM at 2,348 MB despite the memory entitlements being present in the signed binary). A second open issue, [#405](https://github.com/DenisovAV/flutter_gemma/issues/405) filed 2026-08-03 against the *current* stack, reports a **permanent unrecoverable native hang mid-prefill on iOS**.

### 1.2 The recommendation

**Split the gate. Do the OCR half now. Do not build the model half — spike it to kill it.**

**OCR: proceed, this week.** Apple Vision costs zero bytes, zero network, zero third-party code, and zero license question. `VNRecognizeTextRequestRevision3` is `API_AVAILABLE(ios(16.0))` — every device in your support matrix. The models live in the OS (`/System/Library/PrivateFrameworks/TextRecognition.framework`, ~91 MB of OS assets, ANE-precompiled). It is roughly 120 lines of Swift and it de-risks Gate 5 for about two days of work. There is no argument against it.

**Model: do not schedule Gates 4–5 yet.** Run a **3-day kill spike** using an *off-the-shelf* FunctionGemma `.litertlm` build — not a fine-tune — on the oldest iPhone you intend to support. On current evidence I would put the odds of that spike passing at well under even, and the cost of finding out is three days versus the two-to-four weeks that fine-tuning, conversion, an eval harness, packaging, and legal review would cost before you learn the same thing.

The defence, in the order the facts bite:

1. **The one relevant measurement in existence is a failure.** Issue #307 is your exact model, your exact runtime path, your exact first device class. It is open, the maintainer's only reply was "did you read my article / try my notebooks," the reporter said "I'll take a quick look" on 2026-06-08 and never returned. That is an unresolved report, not a debunked one. It was filed against flutter_gemma 0.16.4 and a hand-built bundle, so it may well be stale — but nobody has published a number that supersedes it.
2. **The reported cause is structural, not a bad build.** A ~700-token tool schema is re-prefilled on every `createChat(tools:)`, and there is **no supported prefix/KV-cache reuse API**. Your outputs are a few dozen tokens; your prefill is fixed and large. That ratio is the worst possible one for this architecture, and it will not improve by picking a different quantization.
3. **Constrained decoding is not reachable from Dart, and the part that *is* wired up is weaker than assumed.** I checked the published dartdoc index for `flutter_gemma` 1.5.2 directly: 2,019 symbols, and a case-insensitive search for `constrain|schema|grammar|structur` returns only `inputSchema`, `FilterSchema`, and JSON *parsing* helpers. No constraint API. Feature request [#195](https://github.com/DenisovAV/flutter_gemma/issues/195) has been open since 2026-03-11. And LiteRT-LM's own doc says the tool-calling mode constrains "the function call **string** … to follow the function-calling **syntax** of the model" — **syntax, not argument schema**. So the strongest claim available today is "the envelope is well-formed"; validating argument types and enums remains entirely your Dart layer's job, exactly as it is without a model.
4. **The model needs work before it is even measurable.** Google's own model card: FunctionGemma "is not intended for use as a direct dialogue model, and is designed to be highly performant after further fine-tuning." Base BFCL is 61.6% simple / 39.0% parallel. The 85% figure is *after* fine-tuning. So the honest build order is: synthesize ~1,000 examples → fine-tune → convert with `ai-edge-torch` → get stop tokens right → measure. That is weeks of work before the first real latency number.
5. **The licence is not free.** FunctionGemma carries the **Gemma Terms of Use** (verified: HF `license: gemma`, `gated: manual`), not Apache 2.0 — Gemma 4 was relicensed, FunctionGemma was not. Bundling weights is a "Distribution," which obliges you to ship a NOTICE file, pass the Agreement to recipients, and carry Google's Prohibited Use Policy as an **enforceable provision in your EULA**. Section 3.2 also reserves Google the right to "restrict (remotely or otherwise) usage." Practically unenforceable against a file in your binary — but it is a clause you would be accepting for a product whose entire thesis is "no runtime network."
6. **The plan already says this is optional.** "Recipe OCR and FunctionGemma remain local and always have form fallbacks." Gate 3 completes every workflow without AI. The app is complete and useful with Gates 2, 3 and 6 alone. Gate 4 exists to make a fast thing faster — and if it isn't faster than the form, it is negative value: 285 MB, a wait, and *then* the form.
7. **The runtime is one person.** `flutter_gemma` is a single maintainer, ~24k downloads/month, releasing every 2–4 days, trailing upstream LiteRT-LM by two minors (pins 0.14.0; upstream shipped v0.16.0 on 2026-08-11), and its iOS/Android native binaries are **downloaded at build time from that maintainer's personal GitHub releases** (SHA256-pinned in the hook, no documented offline override). That is a supply-chain entry for your threat model and a genuine bus-factor risk to sit under a shipping product.

**If the spike passes, the stack above is correct and you should build it.** If it fails, the right move is: ship the deterministic app, keep the AI branch in a spike directory, and re-run the same 3-day spike once a quarter. LiteRT-LM's iOS story is moving fast (Swift API landed ~May 2026, five releases since June); this is a "not yet," not a "never."

---

## 2. Comparison of credible alternatives

### 2.1 Model artifacts

| Model | Disk (quantized) | Peak RAM | iOS + Android | Constrained output | License | Offline-safe |
|---|---|---|---|---|---|---|
| **FunctionGemma 270M** (rec.) | **288 MB** `.litertlm` int8 · 253 MB Q4_K_M GGUF · 291 MB Q8_0 GGUF | **~550 MB** measured (S25 Ultra, vendor) | ✅ both, via flutter_gemma | Tool-call **syntax** only via LiteRT-LM; full JSON Schema via llama.cpp GBNF | **Gemma ToU** — commercial OK, NOTICE + EULA obligations, not OSI | ✅ fully bundleable |
| **LFM2.5-350M** | not verified (GGUF/ONNX/MLX exist) | not verified | via GGUF runtimes only | GBNF if run on llama.cpp | `lfm1.0`, **$10M revenue cap** (secondary sources only) | ✅ bundleable |
| **LFM2.5-230M** | not verified | not verified | via GGUF runtimes only | GBNF if run on llama.cpp | `lfm1.0` (unverified text) | ✅ bundleable |
| **Qwen3-0.6B** | 484 MB Q4_K_M · 805 MB Q8_0 | not verified | via GGUF runtimes | GBNF | Apache 2.0 *(not re-verified for 0.6B)* | ✅ bundleable |
| **Gemma 4 E2B** | **2,583 MB** `.litertlm` | 607 MB CPU / 1,450 MB GPU claimed on iPhone 17 Pro *(figures don't reconcile with file size — do not quote)* | ✅ both | tool-call syntax | **Apache 2.0** | ✅ but unbundleable in practice |
| **Apple Foundation Models** (`SystemLanguageModel`) | **0 bytes** | OS-managed | ❌ iOS 26+ / A17 Pro+ only | ✅ **native guided generation (`@Generable`)** — the best structured-output story available | Apple platform SDK | ⚠️ **policy question** — OS downloads the assets; app never makes a request |

The licence win and the size win are in different models: Gemma 4 is Apache 2.0 but nothing exists below E2B (2.6 GB); FunctionGemma is the right size but carries the Gemma ToU. Apple Foundation Models is strictly better than both on size, structured output and licence — and excluded by your iOS 16 floor for most of your fleet.

### 2.2 Runtimes

| Runtime | Version / date | iOS + Android | JSON-Schema forced output | Model supply | License | Offline-safe |
|---|---|---|---|---|---|---|
| **flutter_gemma 1.5.2 + _litertlm 1.3.1** (rec.) | 2026-08-04 / 2026-07-28 | ✅ iOS 16.0, Android minSdk 24 (arm64-only for `.litertlm`) | ❌ **not exposed to Dart** (verified: 0 constraint symbols in 2,019-symbol dartdoc index); tool-call *syntax* auto-enabled when tools are passed | `.fromBundled` / `.fromAsset` / `.fromFile` / opt-in `.fromNetwork` | MIT (wrapper); LiteRT-LM Apache 2.0 | ✅ at runtime · ⚠️ **build-time** native-binary download from maintainer's GitHub releases |
| **llamadart 0.8.19** | 2026-08-10 | ⚠️ **iOS 16.4+** (above your 16.0 floor); Android arm64/x64 | ✅ **yes** — `LlamaStructuredOutput.jsonSchema` → GBNF, but **GGUF/llama.cpp path only**; explicitly not on `.litertlm` | local path / assets; `hf://` scheme downloads — do not use | MIT | ✅ best-documented: `llamadart_native_path` vendoring, "no network required at runtime" |
| **flutter_gemma_mediapipe 1.0.4** | 2026-07-07 | ✅ + Android x86_64/armeabi-v7a | ❌ none at all; function calls recovered by Dart regex parsers | bundle-based | MIT wrapper; Google first-party binaries | ✅ |
| **fllama** | 2026-06-09 | ✅ | ✅ GBNF | `modelPath` | 🚫 **GPL v2** dual-licence — requires disclosing your app source | ✅ |
| **ONNX Runtime GenAI** | v0.15.2, 2026-08-07 | ⚠️ no real Flutter binding exists | ✅ json_schema/regex/lark — but `USE_GUIDANCE` is **OFF by default** | n/a | MIT | ⚠️ `ENABLE_TELEMETRY` defaults **ON** |
| **cactus** | pub 1.3.0, 2025-12-19; Flutter repo **archived** | ⚠️ | — | `downloadModel(slug)` runtime fetch | source-available, revenue-capped | 🚫 telemetry on by default; OpenRouter cloud fallback |
| **MLC-LLM** | no Flutter binding | ❌ | — | — | Apache 2.0 | — |

### 2.3 OCR engines

| Engine | Bytes in app | iOS | Android | Confidence granularity | License | Offline-safe |
|---|---|---|---|---|---|---|
| **Apple Vision, custom channel** (rec. iOS) | **0** | ✅ rev3 = iOS 16+ | ❌ | line only; **3 discrete values observed** (0.3/0.5/1.0) + up to 10 ranked candidates + per-range bounding boxes | Apple system framework | ✅ |
| **ML Kit bundled** (`google_mlkit_text_recognition` 0.16.0) | **+13.79 MB** measured (arm64 release) | 🚫 **binary links `https://play.googleapis.com/log`, GTMSessionFetcher, GoogleDataTransport; no opt-out documented** | ✅ (rec. Android) | **per symbol / element / line — best available**, Android only; iOS headers expose no `confidence` at all | wrapper MIT; **SDK proprietary (ML Kit ToS)** | ⚠️ **adds `INTERNET` to merged manifest — proven**; removable with `tools:node="remove"`, uploader components remain |
| **Tesseract** (`flutter_tesseract_ocr` 0.4.31) | ~3.5 MB native + 4.1 MB `eng` fast | ⚠️ via **archived** SwiftyTesseract (last push 2022) | ✅ | **per word, continuous** (`x_wconf` via hOCR) — best API | BSD-3 wrapper / Apache-2.0 engine | ✅ but ships an **unversioned, unchecksummed prebuilt AAR** |
| **PaddleOCR / RapidOCR via ONNX** | 10–21 MB | custom work | custom work | per-character logits if you decode yourself | Apache-2.0 + MIT | ✅ |

**ML Kit on iOS is disqualified by your own release contract**, not by accuracy. This is the strongest single finding in the sweep and it is backed by a symbol dump of the shipped `MLKitCommon.framework` arm64 slice.

---

## 3. Gate 1 spike plan

The design principle for every threshold: **the AI path's only competitor is the plain form that already exists.** At a market stall — standing, one hand, sunlight, a queue, intermittent attention — a slower or less reliable AI path is worse than no AI path, because it costs 285 MB *and* a wait *and then* the form. So every number below is set relative to the form, on the worst device, not the best.

### Step 0 — Measure the baseline first (half a day)

Before touching a model, time the existing flow: "add 2 cases of tortillas" via the plain form, one-handed, on the target device, 10 trials, median. Expect 8–12 s. **Everything below is scored against that number.** If you skip this you have no denominator.

### Step 1 — The kill test (2 days, no fine-tuning)

Bundle the **ungated off-the-shelf** `sasha-denisov/function-gemma-270M-it` `.litertlm` (284.4 MB) as a native bundle resource. Wire `flutter_gemma` 1.5.2 + `flutter_gemma_litertlm` 1.3.1, CPU backend, `ToolChoice.required`, with your **real ~10-command tool schema** — not a three-function toy. Run on the **oldest iPhone you intend to support**, in release mode, on device, force-quit between cold runs.

You are not measuring quality here. You are measuring whether the physics work. A base model will route badly; that is expected and irrelevant to this step.

| # | Measurement | How | Pass | Hard kill |
|---|---|---|---|---|
| 1 | **End-to-end proposal latency** — phrase in → validated typed proposal out | `os_signpost` interval, ≥20 runs | **p50 ≤ 1.2 s, p95 ≤ 2.5 s** | **p95 > 3 s** |
| 2 | Prefill vs decode split | `getSessionMetrics()` / `litert_lm_engine_settings_enable_benchmark` | prefill < 60% of total | prefill > 80% with no cache reuse available |
| 3 | **Peak `phys_footprint`** | `task_info(TASK_VM_INFO)` | **≤ 700 MB** | > 800 MB, or any `EXC_RESOURCE` |
| 4 | `resident_size` vs `phys_footprint` gap | `mach_task_basic_info` alongside #3 | footprint stays flat while residency climbs (proves `mmap` clean-page assumption) | footprint tracks residency 1:1 |
| 5 | `os_proc_available_memory()` at idle / load / peak | direct call | never below **150 MB** | below 50 MB |
| 6 | **Cold app start delta** with model in bundle, not loaded | `flutter run --profile --trace-startup` → `timeToFirstFrameRasterizedMicros` | **≤ 50 ms delta** | any visible regression |
| 7 | Cold model load (post-reboot, cold page cache) | `os_signpost` | ≤ 3 s, and off the critical path | > 6 s |
| 8 | **Frame time during generation** | Flutter timeline / DevTools | **p95 ≤ 20 ms** (60 Hz budget is 16.7 ms) | UI jank or ANR-class stall |
| 9 | **Thermal** over a 20-proposal burst | `ProcessInfo.thermalState` | never reaches `.serious` | `.serious`, or latency drift > 2× |
| 10 | **Soak:** 200 consecutive generations | RSS sampled per iteration | growth < 10%; zero hangs; zero crashes | any #405-class permanent hang |
| 11 | **Backgrounding survival** at 5 / 30 / 300 s with model loaded | manual + device logs | app resumes | jetsam kill |
| 12 | **Low Power Mode** re-run of #1 | `isLowPowerModeEnabled` | p95 ≤ 4 s | > 6 s |
| 13 | **Airplane mode + packet capture**, full flow | manual | zero packets | any traffic |

**Justification for the two that matter most.** *Latency:* the form takes 8–12 s. The AI path spends ~4 s on input and ~2 s on the human-approval tap that ADR 0001 mandates, so anything above ~2.5 s of model time erases the advantage entirely; and at a stall with a queue, the p95 is what people remember, not the p50. *Memory:* your iOS 16 floor admits iPhone 8 (2 GB) and iPhone X / SE2 (3 GB), where the community-estimated footprint budget is roughly 700 MB–1.4 GB. A 550 MB peak on a 2 GB device is not comfortable — and a jetsam kill mid-transaction at a stall loses a movement record, which for an append-only inventory system is the one failure you cannot tolerate.

**Concrete de-risking option that falls out of #3–#5:** decouple the *AI-feature* device floor from the *app* device floor. Ship the app on iOS 16 / iPhone 8; gate the AI controller behind ≥4 GB RAM / A14+ and serve the plain form everywhere else. ADR 0001's fallback already makes this free, and it removes the entire low-end memory question from the critical path.

### Step 2 — Only if Step 1 passes: the quality gate (3–5 days)

Fine-tune on ~1,000 synthetic examples (~100 per command — the published Flutter recipe used 284 examples for 3 functions), convert via the repo's `colabs/functiongemma_to_litertlm.ipynb`, and assert in CI that **both** `<end_of_turn>` and `<start_function_response>` stop tokens are set at conversion time. Then, against a frozen 50-phrase corpus (30 in-domain, 10 adversarial phrasings, 10 out-of-domain):

| Measurement | Pass | Hard kill |
|---|---|---|
| Schema-valid proposal rate | **≥ 95%** | < 85% |
| Correct command + correct arguments | **≥ 90%** | < 80% |
| **Invented identifiers** (item IDs not in the workspace) | **0 occurrences** — not a rate | any occurrence not caught by the Dart validator |
| Correct refusal on the 10 out-of-domain phrases | ≥ 80% | < 50% |
| Enum-typed argument ever out of enum | 0 | any (settles whether tool-call constraining covers arguments) |

95% schema validity is the bar because ADR 0001 puts a human in the loop: at 1-in-20 corrections the AI path still beats the form; at 1-in-7 it does not, and the user stops using it.

### Step 3 — OCR spike, in parallel (2 days, independent of the model)

Custom Swift `MethodChannel`: `VNRecognizeTextRequest`, `revision = VNRecognizeTextRequestRevision3`, `.accurate`, image passed as **bytes** (`VNImageRequestHandler(data:)` / `(cgImage:)`) — never a temp file, per the "temporary images" threat. Two passes: `usesLanguageCorrection = false` + `topCandidates(5)` over the ingredient block, correction **on** for prose. Pre-warm the request at screen entry (~2.7 s one-time cost observed).

| Measurement | Pass | Hard kill |
|---|---|---|
| Warm recognition p50 on a 12 MP capture | ≤ 1.5 s | > 4 s |
| Peak footprint during recognition | ≤ 250 MB above idle | > 500 MB |
| **Numeric-token CER** on 30–50 real photographed recipe sources, hand-transcribed | ≤ 2% | > 8% |
| Prose CER | ≤ 5% | > 15% |
| N-best digit disagreement flags ≥ 90% of numeric errors | yes | no → the uncertainty signal doesn't work |
| iOS 16 device: `supportedRecognitionLanguagesAndReturnError:` includes `en-US` | yes | no |
| Airplane mode + packet capture during OCR | zero packets | any traffic |

**Do not use `confidence` as the corruption detector.** The sweep found it takes three discrete values (0.3 / 0.5 / 1.0) and reports catastrophic numeric errors at **1.000** — `2 1/4 cups` → `21/4 cups` (a 2.3× quantity error), `0.5 lb` → `8.51`. Use **top-N candidate disagreement on digits** as the flag, gate every numeric token through a strict grammar (`int`, `decimal`, `int space int/int`, `int/int`), show the `boundingBoxForRange:` crop next to every parsed quantity, cross-check unit plausibility, and never auto-accept a numeric field.

### Step 4 — CI and packaging assertions (half a day, do regardless)

- Release APK permission dump must still contain no `INTERNET`. Note that `flutter_gemma` pulls `background_downloader` → `androidx.work`, which adds `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`. **Decide now:** allowlist or `tools:node="remove"`.
- If ML Kit lands on Android, add a **new** CI assertion that the two `tools:node="remove"` directives are present in `android/app/src/main/AndroidManifest.xml` — a dependency bump silently re-adds `INTERNET` otherwise.
- Verify the shipped iOS `Info.plist` has **no** `NSLocalNetworkUsageDescription` / `NSBonjourServices` (they are Flutter debug VM-service artifacts, mislabelled in flutter_gemma's README as an inference requirement).
- Hermetic CI: pre-seed `~/Library/Caches/flutter_gemma/native/` plus the `.flutter_gemma_native_version` marker on a network-disabled runner, pin `flutter_gemma_litertlm` exactly, and confirm `flutter build ipa` succeeds offline.
- **Forbid in code review:** `rootBundle.load('assets/model.litertlm')` → write to Documents. It pulls 285 MB through the Dart heap, doubles disk, and puts a non-user-generated file in a backed-up location. Apple DTS has stated App Review rejects apps for this pattern. Use `lookupKey(forAsset:)` + `Bundle.main.path` and `mmap` in place. On Android set `androidResources { noCompress += listOf("litertlm", "gguf", "task") }` or `AAsset_openFileDescriptor64` returns < 0.
- Your existing target-API check: from **2026-08-31** (19 days out) new Play submissions must target API 36. Verify `android/app/build.gradle.kts` regardless of any AI decision.

---

## 4. Open questions only you can answer

1. **Do you accept the Gemma Terms of Use?** Commercial closed-source shipping is permitted, but bundling weights is a "Distribution": you must ship a NOTICE file, provide the Agreement to recipients, and carry Google's Prohibited Use Policy **as an enforceable provision in your EULA** — a policy Google can revise unilaterally. Section 3.2 also reserves Google the right to "restrict (remotely or otherwise) usage." For a product positioned on "no accounts, no network, your data is yours," accepting a licence with a remote-restriction clause is a positioning decision, not just a legal one. If the answer is no, the model half is dead today and the alternatives (LFM2.5's unverified $10M revenue cap, or a 2.6 GB Apache-2.0 Gemma 4) are worse.
2. **What is your app-size ceiling?** +285 MB is a 15–20× increase on the current binary, trips the >200 MB mobile-data warning on both stores, and forces a full re-download on every update. Is a ~300 MB market-stall app acceptable? There is no meaningful further compression available — the floor is set by Gemma's 262k-token vocabulary (the tokenizer alone is 33.4 MB), so `Q4_K_S` at 249.9 MB is as low as it goes.
3. **Is a one-time "import the model file" step acceptable UX?** All four sweeps recommend against it for the primary flow: it turns a feature into a setup ritual for users who are not LLM hobbyists, doubles disk, needs `NSURLIsExcludedFromBackupKey` handling, and — most seriously — makes the model itself attacker-controllable, which directly worsens the "malformed model output" threat you already list. Pinning a hash of the expected file is bundling with extra steps and worse UX. **My recommendation: no for users, yes as a hidden developer escape hatch during the spike.** But it is the only lever that keeps the store listing small, so it is your call.
4. **Does "the OS downloads the model, the app never makes a request" satisfy your offline stance?** This decides whether Apple's Foundation Models framework is ever admissible — zero bytes, native `@Generable` guided generation (the best structured-output story on the table), but iOS 26+ / A17 Pro+ only, and its `modelNotReady` state literally means "the OS is still downloading Apple Intelligence assets." Worth an explicit ADR, because the same question will recur for every OS-provided capability.
5. **Android OCR: which residue do you prefer?** ML Kit bundled gives per-symbol confidence (nothing else on Android does) at the cost of +13.8 MB and four permission-starved-but-present Google telemetry components in your manifest. Tesseract4Android used directly is clean on permissions and 3.5 MB, but has weaker numeric accuracy and no per-symbol confidence. Both are defensible; only you can price the threat-model entry.
6. **Bus factor.** `flutter_gemma` is one maintainer, and your iOS/Android native binaries are fetched at build time from his personal GitHub releases (SHA256-pinned, no documented offline override). Acceptable dependency for a shipping product, or do you want a vendored fork before Gate 4?
7. **If the spike fails, what's the policy?** Defer Gates 4–5 indefinitely, or re-run the same 3-day spike quarterly? I'd recommend quarterly — LiteRT-LM shipped five releases between June and August 2026 and the iOS path is visibly maturing.

---

## 5. What we could not verify

Ranked by how much a wrong guess costs. Items marked **[carried]** are the researchers' unknowns I did not independently re-check; items marked **[weak]** rest on secondary sources.

**Would change the recommendation:**

1. **Current FunctionGemma-270M latency on iOS with flutter_gemma 1.5.2 / LiteRT-LM 0.14.0.** The only figure that exists (~10 s/call, iPhone 13 CPU) is from flutter_gemma **0.16.4**, June 2026, two majors and an architecture rewrite ago, using a hand-built bundle rather than the repo's Colab pipeline. It may be materially better now. **Nothing on the web will answer this — Step 1 of the spike *is* the answer.**
2. **No published iPhone numbers for this model, at all.** Every measurement is Samsung S25 Ultra. Treat 288 MB / ~550 MB RSS / 0.3 s TTFT as an optimistic ceiling, not a prediction.
3. **Whether clean `mmap`'d bundle pages are still excluded from `phys_footprint` on iOS 26/27.** The definitive statement — footprint = dirty + compressed, `mmap`'d read-only files are clean, Apple explicitly names "training models" — is WWDC18 session 416, **eight years old**. No contradicting statement found; 2026 community measurements are consistent. **This is the load-bearing assumption of the whole delivery analysis.** Settled by spike measurement #4, in an afternoon.
4. **Whether LiteRT-LM's tool-calling constraint enforces the *argument* schema or only the call envelope.** The primary doc says "syntax," which reads as envelope-only, but the grammar-construction code was not read. Determines how much validation your Dart layer must still do. Settled empirically by spike measurement "enum-typed argument ever out of enum," or by reading `runtime/conversation/` in LiteRT-LM.
5. **Whether constrained decoding is reachable from Dart at all.** I verified the *negative* directly (0 constraint symbols in `flutter_gemma`'s 2,019-symbol dartdoc index; the C symbols `litert_lm_conversation_optional_args_set_constraint` and `…set_constraint_provider` are reportedly **[carried]** not bound in `litert_lm_bindings.dart`). What I could not verify is whether the LiteRT-LM **iOS Swift** API exposes it — its README calls Swift "Early Preview," and its Swift surface reportedly includes `ResponseFormat.json(schema:)` **[carried]**. If so, a small fork of `flutter_gemma_litertlm` binding one C call gets you real JSON-Schema enforcement.
6. **Real numeric CER for Apple Vision on actual recipe photographs.** The confidence findings come from *synthetic rendered text with synthetic blur/noise* — they demonstrate the shape of the confidence API, not accuracy. No credible current head-to-head CER benchmark of Vision vs ML Kit vs Tesseract on printed text exists. Settled by Step 3's 30–50-photo corpus. **Numeric CER is the only OCR number that matters for your gate.**

**Would change implementation, not the decision:**

7. **Whether `litert_lm_conversation_send_message_stream` blocks the calling Dart isolate.** Source comments in `litert_lm_client.dart` point both ways; the maintainer moved engine- and conversation-creation to `Isolate.run` but not generation. Settled by spike measurement #8. **[carried]**
8. **Whether the `vtool minos 26.2 → 16.0` patch on `libGemmaModelConstraintProvider` yields a working binary on a real iOS 16 device.** Patching a Mach-O's minimum-OS field does not restore APIs the library may call. Given your iOS 16 floor this is a real risk. Requires a **physical iOS 16.x device** — not a simulator, not iOS 18+. **[carried]**
9. **Whether the `flutter_gemma` native cache can be pre-seeded for a hermetic offline CI build.** Inferred from the hook's layout and marker-file logic; there is no documented env-var override. Settled by trying it on a network-disabled runner. **[carried]**
10. **Whether your chosen runtime can `mmap` from an APK fd + offset on Android.** llama.cpp's `mmap` path takes a filename; `AAsset_openFileDescriptor64` gives fd + offset + length. If the runtime can't handle the offset form, you extract to the filesystem and double storage. **This is the most likely place the Android side costs an unplanned week.** Settled by reading the plugin's Android source before committing. **[carried]**
11. **Whether ML Kit Android still functions correctly with `INTERNET` removed.** The manifest merge was proven clean; the recognizer was never run with the removal in place. The datatransport uploader will still schedule jobs and fail — harmless logcat noise, a `SecurityException`, or battery-wasting retries is untested. **[carried]**
12. **Whether iOS ML Kit telemetry actually fires.** The endpoints and HTTP client were proven linked into the binary; no request was observed. Given the documented no-opt-out, I would not spend the time — but it is the experiment if anyone argues the point. **[carried]**
13. **Per-device iOS footprint limits.** Apple publishes no table. The figures used above (~4,000 MB on 8 GB devices, ~900 MB on 3 GB, ~50% of RAM) are community sources. Settled by calling `os_proc_available_memory()` on the exact target iPhone. **[weak]**
14. **Apple's 200 MB cellular-download threshold.** Not present on the App Store Connect maximum-build-file-sizes page I fetched; carried from secondary sources (raised from 150 MB in 2019, user-overridable since iOS 13). Play's >200 MB mobile-data warning **is** primary-verified. **[weak]**
15. **`lfm1.0` licence text and the $10M revenue cap.** Multiple secondary sources agree; the licence file itself was not read. Needs primary confirmation before LFM2.5 can be relied on as a fallback. **[weak, carried]**
16. **LFM2.5-230M/350M on-disk sizes and RAM at common quantizations.** Not published on the HF pages; no measured RSS found. **[carried]**
17. **Qwen3-0.6B's licence specifically.** Qwen3 is generally Apache 2.0; not re-verified for the 0.6B. **[carried]**
18. **Gemma 4 E2B's iOS memory figures are internally inconsistent** — a 2,583 MB file reported at 607 MB peak on iPhone 17 Pro CPU. Doesn't change anything (E2B is out on size), but **do not quote the 607 MB figure**. **[carried]**
19. **Whether App Review treats user-imported model weights as "code" under Guideline 2.5.2.** No Apple statement on weights specifically; precedent (LLM Farm, PocketPal AI) suggests data. Only matters if you pursue user import, which is not recommended. Settled by a DTS ticket before building the flow. **[carried]**
20. **Redistribution rights for a specific bundled `.litertlm` conversion.** `google/functiongemma-270m-it` is `gated: manual` (verified); `sasha-denisov/function-gemma-270M-it` is ungated but carries **no HF licence tag at all** while its card text cites the Gemma Terms. Gating affects your build pipeline, not the shipped app — but provenance of whichever conversion you bundle is a legal question. **[carried]**
21. **Whether anyone has published a schema-validity rate for FunctionGemma under grammar-constrained decoding.** Both halves exist separately (FunctionGemma fine-tuned to 85% on Mobile Actions; constrained decoding taking a 1B model from 13% to ~96% schema validity on hard schemas per JSONSchemaBench, arXiv:2501.10868). **No source combines them on this model.** The claim that 270M + grammar clears your bar is a synthesis, not a measurement. It is the highest-value number Step 2 can produce. **[carried]**
22. **`cunning_document_scanner` 3.0.1's Android implementation** — if it uses the ML Kit Document Scanner API it is Play-Services-delivered and disqualified. Thirty seconds of reading its `android/build.gradle` settles it. VisionKit's `VNDocumentCameraViewController` on iOS is fine and is the best capture layer available. **[carried]**
23. **Apple's supported-language list on iOS 16 revision 3.** The 30-language list observed was from macOS 26.3.1; the iOS 16 list is very likely shorter. English is safe regardless. **[carried]**
24. **Whether Apple publishes an explicit "Vision never uses the network" guarantee.** None found in the API reference. Evidence is strong but circumstantial (models on-disk in the OS framework). Settled by the airplane-mode packet capture in Step 3. **[carried]**

---

### Verification note

Facts I re-verified against primary sources on 2026-08-12: `flutter_gemma` 1.5.2 (2026-08-04, `sdk >=3.12.0 <4.0.0`, `flutter >=3.44.0`) and `flutter_gemma_litertlm` 1.3.1 (2026-07-28) via the pub.dev API; the absence of any constraint/grammar symbol in `flutter_gemma`'s 2,019-symbol dartdoc index; GitHub issues #195, #307, #348, #405 (all open, titles/dates/bodies as described, including the full text of #307's comment thread); `google/functiongemma-270m-it` (created 2025-10-08, `license: gemma`, `gated: manual`, ships `tiny_garden.litertlm`) via the HF API; the FunctionGemma model card's device benchmarks; the Gemma Terms of Use (effective 2026-04-01, NOTICE + downstream-enforceable-provision + pass-through obligations, no copyleft, Section 3.2 remote-restriction clause); LiteRT-LM's constrained-decoding doc (two mutually exclusive modes, syntax-level tool-call constraint); LiteRT-LM releases v0.14.0 → v0.16.0 (2026-08-11), confirming flutter_gemma trails by two minors; Apple's maximum build file sizes (4 GB uncompressed, 80 MB `__TEXT`); Google Play's size limits (500 MB base module, >200 MB mobile-data warning); ML Kit's iOS data disclosure (no opt-out documented); `llamadart` 0.8.19 (2026-08-10); `google_mlkit_text_recognition` 0.16.0 (2026-07-07).

The four researchers' local experiments — the `MLKitCommon` Mach-O symbol dump, the AGP manifest-merge probe, the 13.79 MB APK delta, the Apple Vision confidence sweep, and the GGUF compression measurements — are primary evidence but were **not reproduced by me**. They are the strongest findings in the sweep and I would not re-litigate them, but that is their provenance.
