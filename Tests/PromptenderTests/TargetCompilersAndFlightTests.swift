import Foundation
import Testing
@testable import PromptenderKit

@Suite("All 8 Target Compilers & Closed-World Flight")
struct TargetCompilersAndFlightTests {
    @Test("Every built-in recipe compiles offline with zero API keys and valid JSON payload")
    func compileAllTargetsOffline() throws {
        let engine = PromptCompilerEngine()
        let sampleInputs: [TargetDestination: String] = [
            .dexDiffusionImage: "score_9 <lora:film_grain:0.6> A brass lantern on wet cobblestones at dusk __weather__ NOT: cartoon, watermark",
            .grokImagineImage: #"Photorealistic espresso machine labeled "MORNING ROAST" on walnut counter, 16:9, avoid plastic reflections"#,
            .grokImagineVideo: "[00:00-00:04] Slow dolly forward onto harbor fog.\n[00:04-00:09] Fisherman says: \"Tide turns before sunrise.\"\nAspect ratio 16:9, 720p, 9s",
            .openAIImage: #"Flat vector emblem on transparent background reading "STARLIGHT LABS" with sharp metallic bevel, 1:1"#,
            .openAITextAgent: "Refactor the Swift keychain helper in `/src/KeychainStore.swift` and return a strict JSON summary.",
            .geminiImage: "Minimalist ceramic vase bathed in afternoon window shadows, editorial photography, 4K, aspect ratio 4:5",
            .geminiVideo: "[00:00-00:03] Start state: <VIDEO_REF_0> static alley in rain.\n[00:03-00:07] Neon sign flickers on with low electric hum. SFX: rain hiss.",
            .geminiTextAgent: "Analyze SQLite index contention and return structured JSON findings.",
            .claudeTextAgent: "Review `PromptLexer.swift` for UTF-16 boundary bugs and preserve existing public API.",
            .perplexityResearch: "Compare 2026 macOS Keychain API guidance with primary Apple documentation links.",
            .agenticIDEWorkflow: "Implement read-only JSON import with backup creation before writing destination files."
        ]

        for recipe in engine.registry.builtInRecipes {
            let input = sampleInputs[recipe.destination] ?? "Test prompt for \(recipe.name)"
            let result = engine.compile(rawInput: input, recipe: recipe, mixMode: .stirred)

            #expect(!result.compiledPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let data = try #require(result.structuredPayloadJSON.data(using: .utf8))
            let obj = try JSONSerialization.jsonObject(with: data)
            #expect(obj is [String: Any])
            #expect(result.provenance.contains { $0.source == .userAuthored })
        }
    }

    @Test("Closed-world Flight keeps targets isolated with zero Pony/DexDiffusion style bleed")
    func closedWorldFlightIsolation() {
        let registry = TargetProfileRegistry()
        let flight = FlightEngine()

        let ponyRecipe = registry.recipe(for: "dexdiffusion-sdxl-pony")!
        let geminiImg = registry.recipe(for: "google-gemini-nano-banana-2.1")!
        let openAIImg = registry.recipe(for: "openai-gpt-image-2")!
        let grokImg = registry.recipe(for: "xai-grok-imagine-image-2.0")!

        let draft = #"Editorial photograph of a green glass apothecary bottle labeled "ELIXIR NO. 4" on moss, morning mist, NOT: blurry, text typo"#

        let report = flight.compileFlight(
            rawInput: draft,
            recipes: [ponyRecipe, geminiImg, openAIImg, grokImg],
            mixMode: .stirred
        )

        #expect(report.entries.count == 4)

        let ponyOut = report.entries[0].result
        let geminiOut = report.entries[1].result
        let openAIOut = report.entries[2].result
        let grokOut = report.entries[3].result

        // Pony gets score tags and separate negative_prompt
        #expect(ponyOut.compiledPrompt.contains("score_9"))
        #expect((ponyOut.negativePrompt ?? "").contains("blurry"))

        // Gemini, OpenAI, and Grok must NOT receive Pony score tags!
        #expect(!geminiOut.compiledPrompt.contains("score_9"))
        #expect(!openAIOut.compiledPrompt.contains("score_9"))
        #expect(!grokOut.compiledPrompt.contains("score_9"))

        // Literal text invariant holds across ALL 4 targets
        for entry in report.entries {
            #expect(entry.result.compiledPrompt.contains("ELIXIR NO. 4"))
            #expect(!entry.result.proofReport.hasBlockingIssues)
        }
    }
}
