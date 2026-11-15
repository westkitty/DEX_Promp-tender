import AppKit
import SwiftUI

/// The Bar and the Settings preview share this exact image composition.
struct PromptenderAppearanceLayer: View {
    @ObservedObject var appearance: AppearanceSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let cfg = appearance.settings
            let image = cfg.isBackdropImageEnabled
                ? appearance.preparedBackdropImage(
                    at: cfg.customBackdropImagePath, blurRadius: cfg.backdropBlur
                )
                : nil

            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: cfg.backdropContentMode == .fill ? .fill : .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(cfg.backdropOpacity)

                    // Keep foreground text legible across bright custom images
                    // without erasing the photo beneath the glass.
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.black.opacity(0.55), .black.opacity(0.28)]
                            : [.white.opacity(0.58), .white.opacity(0.34)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Rectangle().fill(.ultraThinMaterial).opacity(0.18)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }

                LinearGradient(
                    colors: [
                        Color.white.opacity(cfg.glassTintOpacity),
                        Color.cyan.opacity(max(0.02, cfg.glassTintOpacity * 0.65)),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Color.white.opacity(cfg.glassTintOpacity), Color.clear],
                    center: .center, startRadius: 20, endRadius: 360
                )

                if cfg.isWatermarkEnabled {
                    watermarkImage
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(
                            width: min(420, geometry.size.width * 0.90, geometry.size.height * 0.90)
                                * cfg.watermarkScale,
                            height: min(420, geometry.size.width * 0.90, geometry.size.height * 0.90)
                                * cfg.watermarkScale
                        )
                        .opacity(cfg.watermarkOpacity)
                        .blendMode(cfg.watermarkBlendMode.swiftUIBlendMode)
                        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var watermarkImage: Image {
        if let custom = appearance.cachedImage(at: appearance.settings.customWatermarkPath) {
            return Image(nsImage: custom)
        }
        if let image = NSImage(named: "DexCraftWatermark") {
            return Image(nsImage: image)
        }
        if let url = AppBundleResources.url(forResource: "DexCraftWatermark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        return Image("DexCraftWatermark")
    }
}
