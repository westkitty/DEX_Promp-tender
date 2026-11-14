import Foundation

/// Universal offline-first prompt compiler pipeline orchestrator.
final class PromptCompilerEngine {
    let parser: SemanticIRParser
    let registry: TargetProfileRegistry
    let proofEngine: StrainProofEngine
    let diffEngine: SemanticDiffEngine
    private let compilers: [TargetDestination: TargetRecipeCompiler]

    init(
        parser: SemanticIRParser = SemanticIRParser(),
        registry: TargetProfileRegistry = TargetProfileRegistry(),
        proofEngine: StrainProofEngine = StrainProofEngine(),
        diffEngine: SemanticDiffEngine = SemanticDiffEngine()
    ) {
        self.parser = parser
        self.registry = registry
        self.proofEngine = proofEngine
        self.diffEngine = diffEngine

        let allCompilers: [TargetRecipeCompiler] = [
            DexDiffusionCompiler(),
            GrokImagineCompiler(),
            OpenAICompiler(),
            GeminiCompiler(),
            TextAgentLegacyCompiler()
        ]
        var table: [TargetDestination: TargetRecipeCompiler] = [:]
        for compiler in allCompilers {
            for dest in compiler.supportedDestinations {
                table[dest] = compiler
            }
        }
        self.compilers = table
    }

    func compile(
        rawInput: String,
        recipe: RecipeProfile,
        mixMode: MixMode,
        hintedIntent: IntentKind? = nil,
        attachedAssets: [ReferenceAsset] = [],
        parameterOverrides: TechnicalParameterSet = TechnicalParameterSet(),
        manualLocks: [String] = [],
        variables: [String: String] = [:],
        legacyOptions: EnhancementOptions = EnhancementOptions(),
        readiness: ReadinessState = .sourceImplemented
    ) -> CompilationResult {
        let ir = parser.parse(
            rawInput: rawInput,
            hintedIntent: hintedIntent,
            attachedAssets: attachedAssets,
            parameterOverrides: parameterOverrides,
            manualLocks: manualLocks
        )
        return compile(
            ir: ir,
            recipe: recipe,
            mixMode: mixMode,
            variables: variables,
            legacyOptions: legacyOptions,
            readiness: readiness
        )
    }

    func compile(
        ir: CanonicalPromptIR,
        recipe: RecipeProfile,
        mixMode: MixMode,
        variables: [String: String] = [:],
        legacyOptions: EnhancementOptions = EnhancementOptions(),
        readiness: ReadinessState = .sourceImplemented
    ) -> CompilationResult {
        let startedAt = Date()
        let compiler = compilers[recipe.destination] ?? TextAgentLegacyCompiler()

        let draft = compiler.compile(
            ir: ir,
            recipe: recipe,
            mixMode: mixMode,
            variables: variables,
            legacyOptions: legacyOptions
        )

        let invariantResult = InvariantRegistry().verify(
            ir: ir,
            compiledPrompt: draft.compiledPrompt,
            negativePrompt: draft.negativePrompt,
            structuredPayloadJSON: draft.structuredPayloadJSON,
            systemInstructions: draft.systemInstructions
        )

        let proofReport = proofEngine.validate(
            ir: ir,
            recipe: recipe,
            compiledPrompt: draft.compiledPrompt,
            negativePrompt: draft.negativePrompt,
            systemInstructions: draft.systemInstructions,
            structuredPayloadJSON: draft.structuredPayloadJSON,
            resolvedParameters: draft.resolvedParameters,
            readiness: readiness
        )

        let semanticDiff = diffEngine.buildDiff(
            ir: ir,
            compiledPrompt: draft.compiledPrompt,
            negativePrompt: draft.negativePrompt,
            structuredPayloadJSON: draft.structuredPayloadJSON,
            provenance: draft.provenance,
            invariantResult: invariantResult
        )

        let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000.0))

        return CompilationResult(
            id: UUID(),
            target: recipe.destination,
            modelID: recipe.modelID,
            recipeVersion: recipe.version,
            mixMode: mixMode,
            compiledPrompt: draft.compiledPrompt,
            negativePrompt: draft.negativePrompt,
            systemInstructions: draft.systemInstructions,
            structuredPayloadJSON: draft.structuredPayloadJSON,
            recommendedParameters: draft.recommendedParameters,
            provenance: draft.provenance,
            proofReport: proofReport,
            semanticDiff: semanticDiff,
            readiness: readiness,
            compilationDurationMs: durationMs
        )
    }
}
