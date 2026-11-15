import AppKit
import CoreImage
import ImageIO
import Foundation
import SwiftUI

enum WatermarkBlendOption: String, Codable, CaseIterable, Identifiable {
    case screen = "screen"
    case normal = "normal"
    case overlay = "overlay"
    case softLight = "soft_light"
    case plusLighter = "plus_lighter"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screen: return "Screen"
        case .normal: return "Normal"
        case .overlay: return "Overlay"
        case .softLight: return "Soft Light"
        case .plusLighter: return "Additive Glow"
        }
    }

    var swiftUIBlendMode: BlendMode {
        switch self {
        case .screen: return .screen
        case .normal: return .normal
        case .overlay: return .overlay
        case .softLight: return .softLight
        case .plusLighter: return .plusLighter
        }
    }
}

enum BackdropContentMode: String, Codable, CaseIterable, Identifiable {
    case fill = "fill"
    case fit = "fit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fill: return "Fill Window"
        case .fit: return "Fit Whole Image"
        }
    }
}

struct AppearanceSettings: Codable, Equatable {
    var isWatermarkEnabled: Bool
    var customWatermarkPath: String
    var watermarkOpacity: Double
    var watermarkScale: Double
    var watermarkBlendMode: WatermarkBlendOption

    var isBackdropImageEnabled: Bool
    var customBackdropImagePath: String
    var backdropOpacity: Double
    var backdropBlur: Double
    var backdropContentMode: BackdropContentMode

    var glassTintOpacity: Double

    static let `default` = AppearanceSettings(
        isWatermarkEnabled: true,
        customWatermarkPath: "",
        watermarkOpacity: 0.72,
        watermarkScale: 1.0,
        watermarkBlendMode: .screen,
        isBackdropImageEnabled: false,
        customBackdropImagePath: "",
        backdropOpacity: 0.35,
        backdropBlur: 0.0,
        backdropContentMode: .fill,
        glassTintOpacity: 0.16
    )
}

@MainActor
final class AppearanceSettingsStore: ObservableObject {
    @Published var settings: AppearanceSettings {
        didSet { scheduleSave() }
    }
    @Published private(set) var persistenceError: String?
    private var pendingSave: Task<Void, Never>?
    private let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 3
        return cache
    }()
    private let blurredBackdropCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 3
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    private let blurContext = CIContext(options: [.cacheIntermediates: false])

    private let fileURL: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(appFolderName: String = "DexPromptender") {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent(appFolderName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("appearance-settings.json")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.settings = Self.load(from: fileURL, decoder: decoder) ?? .default
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.settings = Self.load(from: fileURL, decoder: decoder) ?? .default
    }

    func resetToDefaults() {
        settings = .default
    }

    // UI responds immediately; only persistence is coalesced. Explicit flush
    // is used when quitting to preserve the most recent slider value.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        persist()
    }

    func cachedImage(at path: String) -> NSImage? {
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, fileManager.fileExists(atPath: clean) else { return nil }
        let modified = (try? fileManager.attributesOfItem(atPath: clean)[.modificationDate] as? Date)
            ?? Date.distantPast
        let cacheKey = "\(clean)#\(modified.timeIntervalSince1970)" as NSString
        if let existing = imageCache.object(forKey: cacheKey) { return existing }
        guard let decoded = NSImage(contentsOfFile: clean) else { return nil }
        imageCache.setObject(decoded, forKey: cacheKey)
        return decoded
    }

    // Pre-render the blur into an image so macOS offscreen and real-window
    // drawing use the same deterministic pixels. Do not modify source files.
    // Thumbnails are bounded to protect low-memory MacBooks during slider drags.
    func preparedBackdropImage(at path: String, blurRadius: Double) -> NSImage? {
        guard let source = cachedImage(at: path) else { return nil }
        let radius = Int(blurRadius.rounded())
        guard radius > 0 else { return source }

        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = (try? fileManager.attributesOfItem(atPath: clean)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let cacheKey = "\(clean)#\(stamp)#blur:\(radius)" as NSString
        if let cached = blurredBackdropCache.object(forKey: cacheKey) {
            return cached
        }

        let url = URL(fileURLWithPath: clean)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                  imageSource, 0, options as CFDictionary
              ) else { return source }

        let input = CIImage(cgImage: thumbnail)
        let filtered = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        guard let output = blurContext.createCGImage(filtered, from: input.extent) else {
            return source
        }
        let prepared = NSImage(
            cgImage: output,
            size: NSSize(width: output.width, height: output.height)
        )
        blurredBackdropCache.setObject(
            prepared,
            forKey: cacheKey,
            cost: output.width * output.height * 4
        )
        return prepared
    }

    func imageLoadIssue(for path: String, label: String, required: Bool) -> String? {
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return required ? "Choose a \(label) image to see its effect." : nil
        }
        guard fileManager.isReadableFile(atPath: clean) else {
            return "\(label.capitalized) image is missing or unreadable. Choose another file."
        }
        guard cachedImage(at: clean) != nil else {
            return "\(label.capitalized) image could not be decoded. Choose a supported image."
        }
        return nil
    }

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoded = try encoder.encode(settings)
            try encoded.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> AppearanceSettings? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let loaded = try? decoder.decode(AppearanceSettings.self, from: data) else {
            return nil
        }
        return loaded
    }
}
