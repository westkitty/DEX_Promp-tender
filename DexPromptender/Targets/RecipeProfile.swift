import Foundation

struct RecipeConstraints: Equatable, Codable {
    var maxPromptCharacters: Int?
    var maxNegativeCharacters: Int?
    var maxReferenceAssets: Int
    var maxVoiceReferences: Int
    var supportedAspectRatios: [String]
    var supportedResolutions: [String]
    var minDurationSeconds: Double?
    var maxDurationSeconds: Double?
    var supportsNegativePromptField: Bool
    var supportsMaskEditing: Bool
    var supportsVideoEditTokens: Bool
    var supportsJSONSchemaOutput: Bool

    init(
        maxPromptCharacters: Int? = nil,
        maxNegativeCharacters: Int? = nil,
        maxReferenceAssets: Int = 0,
        maxVoiceReferences: Int = 0,
        supportedAspectRatios: [String] = [],
        supportedResolutions: [String] = [],
        minDurationSeconds: Double? = nil,
        maxDurationSeconds: Double? = nil,
        supportsNegativePromptField: Bool = false,
        supportsMaskEditing: Bool = false,
        supportsVideoEditTokens: Bool = false,
        supportsJSONSchemaOutput: Bool = false
    ) {
        self.maxPromptCharacters = maxPromptCharacters
        self.maxNegativeCharacters = maxNegativeCharacters
        self.maxReferenceAssets = maxReferenceAssets
        self.maxVoiceReferences = maxVoiceReferences
        self.supportedAspectRatios = supportedAspectRatios
        self.supportedResolutions = supportedResolutions
        self.minDurationSeconds = minDurationSeconds
        self.maxDurationSeconds = maxDurationSeconds
        self.supportsNegativePromptField = supportsNegativePromptField
        self.supportsMaskEditing = supportsMaskEditing
        self.supportsVideoEditTokens = supportsVideoEditTokens
        self.supportsJSONSchemaOutput = supportsJSONSchemaOutput
    }
}

struct RecipeProfile: Identifiable, Equatable, Codable, Hashable {
    var id: String
    var version: String
    var name: String
    var destination: TargetDestination
    var modelID: String
    var subtitle: String
    var promptDialectNote: String
    var defaultMixMode: MixMode
    var systemPrelude: String
    var styleSuffix: String
    var defaultNegativePrompt: String
    var isBuiltIn: Bool
    var constraints: RecipeConstraints

    static func == (lhs: RecipeProfile, rhs: RecipeProfile) -> Bool {
        lhs.id == rhs.id && lhs.version == rhs.version && lhs.modelID == rhs.modelID && lhs.destination == rhs.destination && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(version)
        hasher.combine(modelID)
    }
}

/// Manages built-in versioned Recipes and user-authored House Specials persisted in Application Support.
final class RecipeStore {
    private let fileURL: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(appFolderName: String = "DexPromptender") {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent(appFolderName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("house-specials-recipes.json")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    init(storageDirectoryURL: URL) {
        try? fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        self.fileURL = storageDirectoryURL.appendingPathComponent("house-specials-recipes.json")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    func loadCustomRecipes() -> [RecipeProfile] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let items = try? decoder.decode([RecipeProfile].self, from: data) else {
            return []
        }
        return items
    }

    func saveCustomRecipes(_ recipes: [RecipeProfile]) {
        guard let data = try? encoder.encode(recipes.filter { !$0.isBuiltIn }) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func upsertCustomRecipe(_ recipe: RecipeProfile) -> [RecipeProfile] {
        var existing = loadCustomRecipes()
        var mutable = recipe
        mutable.isBuiltIn = false
        if let idx = existing.firstIndex(where: { $0.id == mutable.id }) {
            existing[idx] = mutable
        } else {
            existing.insert(mutable, at: 0)
        }
        saveCustomRecipes(existing)
        return existing
    }

    func deleteCustomRecipe(id: String) -> [RecipeProfile] {
        let filtered = loadCustomRecipes().filter { $0.id != id }
        saveCustomRecipes(filtered)
        return filtered
    }
}
