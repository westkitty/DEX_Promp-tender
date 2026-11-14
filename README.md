# DEX//PROMPTENDER

> *"Your intent. Perfectly served."* — *"Every model has its own recipe."*

**DEX//PROMPTENDER** is a native macOS menu-bar and detachable workbench utility that acts as a **universal, offline-first prompt compiler** across local diffusion, image/video, and general/agentic text models.

It evolves the proven offline prompt workbench architecture of [westkitty/DexCraft](https://github.com/westkitty/DexCraft) into an independent application with its own bundle identifier (`com.andrew.dexpromptender`) and isolated application storage (`~/Library/Application Support/DexPromptender/`).

---

## Core Design Principles

- **Offline-First & Zero-Key Capable:** Full prompt parsing, deterministic target compilation, constraint validation (`Strain`), semantic diffing, and side-by-side comparison (`The Flight`) work completely offline with zero API keys, no internet connection, no paid inference, and no running backend services.
- **Lossless Intent Preservation:** Raw input is never silently mutated. Protected spans (code fences, `{variables}`, `__wildcards__`, `<lora:...>`, `embedding:...`, paths, quoted literals, and explicit locks) remain inspectable and verifiable.
- **Truthful Proof, No Fake Scores:** Validation surfaces concrete pass, warning, and blocking evidence tied to real target constraints (length limits, schema compatibility, parameter bounds, dropped invariants).
- **Opt-In Extensions Only:** Integration with [DexDiffusion (`westkitty/Image_Gen`)](https://github.com/westkitty/Image_Gen) and optional cloud generation/refinement APIs (xAI Grok Imagine, OpenAI, Google Gemini) strictly preserve an explicit approval boundary before sending external requests.

## Supported Target Families

1. DexDiffusion image generation (`FLUX.2 Klein`, `FLUX.1`, `SDXL`, `SDXL Turbo`, `Pony`, `SD 1.5`, custom checkpoints)
2. Grok Imagine image generation & editing (`grok-imagine-image-2.0`)
3. Grok Imagine video generation (`grok-imagine-video-1.5`, `grok-imagine-video-1.5-lite`)
4. OpenAI GPT Image generation & editing (`gpt-image-1.5`, `gpt-image-2`, `gpt-image-1-mini`)
5. OpenAI GPT text, multimodal, coding, research & agent workflows (Responses API)
6. Gemini image generation & editing (Nano Banana / `gemini-3*-image`)
7. Gemini video generation (`gemini-omni-1.2-flash`, `veo-3.1`)
8. Gemini text, multimodal, coding, research & agent workflows

## Repository Layout

- `DexPromptender/` — Native macOS SwiftUI / AppKit application sources (`Models/`, `Services/`, `ViewModels/`, `Views/`, `Resources/`)
- `Tests/DexCraftReferenceTests/` — Preserved upstream XCTest suite (slated for `Testing.framework` + SwiftPM adaptation in Phase 1)
- `Tools/regression_harness.swift` — Standalone deterministic Swift regression harness
- `docs/implementation_plan.md` — Phased engineering architecture and validation plan
- `UPSTREAM.md` — Source lineage from `westkitty/DexCraft` and asset exclusions

## Building (macOS CommandLineTools / Swift 5.9+)

```bash
swift build
swift run DexPromptender
```

## Optional Local LLM Runtime

Public GitHub releases intentionally exclude large inference binaries and GGUF weights. **DEX//PROMPTENDER** runs its full deterministic prompt compiler without any local GGUF model.

If you want optional on-device tiny-LLM polish and local chat, place a macOS `llama-completion` binary and `.gguf` weights locally and configure them via Settings or environment variables:

- `DEXPROMPTENDER_EMBEDDED_RUNTIME_PATH`
- `DEXPROMPTENDER_EMBEDDED_TINY_MODEL_PATH`
- `DEXPROMPTENDER_EMBEDDED_FALLBACK_MODEL_PATH`
