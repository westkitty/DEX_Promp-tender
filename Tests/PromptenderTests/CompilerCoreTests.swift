import Foundation
import Testing
@testable import PromptenderKit

@Suite("Lexer, IR, Invariants & Strain Proof")
struct CompilerCoreTests {
    @Test("Lexer preserves protected tokens cleanly without overlapping corruption")
    func lexerProtectedTokens() {
        let input = """
        score_9, score_8_up <lora:neon_noir:0.75> __lighting/cyberpunk__
        A storefront sign reading "OPEN 24 HRS" beside `/var/log/app.log` and https://example.com/spec
        Use variable {camera_lens} and `<VIDEO_REF_0>` continuity.
        lock: teal patina on brass door
        NOT: watermark, blurry hands
        """
        let lex = PromptLexer().lex(input)

        #expect(lex.rawInput == input)
        #expect(lex.loras.contains("<lora:neon_noir:0.75>"))
        #expect(lex.wildcards.contains("__lighting/cyberpunk__"))
        #expect(lex.variables.contains("camera_lens"))
        #expect(lex.quotedLiterals.contains("OPEN 24 HRS"))
        #expect(lex.spans(of: .qualityScoreTag).map(\.text).contains("score_9"))
        #expect(lex.spans(of: .url).map(\.text).contains("https://example.com/spec"))
        #expect(lex.spans(of: .explicitLock).map(\.normalizedPayload).contains("teal patina on brass door"))
        #expect(lex.spans(of: .negativeDirective).map(\.normalizedPayload).contains("watermark, blurry hands"))
    }

    @Test("Parser extracts separate-image multiplicity and video timeline beats")
    func parserMultiplicityAndVideoBeats() {
        let imagePrompt = "Create 3 separate studio portraits of owls, not a collage. 16:9."
        let parser = SemanticIRParser()
        let imageIR = parser.parse(rawInput: imagePrompt)

        #expect(imageIR.intentKind == .imageGeneration)
        #expect(imageIR.ingredients.separateOutputsRequested == true)
        #expect(imageIR.lexResult.subjectCounts.contains { $0.count == 3 && $0.entity.contains("owl") })
        #expect(imageIR.invariants.contains { $0.kind == .forbidCollageMerge })

        let videoPrompt = """
        [00:00-00:04] Wide dolly in across misty pines at sunrise (Audio: distant owl call).
        [00:04-00:08] Close-up on brass compass opening in gloved hands.
        Dialogue: "Stay on the ridge before dusk."
        """
        let videoIR = parser.parse(rawInput: videoPrompt)
        #expect(videoIR.intentKind == .videoGeneration)
        #expect(videoIR.ingredients.temporalTimeline.count == 2)
        #expect(videoIR.ingredients.temporalTimeline[0].startSeconds == 0)
        #expect(videoIR.ingredients.temporalTimeline[0].endSeconds == 4)
        #expect(videoIR.ingredients.temporalTimeline[1].endSeconds == 8)
        #expect(videoIR.ingredients.audioDialogue.spokenDialogue == ["Stay on the ridge before dusk."])
        #expect(videoIR.ingredients.audioDialogue.requiresLipSync == true)
    }

    @Test("InvariantRegistry catches dropped literal text and affirmative collage injection")
    func invariantCatcher() {
        let parser = SemanticIRParser()
        let ir = parser.parse(rawInput: #"3 separate portraits wearing badges that say "UNIT-7", never a collage."#)
        let registry = InvariantRegistry()

        let brokenResult = registry.verify(
            ir: ir,
            compiledPrompt: "A collage grid of foxes wearing badges.",
            negativePrompt: nil,
            structuredPayloadJSON: "{}"
        )
        #expect(!brokenResult.isClean)
        #expect(brokenResult.violations.count >= 2)
    }

    @Test("StrainProofEngine blocks over-4000 char DexDiffusion controlled prompt")
    func dexDiffusionLengthCapEnforced() {
        let engine = PromptCompilerEngine()
        let oversized = String(repeating: "dramatic volumetric rim lighting across copper arches, ", count: 95)
        let recipe = engine.registry.recipe(for: "dexdiffusion-flux2-klein-4b")!

        let result = engine.compile(
            rawInput: oversized,
            recipe: recipe,
            mixMode: .stirred,
            readiness: .capabilityProven
        )

        #expect(result.proofReport.hasBlockingIssues)
        #expect(result.proofReport.items.contains { $0.severity == .blocking && $0.category == "Length Limit" })
    }

    @Test("StrainProofEngine blocks >5 refs on Grok Image and >15s on Grok Video")
    func providerConstraintBlockingChecks() {
        let engine = PromptCompilerEngine()
        let grokImage = engine.registry.recipe(for: "xai-grok-imagine-image-2.0")!
        let tooManyRefs = (1...6).map {
            ReferenceAsset(label: "ref\($0)", pathOrURI: "/tmp/ref\($0).png", role: .subject)
        }
        let imageResult = engine.compile(
            rawInput: "Editorial sneaker shot",
            recipe: grokImage,
            mixMode: .neat,
            attachedAssets: tooManyRefs
        )
        #expect(imageResult.proofReport.items.contains { $0.severity == .blocking && $0.category == "References" })

        let grokVideo = engine.registry.recipe(for: "xai-grok-imagine-video-1.5")!
        let videoResult = engine.compile(
            rawInput: "[00:00-00:20] Long continuous pan across desert dunes.",
            recipe: grokVideo,
            mixMode: .stirred,
            parameterOverrides: TechnicalParameterSet(durationSeconds: 20)
        )
        #expect(videoResult.proofReport.items.contains { $0.severity == .blocking && $0.category == "Video Duration" })
    }

    @Test("Mix modes Neat, Stirred, and Shaken respect original intent, locks, and semantic diff")
    func mixModesAndSemanticDiff() {
        let engine = PromptCompilerEngine()
        let geminiImg = engine.registry.recipe(for: "google-gemini-nano-banana-2.1")!
        let draft = #"A ceramic teapot beside {flower_type} saying "TEA HOUSE""#

        let neat = engine.compile(rawInput: draft, recipe: geminiImg, mixMode: .neat)
        let stirred = engine.compile(rawInput: draft, recipe: geminiImg, mixMode: .stirred)
        let shaken = engine.compile(
            rawInput: draft,
            recipe: geminiImg,
            mixMode: .shaken,
            variables: ["flower_type": "white jasmine"]
        )

        #expect(neat.compiledPrompt.contains("{flower_type}"))
        #expect(neat.proofReport.items.contains { $0.severity == .warning && $0.category == "Variables" })
        #expect(stirred.compiledPrompt.contains("TEA HOUSE"))
        #expect(shaken.compiledPrompt.contains("white jasmine"))
        #expect(shaken.compiledPrompt.contains("TEA HOUSE"))
        #expect(!shaken.proofReport.hasBlockingIssues)
        #expect(shaken.semanticDiff.preservedLockCount >= 2)
        #expect(shaken.provenance.contains { $0.source == .heuristicTransform })
    }

    @Test("Preserved PromptTextGuards protects code fences during text transforms")
    func upstreamCodeFencePreservation() {
        let input = "Fix bug\n```swift\nlet value = 42\n```\nmaybe cleanly"
        let segments = PromptTextGuards.splitByCodeFences(input)
        let transformed = PromptTextGuards.transformTextSegments(segments) { segment in
            segment.replacingOccurrences(of: "maybe ", with: "")
        }
        #expect(transformed.contains("```swift\nlet value = 42\n```"))
        #expect(!transformed.contains("maybe cleanly"))
    }
}
