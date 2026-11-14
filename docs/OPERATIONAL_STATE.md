# Operational State — DEX//PROMPTENDER

## Baseline Bootstrap

- **Repository:** `https://github.com/westkitty/DEX_Promp-tender` (`main`)
- **Upstream Lineage:** Derived selectively from `westkitty/DexCraft` (`master` @ `b467c52ee9c554360fa3f895e4f88e6c6eb6fcdb`).
- **Integration Reference:** `westkitty/Image_Gen` (`main` @ `39534f2`, live loopback operator console verified reachable on `127.0.0.1:31337` with `flux2-klein-4b` and `flux-fp8` proofed, and schema constraint `maxLength: 4000` confirmed in `schemas/generation-job.schema.json`).
- **Identity:** `com.andrew.dexpromptender`, storage under `~/Library/Application Support/DexPromptender/` (isolated from `com.andrew.dexcraft`).
- **Build Toolchain Note:** Host runs CommandLineTools Swift 6.3.3 (`swift build` + `Testing.framework` with explicit framework/rpath flags); full `Xcode.app` (`xcodebuild` / `XCTest.framework`) is not installed on this host.

## Current Phase Status

- **Phase 0 (Audit & Plan):** Complete.
- **Bootstrap & Initial Publication:** Executed in `main` with clean preflight and SwiftPM compilation verification.
- **Phases 1–12 (Core Compiler, 8 Target Recipes, UI Workbench, Integrations):** Pending plan approval before implementation edits.
