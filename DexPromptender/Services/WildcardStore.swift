import Foundation

enum WildcardSourceKind: String, Codable, Hashable {
    case builtIn = "built_in"
    case localUser = "local_user"
    case syncedFolder = "synced_folder"
    case dexterFusion = "dexter_fusion"

    var badgeLabel: String {
        switch self {
        case .builtIn: return "Built-In"
        case .localUser: return "Local Custom"
        case .syncedFolder: return "Synced Folder"
        case .dexterFusion: return "Dexter Fusion"
        }
    }
}

struct WildcardBankRecord: Identifiable, Codable, Equatable, Hashable {
    var id: String { name.lowercased() }
    var name: String
    var items: [String]
    var description: String
    var tags: [String]
    var source: WildcardSourceKind
    var isFullDetailLoaded: Bool
    var previewCount: Int

    var count: Int {
        items.isEmpty ? previewCount : items.count
    }

    init(
        name: String,
        items: [String],
        description: String = "",
        tags: [String] = [],
        source: WildcardSourceKind,
        isFullDetailLoaded: Bool = true,
        previewCount: Int? = nil
    ) {
        self.name = name
        self.items = items
        self.description = description
        self.tags = tags
        self.source = source
        self.isFullDetailLoaded = isFullDetailLoaded
        self.previewCount = previewCount ?? items.count
    }
}

enum WildcardMutationError: LocalizedError {
    case invalidName
    case protectedBuiltIn(String)
    case syncFolderUnavailable
    case ambiguousCopy(String)
    case unsafeSymbolicLink(String)
    case overwriteNotAuthorized(String)
    case noSelectedCopies(String)
    case concurrentRemoteChange(String)
    case partialDelete(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Invalid wildcard bank name."
        case .protectedBuiltIn(let name): return "Built-in bank \(name) is read-only. Duplicate it under a new name."
        case .syncFolderUnavailable: return "The configured synced wildcard directory is not available."
        case .ambiguousCopy(let name): return "Multiple case-variant copies of \(name) exist. Resolve the conflict before writing."
        case .unsafeSymbolicLink(let name): return "Refusing to modify symbolic-link wildcard file \(name)."
        case .overwriteNotAuthorized(let destination): return "Overwriting the existing \(destination) bank requires explicit approval."
        case .noSelectedCopies(let name): return "No selected local/synced copies exist for \(name)."
        case .concurrentRemoteChange(let name): return "Remote bank \(name) changed since preflight; refusing a stale remote write/delete."
        case .partialDelete(let detail): return "Partial wildcard deletion: \(detail)"
        }
    }
}

struct WildcardSyncConfig: Codable, Equatable {
    var externalSyncDirectoryPath: String
    var lastSyncedAt: Date?

    init(externalSyncDirectoryPath: String = "", lastSyncedAt: Date? = nil) {
        self.externalSyncDirectoryPath = externalSyncDirectoryPath
        self.lastSyncedAt = lastSyncedAt
    }
}

