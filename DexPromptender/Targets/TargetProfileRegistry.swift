import Foundation

/// Central registry of versioned target recipes across all 8 required model families
/// plus preserved upstream DexCraft targets and user-authored House Specials.
final class TargetProfileRegistry {
    let builtInRecipes: [RecipeProfile]

    init() {
        self.builtInRecipes = [
            // 1. DexDiffusion Image Targets
            RecipeProfile(
                id: "dexdiffusion-flux2-klein-4b",
                version: "2.1.0",
                name: "DexDiffusion · FLUX.2 Klein 4B",
                destination: .dexDiffusionImage,
                modelID: "flux2-klein-4b",
                subtitle: "Natural prose, spatial precision, 4000-char controlled limit",
                promptDialectNote: "FLUX.2 responds cleanly to cohesive natural prose with explicit lighting, camera, and spatial relations. Avoid weighted tag soup unless specifically locked.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 4000,
                    maxNegativeCharacters: 4000,
                    maxReferenceAssets: 1,
                    supportedAspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3"],
                    supportedResolutions: ["512x512", "768x768", "1024x1024", "1344x768", "768x1344"],
                    supportsNegativePromptField: true
                )
            ),
            RecipeProfile(
                id: "dexdiffusion-flux-fp8",
                version: "2.1.0",
                name: "DexDiffusion · FLUX FP8",
                destination: .dexDiffusionImage,
                modelID: "flux-fp8",
                subtitle: "High-detail FLUX checkpoint via sdcpp",
                promptDialectNote: "Rich photographic or painterly prose; positive phrasing strongly preferred over long negative lists.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 4000,
                    maxNegativeCharacters: 4000,
                    maxReferenceAssets: 1,
                    supportedAspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3"],
                    supportedResolutions: ["768x768", "1024x1024", "1344x768", "768x1344"],
                    supportsNegativePromptField: true
                )
            ),
            RecipeProfile(
                id: "dexdiffusion-sdxl-photonic",
                version: "2.0.0",
                name: "DexDiffusion · SDXL / Photonic",
                destination: .dexDiffusionImage,
                modelID: "sdxl-photonic",
                subtitle: "Structured descriptors + dedicated negative prompt",
                promptDialectNote: "Balances clear subject prose with comma-separated lighting, lens, and explicit negative_prompt exclusions.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "blurry, deformed hands, watermark, low contrast, artifacts",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 4000,
                    maxNegativeCharacters: 4000,
                    maxReferenceAssets: 1,
                    supportedAspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3"],
                    supportedResolutions: ["1024x1024", "1152x896", "896x1152", "1344x768"],
                    supportsNegativePromptField: true
                )
            ),
            RecipeProfile(
                id: "dexdiffusion-sdxl-pony",
                version: "2.0.0",
                name: "DexDiffusion · Pony / Tag-Aware SDXL",
                destination: .dexDiffusionImage,
                modelID: "sdxl-pony",
                subtitle: "Preserves score/source/rating tags + LoRAs",
                promptDialectNote: "Preserves quality score tags (`score_9`, `score_8_up`), source/rating tags, and `<lora:...>` weights cleanly ahead of scene descriptors.",
                defaultMixMode: .neat,
                systemPrelude: "score_9, score_8_up, score_7_up",
                styleSuffix: "",
                defaultNegativePrompt: "score_4, score_3, score_2, score_1, lowres, blurry, watermark",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 4000,
                    maxNegativeCharacters: 4000,
                    maxReferenceAssets: 1,
                    supportedAspectRatios: ["1:1", "4:3", "3:4", "16:9", "9:16"],
                    supportedResolutions: ["1024x1024", "896x1152", "1152x896"],
                    supportsNegativePromptField: true
                )
            ),
            RecipeProfile(
                id: "dexdiffusion-sd15",
                version: "1.9.0",
                name: "DexDiffusion · SD 1.5",
                destination: .dexDiffusionImage,
                modelID: "sd15",
                subtitle: "Compact token budget + explicit negative prompt",
                promptDialectNote: "Concise subject, style, and lens tokens suited to SD 1.5 CLIP window alongside crisp negative_prompt exclusions.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "lowres, bad anatomy, blurry, cropped, watermark, text",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 4000,
                    maxNegativeCharacters: 4000,
                    maxReferenceAssets: 1,
                    supportedAspectRatios: ["1:1", "4:3", "3:4", "3:2", "2:3"],
                    supportedResolutions: ["512x512", "768x512", "512x768"],
                    supportsNegativePromptField: true
                )
            ),

            // 2. Grok Imagine Image
            RecipeProfile(
                id: "xai-grok-imagine-image-2.0",
                version: "2.0.0",
                name: "Grok Imagine · Image 2.0",
                destination: .grokImagineImage,
                modelID: "grok-imagine-image-2.0",
                subtitle: "Photoreal & stylized prose + up to 5 reference images",
                promptDialectNote: "Grok Imagine excels with direct visual prose and crisp quoted text rendering; exclusions belong in positive constraint clauses rather than a negative_prompt field.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 8000,
                    maxReferenceAssets: 5,
                    supportedAspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "auto"],
                    supportedResolutions: ["1k", "2k"],
                    supportsNegativePromptField: false
                )
            ),

            // 3. Grok Imagine Video
            RecipeProfile(
                id: "xai-grok-imagine-video-1.5",
                version: "1.5.0",
                name: "Grok Imagine · Video 1.5",
                destination: .grokImagineVideo,
                modelID: "grok-imagine-video-1.5",
                subtitle: "Up to 15s, 480p/720p/1080p, lip-sync dialogue, 14 refs, 3 voice refs",
                promptDialectNote: "Temporal shot ordering, explicit camera movement, pinned start/end frame continuity, and lip-synced spoken dialogue lines.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 8000,
                    maxReferenceAssets: 14,
                    maxVoiceReferences: 3,
                    supportedAspectRatios: ["16:9", "9:16", "1:1", "4:3", "3:4", "3:2", "2:3"],
                    supportedResolutions: ["480p", "720p", "1080p"],
                    minDurationSeconds: 1,
                    maxDurationSeconds: 15,
                    supportsNegativePromptField: false
                )
            ),
            RecipeProfile(
                id: "xai-grok-imagine-video-1.5-lite",
                version: "1.5.0",
                name: "Grok Imagine · Video 1.5 Lite",
                destination: .grokImagineVideo,
                modelID: "grok-imagine-video-1.5-lite",
                subtitle: "Fast iteration video up to 15s",
                promptDialectNote: "Tight shot progression and concise audio/camera instructions optimized for faster turnaround.",
                defaultMixMode: .neat,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 6000,
                    maxReferenceAssets: 14,
                    maxVoiceReferences: 3,
                    supportedAspectRatios: ["16:9", "9:16", "1:1", "4:3", "3:4"],
                    supportedResolutions: ["480p", "720p"],
                    minDurationSeconds: 1,
                    maxDurationSeconds: 15,
                    supportsNegativePromptField: false
                )
            ),

            // 4. OpenAI GPT Image
            RecipeProfile(
                id: "openai-gpt-image-1.5",
                version: "1.5.0",
                name: "OpenAI · GPT Image 1.5",
                destination: .openAIImage,
                modelID: "gpt-image-1.5",
                subtitle: "Compositional brief, literal text, masks, transparency, 16 refs",
                promptDialectNote: "Responds well to structured scene geometry, exact quoted typography, mask regions, `input_fidelity`, and transparent/opaque background control.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 32000,
                    maxReferenceAssets: 16,
                    supportedAspectRatios: ["1:1", "3:2", "2:3", "16:9", "9:16"],
                    supportedResolutions: ["1024x1024", "1536x1024", "1024x1536", "auto"],
                    supportsNegativePromptField: false,
                    supportsMaskEditing: true
                )
            ),
            RecipeProfile(
                id: "openai-gpt-image-2",
                version: "2.0.0",
                name: "OpenAI · GPT Image 2",
                destination: .openAIImage,
                modelID: "gpt-image-2",
                subtitle: "High-fidelity instruction following & multi-image edits",
                promptDialectNote: "Excels with spatial placement specs, multi-subject fidelity locks, and high/xhigh/max quality tiers.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 32000,
                    maxReferenceAssets: 16,
                    supportedAspectRatios: ["1:1", "3:2", "2:3", "16:9", "9:16"],
                    supportedResolutions: ["1024x1024", "1536x1024", "1024x1536", "auto"],
                    supportsNegativePromptField: false,
                    supportsMaskEditing: true
                )
            ),

            // 5. OpenAI GPT Text / Multimodal / Coding / Research / Agent
            RecipeProfile(
                id: "openai-gpt-6.1-sol-responses",
                version: "6.1.0",
                name: "OpenAI · GPT 6.1 Sol (Responses API)",
                destination: .openAITextAgent,
                modelID: "gpt-6.1-sol",
                subtitle: "Developer instructions + user input + reasoning effort / JSON schema",
                promptDialectNote: "Separates developer `instructions` from user `input`, enforces concrete verification contracts, and wires `reasoning.effort` cleanly.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxReferenceAssets: 16,
                    supportsJSONSchemaOutput: true
                )
            ),
            RecipeProfile(
                id: "openai-gpt-6-astra-responses",
                version: "6.0.0",
                name: "OpenAI · GPT 6 Astra (General / Multimodal)",
                destination: .openAITextAgent,
                modelID: "gpt-6-astra",
                subtitle: "Structured markdown sections + verification guardrails",
                promptDialectNote: "Clean role framing, explicit non-goals, and concrete output contracts without bloat.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxReferenceAssets: 16,
                    supportsJSONSchemaOutput: true
                )
            ),

            // 6. Gemini Image (Nano Banana)
            RecipeProfile(
                id: "google-gemini-nano-banana-2.1",
                version: "2.1.0",
                name: "Gemini Image · Nano Banana 2.1",
                destination: .geminiImage,
                modelID: "gemini-nano-banana-2.1",
                subtitle: "Editorial prose, 1K/2K/4K, wide ratios (1:8..8:1), 14 char/object refs",
                promptDialectNote: "Natural descriptive narrative paired with `imageConfig` (`aspectRatio`, `imageSize`) and `thinkingConfig.thinkingLevel`.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 16000,
                    maxReferenceAssets: 14,
                    supportedAspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "21:9", "4:5", "5:4", "1:4", "4:1", "1:8", "8:1"],
                    supportedResolutions: ["1K", "2K", "4K"],
                    supportsNegativePromptField: false
                )
            ),
            RecipeProfile(
                id: "google-gemini-3.1-flash-image",
                version: "3.1.0",
                name: "Gemini · 3.1 Flash Image",
                destination: .geminiImage,
                modelID: "gemini-3.1-flash-image",
                subtitle: "Fast multimodal image gen & reference composition",
                promptDialectNote: "Crisp visual narrative + explicit reference role mapping (character vs object consistency).",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 16000,
                    maxReferenceAssets: 14,
                    supportedAspectRatios: ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "21:9", "1:4", "4:1", "1:8", "8:1"],
                    supportedResolutions: ["1K", "2K", "4K"],
                    supportsNegativePromptField: false
                )
            ),

            // 7. Gemini Video
            RecipeProfile(
                id: "google-gemini-omni-1.2-flash",
                version: "1.2.0",
                name: "Gemini Video · Omni 1.2 Flash",
                destination: .geminiVideo,
                modelID: "gemini-omni-1.2-flash",
                subtitle: "3–15s native audio, multi-turn <VIDEO_REF_0> editing, up to 6 refs",
                promptDialectNote: "Structured beat timeline, explicit audio/dialogue cues, and lossless `<VIDEO_REF_0>` continuity handles.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 12000,
                    maxReferenceAssets: 6,
                    supportedAspectRatios: ["16:9", "9:16", "1:1", "4:3", "3:4"],
                    supportedResolutions: ["720p", "1080p"],
                    minDurationSeconds: 3,
                    maxDurationSeconds: 15,
                    supportsVideoEditTokens: true
                )
            ),
            RecipeProfile(
                id: "google-veo-3.1-generate-001",
                version: "3.1.0",
                name: "Gemini Video · Veo 3.1",
                destination: .geminiVideo,
                modelID: "veo-3.1-generate-001",
                subtitle: "Enterprise 24fps, 16:9 / 9:16, up to 4K + native audio",
                promptDialectNote: "Cinematographic beat choreography with strict 16:9 or 9:16 geometry, camera trajectory, lighting continuity, and SFX/dialogue specification.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxPromptCharacters: 12000,
                    maxReferenceAssets: 3,
                    supportedAspectRatios: ["16:9", "9:16"],
                    supportedResolutions: ["720p", "1080p", "4K"],
                    minDurationSeconds: 4,
                    maxDurationSeconds: 8
                )
            ),

            // 8. Gemini Text / Agent
            RecipeProfile(
                id: "google-gemini-3.1-pro",
                version: "3.1.0",
                name: "Gemini · 3.1 Pro (Text / Agent / JSON)",
                destination: .geminiTextAgent,
                modelID: "gemini-3.1-pro",
                subtitle: "systemInstruction + grounded XML/Markdown + responseJsonSchema",
                promptDialectNote: "Separates `systemInstruction` cleanly from user `contents` and formats JSON schema output when structured data is requested.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxReferenceAssets: 14,
                    supportsJSONSchemaOutput: true
                )
            ),
            RecipeProfile(
                id: "google-gemini-2.5-flash",
                version: "2.5.0",
                name: "Gemini · 2.5 Flash (Fast / Coding)",
                destination: .geminiTextAgent,
                modelID: "gemini-2.5-flash",
                subtitle: "Concise instructions, deterministic verification criteria",
                promptDialectNote: "Low-overhead task framing and tight acceptance boundaries.",
                defaultMixMode: .neat,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(
                    maxReferenceAssets: 14,
                    supportsJSONSchemaOutput: true
                )
            ),

            // 9. Preserved Legacy DexCraft Playbook Targets
            RecipeProfile(
                id: "anthropic-claude-xml",
                version: "1.0.0",
                name: "Claude · XML Prompt Contract",
                destination: .claudeTextAgent,
                modelID: "claude-sonnet-4",
                subtitle: "Preserved DexCraft XML tags (<objective>, <context>, <constraints>)",
                promptDialectNote: "Deterministic XML structure preserving exact deliverables, code fences, and invariants.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints(supportsJSONSchemaOutput: true)
            ),
            RecipeProfile(
                id: "perplexity-verified-research",
                version: "1.0.0",
                name: "Perplexity · Verified Research",
                destination: .perplexityResearch,
                modelID: "sonar-reasoning-pro",
                subtitle: "Preserved citation & source-verification discipline",
                promptDialectNote: "Enforces primary-source citations, uncertainty labeling, and structured evidence synthesis.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints()
            ),
            RecipeProfile(
                id: "agentic-ide-workflow",
                version: "1.0.0",
                name: "Agentic IDE · Execution Scaffold",
                destination: .agenticIDEWorkflow,
                modelID: "agentic-ide",
                subtitle: "Preserved Plan -> Diff -> Tests -> Build/Revert workflow",
                promptDialectNote: "Produces repository-aware implementation specs with build/test commands and rollback notes.",
                defaultMixMode: .stirred,
                systemPrelude: "",
                styleSuffix: "",
                defaultNegativePrompt: "",
                isBuiltIn: true,
                constraints: RecipeConstraints()
            )
        ]
    }

    func allRecipes(customRecipes: [RecipeProfile] = []) -> [RecipeProfile] {
        builtInRecipes + customRecipes
    }

    func recipe(for id: String, customRecipes: [RecipeProfile] = []) -> RecipeProfile? {
        allRecipes(customRecipes: customRecipes).first(where: { $0.id == id })
    }

    func recipes(for destination: TargetDestination, customRecipes: [RecipeProfile] = []) -> [RecipeProfile] {
        allRecipes(customRecipes: customRecipes).filter { $0.destination == destination }
    }

    func defaultRecipe(for destination: TargetDestination, customRecipes: [RecipeProfile] = []) -> RecipeProfile {
        recipes(for: destination, customRecipes: customRecipes).first ?? builtInRecipes[0]
    }
}
