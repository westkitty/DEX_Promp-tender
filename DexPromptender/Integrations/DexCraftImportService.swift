import Foundation

struct DexCraftImportReport: Equatable {
    let sourceDirectoryPath: String
    let destinationDirectoryPath: String
    let backupDirectoryPath: String?
    let templatesImported: Int
    let templatesSkippedDuplicates: Int
    let historyImported: Int
    let historySkippedDuplicates: Int
    let libraryPromptsImported: Int
    let libraryPromptsSkippedDuplicates: Int
    let settingsImported: Bool
    let optimizerWeightsImported: Bool
    let warnings: [String]

    var summaryLine: String {
        "Imported \(templatesImported) templates, \(historyImported) history entries, \(libraryPromptsImported) library prompts (skipped \(templatesSkippedDuplicates + historySkippedDuplicates + libraryPromptsSkippedDuplicates) duplicates)."
    }
}

/// Optional, non-destructive read-only migration importer from legacy `~/Library/Application Support/DexCraft/`
/// into isolated `~/Library/Application Support/DexPromptender/`.
final class DexCraftImportService {
    private let fileManager = FileManager.default
    private let sourceDirURL: URL
    private let destinationDirURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        sourceDirURL: URL? = nil,
        destinationDirURL: URL? = nil
    ) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        self.sourceDirURL = sourceDirURL ?? appSupport.appendingPathComponent("DexCraft", isDirectory: true)
        self.destinationDirURL = destinationDirURL ?? appSupport.appendingPathComponent("DexPromptender", isDirectory: true)

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func canDiscoverSource() -> Bool {
        fileManager.fileExists(atPath: sourceDirURL.path)
    }

    func importLegacyData(overwriteExistingSettings: Bool = false) throws -> DexCraftImportReport {
        guard canDiscoverSource() else {
            return DexCraftImportReport(
                sourceDirectoryPath: sourceDirURL.path,
                destinationDirectoryPath: destinationDirURL.path,
                backupDirectoryPath: nil,
                templatesImported: 0,
                templatesSkippedDuplicates: 0,
                historyImported: 0,
                historySkippedDuplicates: 0,
                libraryPromptsImported: 0,
                libraryPromptsSkippedDuplicates: 0,
                settingsImported: false,
                optimizerWeightsImported: false,
                warnings: ["Legacy DexCraft Application Support directory not found at \(sourceDirURL.path)."]
            )
        }

        try fileManager.createDirectory(at: destinationDirURL, withIntermediateDirectories: true)
        let backupURL = try createDestinationBackupIfNeeded()
        var warnings: [String] = []

        // 1. Templates (dedup by id or normalized name+content)
        var templatesImported = 0
        var templatesSkipped = 0
        let legacyTemplatesURL = sourceDirURL.appendingPathComponent("templates.json")
        if fileManager.fileExists(atPath: legacyTemplatesURL.path) {
            do {
                let data = try Data(contentsOf: legacyTemplatesURL)
                let legacyTemplates = try decoder.decode([PromptTemplate].self, from: data)
                let destTemplatesURL = destinationDirURL.appendingPathComponent("templates.json")
                var existing: [PromptTemplate] = []
                if fileManager.fileExists(atPath: destTemplatesURL.path),
                   let existingData = try? Data(contentsOf: destTemplatesURL),
                   let decodedExisting = try? decoder.decode([PromptTemplate].self, from: existingData) {
                    existing = decodedExisting
                }

                var seenIDs = Set(existing.map(\.id))
                var seenKeys = Set(existing.map { "\($0.name.lowercased())|\($0.content.trimmingCharacters(in: .whitespacesAndNewlines))" })

                for item in legacyTemplates {
                    let key = "\(item.name.lowercased())|\(item.content.trimmingCharacters(in: .whitespacesAndNewlines))"
                    if seenIDs.contains(item.id) || seenKeys.contains(key) {
                        templatesSkipped += 1
                    } else {
                        existing.append(item)
                        seenIDs.insert(item.id)
                        seenKeys.insert(key)
                        templatesImported += 1
                    }
                }
                if templatesImported > 0 {
                    let outData = try encoder.encode(existing)
                    try outData.write(to: destTemplatesURL, options: .atomic)
                }
            } catch {
                warnings.append("templates.json skipped: \(error.localizedDescription)")
            }
        }

        // 2. History (dedup by id or target+originalInput+generatedPrompt)
        var historyImported = 0
        var historySkipped = 0
        let legacyHistoryURL = sourceDirURL.appendingPathComponent("history.json")
        if fileManager.fileExists(atPath: legacyHistoryURL.path) {
            do {
                let data = try Data(contentsOf: legacyHistoryURL)
                let legacyHistory = try decoder.decode([PromptHistoryEntry].self, from: data)
                let destHistoryURL = destinationDirURL.appendingPathComponent("history.json")
                var existing: [PromptHistoryEntry] = []
                if fileManager.fileExists(atPath: destHistoryURL.path),
                   let existingData = try? Data(contentsOf: destHistoryURL),
                   let decodedExisting = try? decoder.decode([PromptHistoryEntry].self, from: existingData) {
                    existing = decodedExisting
                }

                var seenIDs = Set(existing.map(\.id))
                var seenSigs = Set(existing.map { "\($0.target.rawValue)|\($0.originalInput)|\($0.generatedPrompt)" })

                for entry in legacyHistory {
                    let sig = "\(entry.target.rawValue)|\(entry.originalInput)|\(entry.generatedPrompt)"
                    if seenIDs.contains(entry.id) || seenSigs.contains(sig) {
                        historySkipped += 1
                    } else {
                        existing.append(entry)
                        seenIDs.insert(entry.id)
                        seenSigs.insert(sig)
                        historyImported += 1
                    }
                }
                if historyImported > 0 {
                    let sorted = existing.sorted { $0.timestamp > $1.timestamp }
                    let capped = Array(sorted.prefix(200))
                    let outData = try encoder.encode(capped)
                    try outData.write(to: destHistoryURL, options: .atomic)
                }
            } catch {
                warnings.append("history.json skipped: \(error.localizedDescription)")
            }
        }

        // 3. Prompt Library (dedup categories, tags, prompts)
        var libraryImported = 0
        var librarySkipped = 0
        let legacyLibraryURL = sourceDirURL.appendingPathComponent("prompt-library.json")
        if fileManager.fileExists(atPath: legacyLibraryURL.path) {
            do {
                let data = try Data(contentsOf: legacyLibraryURL)
                let legacyBundle = try decoder.decode(PromptLibraryBundle.self, from: data)
                let destLibraryURL = destinationDirURL.appendingPathComponent("prompt-library.json")
                var destBundle = PromptLibraryBundle.empty
                if fileManager.fileExists(atPath: destLibraryURL.path),
                   let existingData = try? Data(contentsOf: destLibraryURL),
                   let decoded = try? decoder.decode(PromptLibraryBundle.self, from: existingData) {
                    destBundle = decoded
                }

                var seenPromptIDs = Set(destBundle.prompts.map(\.id))
                var seenCatIDs = Set(destBundle.categories.map(\.id))
                var seenTagIDs = Set(destBundle.tags.map(\.id))

                for cat in legacyBundle.categories where seenCatIDs.insert(cat.id).inserted {
                    destBundle.categories.append(cat)
                }
                for tag in legacyBundle.tags where seenTagIDs.insert(tag.id).inserted {
                    destBundle.tags.append(tag)
                }
                for prompt in legacyBundle.prompts {
                    if seenPromptIDs.insert(prompt.id).inserted {
                        destBundle.prompts.append(prompt)
                        libraryImported += 1
                    } else {
                        librarySkipped += 1
                    }
                }
                if libraryImported > 0 || !legacyBundle.categories.isEmpty || !legacyBundle.tags.isEmpty {
                    let outData = try encoder.encode(destBundle)
                    try outData.write(to: destLibraryURL, options: .atomic)
                }
            } catch {
                warnings.append("prompt-library.json skipped: \(error.localizedDescription)")
            }
        }

        // 4. Connected model settings & optimizer weights (copy only if missing or overwrite explicitly opted in)
        let settingsImported = copyOptionalJSONFile(
            filename: "connected-model-settings.json",
            overwrite: overwriteExistingSettings,
            warnings: &warnings
        )
        let weightsImported = copyOptionalJSONFile(
            filename: "optimizer-weights.json",
            overwrite: overwriteExistingSettings,
            warnings: &warnings
        )

        return DexCraftImportReport(
            sourceDirectoryPath: sourceDirURL.path,
            destinationDirectoryPath: destinationDirURL.path,
            backupDirectoryPath: backupURL?.path,
            templatesImported: templatesImported,
            templatesSkippedDuplicates: templatesSkipped,
            historyImported: historyImported,
            historySkippedDuplicates: historySkipped,
            libraryPromptsImported: libraryImported,
            libraryPromptsSkippedDuplicates: librarySkipped,
            settingsImported: settingsImported,
            optimizerWeightsImported: weightsImported,
            warnings: warnings
        )
    }

    private func copyOptionalJSONFile(filename: String, overwrite: Bool, warnings: inout [String]) -> Bool {
        let src = sourceDirURL.appendingPathComponent(filename)
        let dst = destinationDirURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: src.path) else { return false }
        if fileManager.fileExists(atPath: dst.path) && !overwrite {
            return false
        }
        do {
            let data = try Data(contentsOf: src)
            _ = try JSONSerialization.jsonObject(with: data)
            try data.write(to: dst, options: .atomic)
            return true
        } catch {
            warnings.append("\(filename) skipped: \(error.localizedDescription)")
            return false
        }
    }

    private func createDestinationBackupIfNeeded() throws -> URL? {
        let targetFiles = [
            "templates.json",
            "history.json",
            "prompt-library.json",
            "connected-model-settings.json",
            "optimizer-weights.json"
        ]
        let existingFiles = targetFiles.filter {
            fileManager.fileExists(atPath: destinationDirURL.appendingPathComponent($0).path)
        }
        guard !existingFiles.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupDir = destinationDirURL
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("pre-import-\(stamp)", isDirectory: true)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        for name in existingFiles {
            let src = destinationDirURL.appendingPathComponent(name)
            let dst = backupDir.appendingPathComponent(name)
            try fileManager.copyItem(at: src, to: dst)
        }
        return backupDir
    }
}
