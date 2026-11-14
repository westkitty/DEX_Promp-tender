# DEX//PROMPTENDER — Implementation Plan

- **Product:** `DEX//PROMPTENDER` (*"Your intent. Perfectly served."* / *"Every model has its own recipe."*)
- **Authoritative Repository:** `https://github.com/westkitty/DEX_Promp-tender` (`main`)
- **Upstream Reference:** `westkitty/DexCraft` (`master` @ `b467c52ee9c554360fa3f895e4f88e6c6eb6fcdb`)
- **Backend Integration Authority:** `westkitty/Image_Gen` (`main` @ `39534f2`)

---

## 1. Source-Control & Identity Architecture

1. **Independent Repository:** `westkitty/DEX_Promp-tender` owns all DEX//PROMPTENDER source, compiler modules, provider adapters, tests, build scripts, and documentation. `DexCraft` and `Image_Gen` are not modified or pushed to by this project.
2. **Coexisting macOS Identity:**
   - Bundle ID: `com.andrew.dexpromptender`
   - Display Name: `DEX//PROMPTENDER`
   - Executable / Storage Name: `DexPromptender`
   - Application Support Path: `~/Library/Application Support/DexPromptender/`
   - Legacy `com.andrew.dexcraft` (`~/Library/Application Support/DexCraft/`) remains untouched; an optional non-destructive `Import from DexCraft` workflow (Phase 11) will read legacy files read-only, validate schemas, back up the destination store first, deduplicate records, and report import counts.
3. **Offline-First & Public-Repo Hygiene:** No GGUF weights, native inference binaries, credentials, personal prompt history, or machine-specific paths are committed. Deterministic prompt compilation runs completely offline without binaries or network access.

---

## 2. Target Compiler Pipeline

```
Raw Draft
  -> SourcePreservingLexer (ProtectedSpans: fences, {vars}, __wildcards__, <lora:...>, embeddings, <VIDEO_REF_0>, paths/URLs, quoted literals, inline locks)
  -> SemanticIRParser -> CanonicalPromptIR (immutable draft + extracted Ingredients + protected invariants)
  -> InvariantRegistry (zero silent drop/alteration verification)
  -> TargetProfileRegistry (versioned Recipes for 8 model families + preserved legacy targets)
  -> MixEngine (Neat | Stirred | Shaken; deterministic heuristics + optional local/authorized LLM assist)
  -> TargetCompiler (model-native prompt, negative prompt, structured JSON payload, parameters)
  -> StrainProofEngine (Pass / Warning / Blocking evidence; never fabricated numerical quality scores)
  -> SemanticDiffEngine (ingredient attribution diff + line LCS diff)
  -> ServeRouter (Copy Prompt | Copy JSON | Export File/Batch | Open DexDiffusion | Explicit Authorized Submit)
```

### Mandatory Destinations (`TargetDestination`)
1. **DexDiffusion Image** (`flux2-klein-4b`, `flux-fp8`, `flux-dev`, `sdxl`, `sdxl-turbo`, `pony`, `sd15`, custom checkpoints; live capability/wildcard/schema sync when `127.0.0.1:31337` is reachable, offline specs when disconnected). Enforces `generation-job.schema.json` `maxLength: 4000` ceiling.
2. **Grok Imagine Image** (`grok-imagine-image-2.0`, generate + up-to-5 ref edit payload).
3. **Grok Imagine Video** (`grok-imagine-video-1.5`, `grok-imagine-video-1.5-lite`, lip-synced speech/audio cues, up-to-14 refs, 480p/720p/1080p, `<= 15s`).
4. **OpenAI GPT Image** (`gpt-image-1.5`, `gpt-image-2`, `gpt-image-1-mini`, generate + `/v1/images/edits` mask/refs/fidelity/transparency).
5. **OpenAI GPT Text / Agent** (`gpt-6-astra`, `gpt-6.1-sol` Responses API `instructions`, `input`, `reasoning.effort`, `text.format` JSON schema).
6. **Gemini Image (Nano Banana)** (`gemini-nano-banana-2.1`, `gemini-3.1-flash-image`, `gemini-3.1-flash-lite-image`, `gemini-3-pro-image`, 1K/2K/4K, wide aspect ratios, `thinking_level`, up to 14 refs).
7. **Gemini Video** (`gemini-omni-1.2-flash`, `veo-3.1`, native audio/SFX, `<VIDEO_REF_0>` multi-turn edit tokens).
8. **Gemini Text / Agent** (`gemini-2.5-*`, `gemini-3*`, `systemInstruction`, `responseJsonSchema`).
*(Preserved compatibility for existing Claude XML, Gemini/ChatGPT, Perplexity, and Agentic IDE targets.)*

---

## 3. Build & Phase Roadmap

- **Bootstrap (Complete upon verified push):** Clean import of reusable `DexCraft` source into `westkitty/DEX_Promp-tender` with `com.andrew.dexpromptender`, `Package.swift`, `swift build` compilation check, `UPSTREAM.md`, `README.md`, and docs.
- **Phases 1–3 (Core Compiler & IR):** Extract `PromptenderCore` SwiftPM library + implement `PromptLexer`, `CanonicalPromptIR`, `SemanticIRParser`, `InvariantRegistry`, `MixEngine` (`Neat`/`Stirred`/`Shaken`), `SemanticDiffEngine`, `StrainProofEngine`, and `Testing.framework` (`PromptenderTests`).
- **Phases 4–6 (8 Target Compilers & Flight):** Implement all 8 versioned `RecipeProfile` compilers, closed-world `FlightEngine`, golden fixture suite, and batch export updates.
- **Phases 7–8 (UI & DexDiffusion Client):** Evolve UI into **THE BAR**, **THE MIXING ROOM**, **THE FLIGHT**, **PROOF**, **HOUSE SPECIALS**, and **THE CELLAR**, plus live read-only + guarded submission `DexDiffusionClient`.
- **Phases 9–11 (Opt-In Cloud Clients, Keychain, Migration & App Bundle):** macOS Keychain secret store, explicit `ServeConfirmationSheet`, non-destructive read-only `DexCraftImportService`, and CommandLineTools `.app` bundle builder script (`scripts/build_app.sh`).
- **Phase 12 (Verification & Release Candidate):** Full test suite, offline zero-key compile proof, read-only loopback DexDiffusion check, and native `.app` UI launch inspection without altering `DexCraft.app` or firing billable jobs.
