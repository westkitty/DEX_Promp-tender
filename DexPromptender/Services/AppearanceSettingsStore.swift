import AppKit
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
        didSet { persist() }
    }

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

    private func persist() {
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
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