/// Manages built-in wildcard `.txt` banks, local edits, external Dexter Fusion wildcard folders,
/// and live HTTP sync against `127.0.0.1:31337/api/wildcards` using matching `# description:` / `# tags:` syntax.
final class WildcardStore {
    static let bankNameRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,120}$")
    static let tokenRegex = try! NSRegularExpression(pattern: "__([a-zA-Z0-9_-]+)__")

    private let fileManager = FileManager.default
    private let localDirURL: URL
    private let configURL: URL
    private let bundledDirURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        appFolderName: String = "DexPromptender",
        bundledDirURL: URL? = AppBundleResources.wildcardsDirectoryURL()
    ) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let appDir = base.appendingPathComponent(appFolderName, isDirectory: true)
        self.localDirURL = appDir.appendingPathComponent("Wildcards", isDirectory: true)
        self.configURL = appDir.appendingPathComponent("wildcard-sync.json")
        self.bundledDirURL = bundledDirURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        try? fileManager.createDirectory(at: localDirURL, withIntermediateDirectories: true)
    }

    init(storageDirectoryURL: URL, bundledDirURL: URL? = AppBundleResources.wildcardsDirectoryURL()) {
        self.localDirURL = storageDirectoryURL.appendingPathComponent("Wildcards", isDirectory: true)
        self.configURL = storageDirectoryURL.appendingPathComponent("wildcard-sync.json")
        self.bundledDirURL = bundledDirURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        try? fileManager.createDirectory(at: localDirURL, withIntermediateDirectories: true)
    }

    func loadSyncConfig() -> WildcardSyncConfig {
        guard fileManager.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let cfg = try? decoder.decode(WildcardSyncConfig.self, from: data) else {
            return WildcardSyncConfig()
        }
        return cfg
    }

    func saveSyncConfig(_ config: WildcardSyncConfig) {
        try? fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    /// Loads merged banks with precedence:
    /// built-in bundle < optional synced external folder < local DexPromptender edited/cached banks.
    func loadAllLocalBanks() -> [WildcardBankRecord] {
        var map: [String: WildcardBankRecord] = [:]

        if let bundledDir = bundledDirURL {
            for bank in readBanks(from: bundledDir, source: .builtIn) {
                map[bank.id] = bank
            }
        }

        let syncPath = loadSyncConfig().externalSyncDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !syncPath.isEmpty {
            let syncURL = URL(fileURLWithPath: syncPath, isDirectory: true)
            for bank in readBanks(from: syncURL, source: .syncedFolder) {
                map[bank.id] = bank
            }
        }

        for bank in readBanks(from: localDirURL, source: .localUser) {
            map[bank.id] = bank
        }

        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func saveBankLocally(
        name: String,
        items: [String],
        description: String,
        tags: [String],
        source: WildcardSourceKind = .localUser
    ) throws -> WildcardBankRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidBankName(trimmedName) else {
            throw NSError(domain: "WildcardStore", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Bank names may contain letters, numbers, _ and - (max 120 chars)."
            ])
        }

        guard !isBundledBank(name: trimmedName) else {
            throw WildcardMutationError.protectedBuiltIn(trimmedName)
        }
        let cleanItems = sanitizeItems(items)
        let content = serializeBankFile(items: cleanItems, description: description, tags: tags)

        try fileManager.createDirectory(at: localDirURL, withIntermediateDirectories: true)
        let existing = try matchingFiles(in: localDirURL, name: trimmedName)
        guard existing.count <= 1 else { throw WildcardMutationError.ambiguousCopy(trimmedName) }
        if let old = existing.first {
            try backupFile(at: old, origin: "local")
        }
        let localFile = existing.first ?? localDirURL.appendingPathComponent("\(trimmedName).txt")
        try content.write(to: localFile, atomically: true, encoding: .utf8)

        return WildcardBankRecord(
            name: trimmedName,
            items: cleanItems,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            source: source,
            isFullDetailLoaded: true,
            previewCount: cleanItems.count
        )
    }


    // Built-in banks are immutable. A local/folder/remote bank with the same name
    // does not grant permission to delete the bundled recipe.
    func isBundledBank(name: String) -> Bool {
        guard isValidBankName(name), let dir = bundledDirURL else { return false }
        return ((try? matchingFiles(in: dir, name: name)) ?? []).isEmpty == false
    }

    func hasLocalBank(name: String) -> Bool {
        guard isValidBankName(name) else { return false }
        return ((try? matchingFiles(in: localDirURL, name: name)) ?? []).isEmpty == false
    }

    func hasSyncedBank(name: String) -> Bool {
        guard isValidBankName(name),
              let dir = configuredSyncDirectory() else { return false }
        return ((try? matchingFiles(in: dir, name: name)) ?? []).isEmpty == false
    }

    var hasConfiguredSyncFolder: Bool { configuredSyncDirectory() != nil }

    // Back up all selected existing local files BEFORE deleting any copy.
    // Never touch bundled resources. The caller separately authorizes and
    // performs any remote action after creating a remote backup.
    func deleteBankCopies(name: String, local: Bool, syncedFolder: Bool) throws -> [String] {
        guard isValidBankName(name) else { throw WildcardMutationError.invalidName }
        guard !isBundledBank(name: name) else { throw WildcardMutationError.protectedBuiltIn(name) }
        var selected: [(URL, String)] = []
        if local {
            selected += try matchingFiles(in: localDirURL, name: name).map { ($0, "local") }
        }
        if syncedFolder {
            guard let dir = configuredSyncDirectory() else { throw WildcardMutationError.syncFolderUnavailable }
            selected += try matchingFiles(in: dir, name: name).map { ($0, "folder") }
        }
        guard !selected.isEmpty || (!local && !syncedFolder) else {
            throw WildcardMutationError.noSelectedCopies(name)
        }
        for (file, origin) in selected {
            try backupFile(at: file, origin: origin)
        }
        var removed: [String] = []
        for (file, origin) in selected {
            do {
                try fileManager.removeItem(at: file)
                removed.append(origin)
            } catch {
                throw WildcardMutationError.partialDelete(
                    "\(removed.joined(separator: ", ")) completed; \(origin) failed: \(error.localizedDescription). Restorable backups are in WildcardBackups."
                )
            }
        }
        return removed
    }

    func mirrorBankToSyncFolder(
        name: String,
        items: [String],
        description: String,
        tags: [String],
        allowOverwrite: Bool
    ) throws -> String {
        guard isValidBankName(name) else { throw WildcardMutationError.invalidName }
        guard !isBundledBank(name: name) else { throw WildcardMutationError.protectedBuiltIn(name) }
        guard let dir = configuredSyncDirectory() else { throw WildcardMutationError.syncFolderUnavailable }
        let content = serializeBankFile(items: sanitizeItems(items), description: description, tags: tags)
        let existing = try matchingFiles(in: dir, name: name)
        guard existing.count <= 1 else { throw WildcardMutationError.ambiguousCopy(name) }
        if let old = existing.first {
            let oldContent = try String(contentsOf: old, encoding: .utf8)
            if oldContent == content { return "unchanged" }
            guard allowOverwrite else { throw WildcardMutationError.overwriteNotAuthorized("synced folder") }
            try backupFile(at: old, origin: "folder")
        }
        let target = existing.first ?? dir.appendingPathComponent("\(name).txt")
        try content.write(to: target, atomically: true, encoding: .utf8)
        return "updated"
    }

    @discardableResult
    func backupRemoteBank(
        name: String,
        items: [String],
        description: String,
        tags: [String]
    ) throws -> URL {
        guard isValidBankName(name) else { throw WildcardMutationError.invalidName }
        let dir = backupDirectory()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("remote-\(UUID().uuidString)-\(name).txt")
        try serializeBankFile(items: items, description: description, tags: tags)
            .write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    func canMirrorWithoutOverwrite(name: String, items: [String], description: String, tags: [String]) throws -> Bool {
        guard isValidBankName(name) else { throw WildcardMutationError.invalidName }
        guard let dir = configuredSyncDirectory() else { throw WildcardMutationError.syncFolderUnavailable }
        let existing = try matchingFiles(in: dir, name: name)
        guard existing.count <= 1 else { throw WildcardMutationError.ambiguousCopy(name) }
        guard let old = existing.first else { return true }
        let original = try String(contentsOf: old, encoding: .utf8)
        return original == serializeBankFile(items: sanitizeItems(items), description: description, tags: tags)
    }

    private func configuredSyncDirectory() -> URL? {
        let path = loadSyncConfig().externalSyncDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url
    }

    private func matchingFiles(in directory: URL, name: String) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        let matches = entries.filter {
            $0.pathExtension.lowercased() == "txt"
            && $0.deletingPathExtension().lastPathComponent.lowercased() == name.lowercased()
        }
        for file in matches {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw WildcardMutationError.unsafeSymbolicLink(file.lastPathComponent)
            }
        }
        return matches
    }

    func wildcardBackupDirectoryURL() -> URL { backupDirectory() }

    private func backupDirectory() -> URL {
        localDirURL.deletingLastPathComponent().appendingPathComponent("WildcardBackups", isDirectory: true)
    }

    @discardableResult
    private func backupFile(at source: URL, origin: String) throws -> URL {
        let dir = backupDirectory()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("\(origin)-\(UUID().uuidString)-\(source.lastPathComponent)")
        try fileManager.copyItem(at: source, to: target)
        return target
    }

    func isValidBankName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return Self.bankNameRegex.firstMatch(in: name, range: range) != nil
    }

    func sanitizeItems(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var clean: [String] = []
        for raw in items {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let lower = trimmed.lowercased()
            guard seen.insert(lower).inserted else { continue }
            clean.append(trimmed)
        }
        return clean
    }

    /// Recursive `__bank__` wildcard expansion matching Dexter Fusion's `wildcards.js` semantics
    /// (case-insensitive bank lookup, up to maxDepth iterations, preserving unknown tokens verbatim).
    func expandTokens(in prompt: String, banks: [WildcardBankRecord], maxDepth: Int = 6, seed: UInt64? = nil) -> String {
        guard !prompt.isEmpty else { return prompt }
        let byKey = Dictionary(uniqueKeysWithValues: banks.map { ($0.id, $0.items) })
        var rng = SeededGenerator(seed: seed ?? UInt64(Date().timeIntervalSince1970 * 1000))
        var working = prompt

        for _ in 0..<maxDepth {
            let before = working
            let ns = working as NSString
            let matches = Self.tokenRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { break }

            var replaced = working
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let tokenKey = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let candidates = byKey[tokenKey], !candidates.isEmpty,
                      let swiftRange = Range(match.range, in: replaced) else {
                    continue
                }
                let index = Int(rng.next() % UInt64(candidates.count))
                replaced.replaceSubrange(swiftRange, with: candidates[index])
            }
            working = replaced
            if working == before { break }
        }
        return working
    }

    func parseBankFile(at fileURL: URL, source: WildcardSourceKind) -> WildcardBankRecord? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let name = fileURL.deletingPathExtension().lastPathComponent
        var description = ""
        var tags: [String] = []
        var items: [String] = []
        var readingHeader = true

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if readingHeader {
                    let body = line.drop(while: { $0 == "#" || $0 == " " })
                    let bodyStr = String(body)
                    if bodyStr.lowercased().hasPrefix("description:") {
                        description = bodyStr.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
                    } else if bodyStr.lowercased().hasPrefix("tags:") {
                        tags = bodyStr.dropFirst("tags:".count)
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    } else if description.isEmpty {
                        description = bodyStr
                    }
                }
                continue
            }
            readingHeader = false
            items.append(line)
        }

        return WildcardBankRecord(
            name: name,
            items: sanitizeItems(items),
            description: description,
            tags: tags,
            source: source,
            isFullDetailLoaded: true,
            previewCount: items.count
        )
    }

    private func readBanks(from directory: URL, source: WildcardSourceKind) -> [WildcardBankRecord] {
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.pathExtension.lowercased() == "txt" && !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { parseBankFile(at: $0, source: source) }
    }

    private func serializeBankFile(items: [String], description: String, tags: [String]) -> String {
        var lines: [String] = []
        let cleanDesc = description.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDesc.isEmpty {
            lines.append("# description: \(cleanDesc)")
        }
        let cleanTags = tags
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanTags.isEmpty {
            lines.append("# tags: \(cleanTags.joined(separator: ", "))")
        }
        lines.append(contentsOf: items)
        return lines.joined(separator: "\n") + "\n"
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 16
    }
}
