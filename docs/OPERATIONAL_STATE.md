# Operational State — DEX//PROMPTENDER

## Baseline Bootstrap

- **Repository:** `https://github.com/westkitty/DEX_Promp-tender` (`main`)
- **Upstream Lineage:** Derived selectively from `westkitty/DexCraft` (`master` @ `b467c52ee9c554360fa3f895e4f88e6c6eb6fcdb`).
- **Integration Reference:** `westkitty/Image_Gen` (`main` @ `39534f2`, live loopback operator console verified reachable on `127.0.0.1:31337` with `flux2-klein-4b` and `flux-fp8` proofed, and schema constraint `maxLength: 4000` confirmed in `schemas/generation-job.schema.json`).
- **Identity:** `com.andrew.dexpromptender`, storage under `~/Library/Application Support/DexPromptender/` (isolated from `com.andrew.dexcraft`).
- **Build Toolchain Note:** Host runs CommandLineTools Swift 6.3.3 (`swift build` + `Testing.framework` with explicit framework/rpath flags); full `Xcode.app` (`xcodebuild` / `XCTest.framework`) is not installed on this host.

## Current Phase Status

- **Phase 0 (Audit & Plan):** Complete.
- **Bootstrap & Initial Publication:** Verified on `main` (`0c63658ca9a8f4d9c8d6c578a6daaff8e2f1ff0b`).
- **Phases 1–6 (Core Compiler, Invariant Registry, MixModes Neat/Stirred/Shaken, Strain Proof, All 8 Target Compilers, Closed-World Flight):** Implemented and verified on `main` (`6067805ec561e9e429074085bc3b43e933e3fcc0`).
- **Phases 8–10 (DexDiffusion Client, Keychain Secret Store, Opt-In Cloud Provider Router, Non-Destructive DexCraft Import):** Implemented and verified on `main` (`68355eb69481ffdb76e36e9686088e0a821e8f2a`).
- **Phase 7 (The Bar & Mixing Room UI, Flight Comparison, House Specials, The Cellar, Serve Confirmation Modal & PromptenderCoordinator):** Implemented and verified on `main` (`7fa89a32f6ad99ff2f5d96e1eef485edbb06d769`).
- **Phases 11–12 (Native Packaging, Verification & Closure):**
  - Added `scripts/build_app.sh` producing adhoc-signed `dist/DexPromptender.app` (`com.andrew.dexpromptender`, `iconutil` icon generation when `Xcode.app` is absent, bundled templates, playbooks, watermark image, and built-in wildcard `.txt` banks).
  - Upgraded to icon-only menu-bar status item (no words in menu bar), meaningful `Stirred`/`Shaken` prompt enhancement across image and text targets, built-in + bidirectional Dexter Fusion synced `WildcardsStudioView` editor, quick **Save Prompt** workflow + auto-history capture, and configurable `AppearanceSettingsStore` (watermark + behind-window background image controls).
  - Verified `codesign --verify --deep --strict`, `plutil -lint`, live read-only `GET /api/{version,capabilities,wildcards,generation-schema}` against loopback `127.0.0.1:31337`, isolated launch (`~/Library/Application Support/DexPromptender/`), clean termination, and `./scripts/run_tests.sh` (`23/23` tests in `6` suites passing).


## Wildcard Safety Repair — 2026-11-14 (Big Mac validation)

