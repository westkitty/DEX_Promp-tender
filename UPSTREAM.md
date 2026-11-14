# Upstream Provenance & Lineage

**DEX//PROMPTENDER** (`westkitty/DEX_Promp-tender`) is an independent evolution originally bootstrapped from selective, verified sources of [westkitty/DexCraft](https://github.com/westkitty/DexCraft).

## Upstream Reference Revision

- **Repository:** `https://github.com/westkitty/DexCraft.git`
- **Branch:** `master`
- **Baseline Commit:** `b467c52ee9c554360fa3f895e4f88e6c6eb6fcdb`
- **Upstream License Note:** As of the baseline commit, `westkitty/DexCraft` contained no standalone `LICENSE` file in the repository root; both repositories belong to `westkitty`. Imported source structure and behavior attribution are preserved here.

## Imported Source & Assets

The initial bootstrap selectively imported clean Swift application sources, UI views, deterministic optimizer/builder services, bundled default templates (`DefaultTemplates.json`), offline playbooks (`PromptingPlaybooks.md`), `AppIcon.appiconset`, `DexCraftWatermark.imageset`, standalone `Tools/regression_harness.swift`, and reference tests (`Tests/DexCraftReferenceTests/`).

## Intentional Exclusions

To keep this public repository clean, safe, and free of bloat or personal data, the following items from the upstream checkout were intentionally excluded:

- `.git` history and `.DS_Store` metadata
- Xcode/SwiftPM build artifacts (`build/`, `build-install/`, `DerivedData/`, `.build/`)
- Prebuilt inference binaries and ~93.5 MB GGUF weights (`Tools/embedded-tiny-runtime/macos-arm64/`)
- Personal Application Support state (`history.json`, user `templates.json`, `prompt-library.json`, `connected-model-settings.json`, `optimizer-weights.json`, batch fixtures)
- Archival zips (`DexCraft-master.zip`) and internal research/resurrection directories

## Identity Divergence

- **Upstream DexCraft:** `com.andrew.dexcraft` using `~/Library/Application Support/DexCraft/`
- **DEX//PROMPTENDER:** `com.andrew.dexpromptender` using `~/Library/Application Support/DexPromptender/`

Existing DexCraft installations and user stores remain completely untouched. An optional, non-destructive read-only import flow is planned to let users migrate legacy history and templates into DEX//PROMPTENDER without overwriting or altering DexCraft data.
