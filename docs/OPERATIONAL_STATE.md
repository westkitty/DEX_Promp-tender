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
- **Phase 7 (The Bar & Mixing Room UI, Flight Comparison, House Specials, The Cellar, Serve Confirmation Modal & PromptenderCoordinator):** Implemented and verified alongside core & integration test suites (`18/18` tests in 5 suites).
- **Phases 11–12 (App Bundle Packaging, Verification & Closure):** In progress.