- **Scope:** DEX//PROMPTENDER wildcard editor, WildcardStore, PromptenderCoordinator, and isolated regression tests. Base revision `e0cf121356d3893483ea6b94e6704a28b5749e72`. MacBook app, DexCraft source, and DexDiffusion data were not modified.
- **Behavior:** `Save Local` never silently mirrors to a folder or writes to DexDiffusion. The new `Sync...` sheet selects destinations explicitly, requires additional approval before differing existing content is overwritten, and backs up existing copies. `Delete Bank...` explicitly confirms local/folder/remote scope, protects built-ins, defaults remote off, and requires separate acknowledgment for remote deletion. The coordinator surfaces partial failures rather than claiming full success.
- **Backup:** Old local, folder, and remote bank contents are written to `Application Support/DexPromptender/WildcardBackups` before destructive action. A final remote GET detects concurrent changes before PUT/DELETE where possible. The upstream API does not provide atomic conditional writes, so a last-moment race after this final GET cannot be completely eliminated client-side.
- **Source tests:** Native Big Mac SwiftPM debug build succeeded. `swift test` passed **31/31** across **6** suites (including mocked remote PUT/DELETE failures, explicit scope deletion, bundled-bank protection, remote/folder overwrite authorization, concurrent remote edits, and backup recovery fixtures). No live destructive DexDiffusion API calls were issued.
- **Packaging:** `./scripts/build_app.sh` built `dist/DexPromptender.app` and passed `plutil` and `codesign --verify --deep --strict` on Big Mac. This is a local ignored build artifact, not a GitHub release or an installed MacBook update.
- **Remaining verification:** Real menu-bar sheet clicking, focus/accessibility and visual correctness have not been exercised on the user's MacBook (DEX//REACH MacBook aiAccess is off); do not claim GUI QA or deployment complete.
- **Reference:** `docs/WILDCARD_SAFETY.md`.

## Impeccable UI/UX Gauntlet Implementation — 2026-11-14

- **Scope:** Implemented all 15 agreed UI/UX findings QW-01..05, HP-01..06, ST-01..04, based on commit 97d0c3569139ab46f99cf68054270688178adb87. Native app source only; no DexCraft or Image_Gen changes.
- **Protected behavior:** Preserved Mix modes, compiler IR, local/remote wildcard confirmation, separate-image guards, offline operation, Keychain provider gating, and paid Serve preview. Stale-result gating now additionally protects Copy/Serve and rechecks at execution.
- **Visual system:** Centralized PromptenderTheme and glass modifiers; native menu for compact navigation; focus/VoiceOver labels on icon controls; neutral disabled actions; screen-bounded popover and single-column result layout; Reduce Motion support; readable error receipts and complete request inspection.
- **Performance:** Debounced appearance setting writes, flushed at app termination; cached user-selected artwork by modified path. No model binaries added.
- **Evidence:** Native debug build passed; 36/36 Swift Testing cases across seven suites passed. Big Mac offscreen render probes passed at 480, 720, and 960 logical-point widths, plus Wildcards, Settings, and Serve views. Release bundle build and codesign outcome must be verified from the final packaging log, not inferred from debug tests. Impeccable's web-only detector is inapplicable to a SwiftUI/AppKit interface.
- **Not yet verified:** Actual MacBook installation, live UI clicking, VoiceOver focus traversal, custom-image contrast in every appearance, and notarization. No live destructive wildcard API calls or paid API requests were made.
- **Detail:** docs/IMPECCABLE_IMPLEMENTATION.md


## Appearance Settings Visibility Repair — 2026-11-14

- **Incident:** After the Impeccable upgrade, appearance settings were difficult to perceive as functional. Source inspection found settings persistence without an in-panel live preview, an image-obscuring full-strength material layer, and silent fallback for invalid image paths.
- **Correction:** Shared PromptenderAppearanceLayer now powers both the Bar and the Settings preview. Backdrop images use a restrained material and a contrast-protecting scrim. Missing images have actionable text. Backdrop blur is prepared using bounded, cached Core Image rendering, rather than relying solely on an offscreen-unverifiable SwiftUI blur effect.
- **Protected behavior:** No changes to compiler/prompt semantics, target selection, Keychain, external Serve authorization, DexDiffusion API, wildcard files, or source artwork. Appearance JSON fields and save location preserved.
- **Evidence:** Native debug build passed. 42/42 automated tests across eight suites passed, including new same-NSHostingView pixel-change assertions for background opacity, glass tint, watermark on/off, watermark scale and opacity, fit/fill, gaussian blur, image-load warnings and source-byte preservation.
- **Limitations:** Actual MacBook UI clicks and arbitrary image contrast remain unverified; MacBook execution access is disabled. Release bundle validation and published commit status are recorded separately after those actions.
- **Reference:** docs/APPEARANCE_SETTINGS_REPAIR.md

- **Final packaging:** Big Mac release app passed plutil, strict codesign, arm64 bundle inspection, and launch/quit smoke. Binary SHA-256 `3229c5d1a8930bf671ff272ca7f1654a7ab3a18f6dbbad0df5b86fe6e9e791d7`. Still not installed on MacBook at the time of this entry.
