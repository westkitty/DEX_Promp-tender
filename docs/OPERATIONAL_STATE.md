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
- **Phases 1–6 (Core Compiler, Invariant Registry, MixModes Neat/Stirred/Shaken, Strain Proof, All 8 Target Compilers, Closed-World Flight):** Implemented and verified (`./scripts/run_tests.sh`: 10/10 tests in 3 suites passing, zero blocking errors).
- **Phases 7–12 (UI Evolution, Live DexDiffusion Client, Keychain & Opt-In API Clients, DexCraft Importer, App Bundle Packaging):** Pending next implementation checkpoints.
