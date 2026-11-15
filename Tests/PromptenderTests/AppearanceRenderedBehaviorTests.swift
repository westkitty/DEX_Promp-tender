import AppKit
import SwiftUI
import Testing
@testable import PromptenderKit

@Suite("Appearance Rendered Behavior")
struct AppearanceRenderedBehaviorTests {
    private func tempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("promptender-appearance-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeVividImage(to url: URL) throws {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 320, pixelsHigh: 240,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            throw NSError(domain: "PreviewTest", code: 1)
        }
        for y in 0..<240 {
            for x in 0..<320 {
                rep.setColor(
                    x < 160
                        ? NSColor(calibratedRed: 0.94, green: 0.10, blue: 0.22, alpha: 1)
                        : NSColor(calibratedRed: 0.08, green: 0.86, blue: 0.36, alpha: 1),
                    atX: x, y: y
                )
            }
        }
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PreviewTest", code: 2)
        }
        try png.write(to: url)
    }

    @MainActor
    private func sampleColor(
        from host: NSHostingView<PromptenderAppearanceLayer>,
        at point: NSPoint
    ) throws -> NSColor {
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "PreviewTest", code: 3)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let rgb = bitmap.colorAt(x: Int(point.x), y: Int(point.y))?
            .usingColorSpace(.deviceRGB) else {
            throw NSError(domain: "PreviewTest", code: 4)
        }
        return rgb
    }

    private func colorDelta(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }

    @MainActor
    @Test("Backdrop opacity and glass tint visibly change the live renderer")
    func backdropAppearanceActuallyChangesPixels() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("vivid.png")
        try writeVividImage(to: imageURL)

        let appearance = AppearanceSettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
        appearance.settings.isWatermarkEnabled = false
        appearance.settings.glassTintOpacity = 0
        appearance.settings.isBackdropImageEnabled = true
        appearance.settings.customBackdropImagePath = imageURL.path
        appearance.settings.backdropBlur = 0
        appearance.settings.backdropOpacity = 0.1

        let host = NSHostingView(rootView: PromptenderAppearanceLayer(appearance: appearance))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
        host.layoutSubtreeIfNeeded()
        let before = try sampleColor(from: host, at: NSPoint(x: 40, y: 70))

        appearance.settings.backdropOpacity = 1.0
        try await Task.sleep(for: .milliseconds(140))
        let after = try sampleColor(from: host, at: NSPoint(x: 40, y: 70))
        #expect(colorDelta(before, after) > 0.12,
                "Backdrop opacity must produce a visible pixel difference")

        appearance.settings.glassTintOpacity = 0.55
        try await Task.sleep(for: .milliseconds(140))
        let tinted = try sampleColor(from: host, at: NSPoint(x: 40, y: 70))
        #expect(colorDelta(after, tinted) > 0.04,
                "Glass tint must produce a visible pixel difference")
    }

    @MainActor
    @Test("Custom watermark opacity visibly updates in the same hosting view")
    func watermarkOpacityActuallyChangesPixels() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("custom-watermark.png")
        try writeVividImage(to: imageURL)

        let appearance = AppearanceSettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
        appearance.settings.glassTintOpacity = 0
        appearance.settings.isBackdropImageEnabled = false
        appearance.settings.customWatermarkPath = imageURL.path
        appearance.settings.watermarkBlendMode = .normal
        appearance.settings.watermarkScale = 1
        appearance.settings.watermarkOpacity = 0
        appearance.settings.isWatermarkEnabled = true

        let host = NSHostingView(rootView: PromptenderAppearanceLayer(appearance: appearance))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
        host.layoutSubtreeIfNeeded()
        let before = try sampleColor(from: host, at: NSPoint(x: 200, y: 115))

        appearance.settings.watermarkOpacity = 1
        try await Task.sleep(for: .milliseconds(140))
        let after = try sampleColor(from: host, at: NSPoint(x: 200, y: 115))
        #expect(colorDelta(before, after) > 0.12,
                "Watermark opacity must produce a visible pixel difference")
    }

    @MainActor
    @Test("Image selection issues are actionable and built-in watermark is valid")
    func missingImageFeedback() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let appearance = AppearanceSettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
        #expect(appearance.imageLoadIssue(for: "", label: "watermark", required: false) == nil)
        #expect(appearance.imageLoadIssue(for: "", label: "background", required: true)?
            .contains("Choose") == true)
        #expect(appearance.imageLoadIssue(
            for: folder.appendingPathComponent("missing.jpg").path,
            label: "background", required: true
        )?.contains("missing or unreadable") == true)
        let real = folder.appendingPathComponent("valid.png")
        try writeVividImage(to: real)
        #expect(appearance.imageLoadIssue(for: real.path, label: "background", required: true) == nil)
    }

    @MainActor
    @Test("Watermark toggle and size alter the same live preview")
    func watermarkSwitchAndScaleRender() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let picture = folder.appendingPathComponent("mark.png")
        try writeVividImage(to: picture)
        let appearance = AppearanceSettingsStore(fileURL: folder.appendingPathComponent("appearance.json"))
        appearance.settings.customWatermarkPath = picture.path
        appearance.settings.watermarkBlendMode = .normal
        appearance.settings.watermarkOpacity = 1
        appearance.settings.glassTintOpacity = 0
        appearance.settings.isBackdropImageEnabled = false
        appearance.settings.isWatermarkEnabled = false

        let host = NSHostingView(rootView: PromptenderAppearanceLayer(appearance: appearance))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
        let hidden = try sampleColor(from: host, at: NSPoint(x: 200, y: 115))
        appearance.settings.isWatermarkEnabled = true
        try await Task.sleep(for: .milliseconds(140))
        let shown = try sampleColor(from: host, at: NSPoint(x: 200, y: 115))
        #expect(colorDelta(hidden, shown) > 0.12)

        appearance.settings.watermarkScale = 0.3
        try await Task.sleep(for: .milliseconds(140))
        let small = try sampleColor(from: host, at: NSPoint(x: 300, y: 115))
        appearance.settings.watermarkScale = 1.8
        try await Task.sleep(for: .milliseconds(140))
        let large = try sampleColor(from: host, at: NSPoint(x: 300, y: 115))
        #expect(colorDelta(small, large) > 0.12,
                "Size slider must visibly change the watermark footprint")
    }

    @MainActor
    @Test("Background scaling and blur visibly change rendered image")
    func backdropScalingAndBlurRender() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let picture = folder.appendingPathComponent("split.png")
        try writeVividImage(to: picture)
        let appearance = AppearanceSettingsStore(fileURL: folder.appendingPathComponent("appearance.json"))
        appearance.settings.isWatermarkEnabled = false
        appearance.settings.glassTintOpacity = 0
        appearance.settings.isBackdropImageEnabled = true
        appearance.settings.customBackdropImagePath = picture.path
        appearance.settings.backdropOpacity = 1
        appearance.settings.backdropBlur = 0
        appearance.settings.backdropContentMode = .fill

        let host = NSHostingView(rootView: PromptenderAppearanceLayer(appearance: appearance))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
        let fillLeft = try sampleColor(from: host, at: NSPoint(x: 12, y: 115))
        appearance.settings.backdropContentMode = .fit
        try await Task.sleep(for: .milliseconds(140))
        let fitLeft = try sampleColor(from: host, at: NSPoint(x: 12, y: 115))
        #expect(colorDelta(fillLeft, fitLeft) > 0.06,
                "Fit and Fill must change what the image occupies")

        appearance.settings.backdropContentMode = .fill
        appearance.settings.backdropBlur = 0
        try await Task.sleep(for: .milliseconds(140))
        let spots = [140, 160, 180, 190, 194, 200, 205, 210, 220, 240, 260]
        let sharpSamples = try spots.map { x in
            try sampleColor(from: host, at: NSPoint(x: x, y: 115))
        }
        appearance.settings.backdropBlur = 28
        try await Task.sleep(for: .milliseconds(200))
        let softenedSamples = try spots.map { x in
            try sampleColor(from: host, at: NSPoint(x: x, y: 115))
        }
        let deltas = zip(sharpSamples, softenedSamples).map { colorDelta($0.0, $0.1) }
        #expect((deltas.max() ?? 0) > 0.04,
                "Blur slider must soften the image's sharp color boundary")
    }


    @MainActor
    @Test("Blur variants are cached without modifying the original image")
    func blurCachePreservesSourceImage() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("original.png")
        try writeVividImage(to: imageURL)
        let before = try Data(contentsOf: imageURL)

        let appearance = AppearanceSettingsStore(
            fileURL: folder.appendingPathComponent("appearance.json")
        )
        let once = try #require(
            appearance.preparedBackdropImage(at: imageURL.path, blurRadius: 18.4)
        )
        let twice = try #require(
            appearance.preparedBackdropImage(at: imageURL.path, blurRadius: 18.4)
        )
        #expect(once === twice)
        #expect(try Data(contentsOf: imageURL) == before)
    }

}
