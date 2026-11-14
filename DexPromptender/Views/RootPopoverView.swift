import SwiftUI

struct RootPopoverView: View {
    @ObservedObject var viewModel: PromptEngineViewModel
    @ObservedObject var coordinator: PromptenderCoordinator
    @ObservedObject var appearance: AppearanceSettingsStore

    private let collapsedWidth: CGFloat = 480
    private let expandedWidth: CGFloat = 960
    private let height: CGFloat = 660

    var body: some View {
        Group {
            if viewModel.isDetachedWindowActive {
                GeometryReader { geometry in
                    content(width: geometry.size.width, height: geometry.size.height, isDetached: true)
                }
                .frame(minWidth: 880, minHeight: 580)
            } else {
                let width = viewModel.isResultPanelVisible ? expandedWidth : collapsedWidth
                content(width: width, height: height, isDetached: false)
                    .frame(width: width, height: height)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.isResultPanelVisible)
    }

    private var backgroundLayer: some View {
        let cfg = appearance.settings
        return ZStack {
            if cfg.isBackdropImageEnabled,
               let behindImg = loadCustomNSImage(path: cfg.customBackdropImagePath) {
                Group {
                    if cfg.backdropContentMode == .fill {
                        Image(nsImage: behindImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(nsImage: behindImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .opacity(cfg.backdropOpacity)
                .blur(radius: cfg.backdropBlur)
                .ignoresSafeArea()
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(cfg.glassTintOpacity),
                    Color.cyan.opacity(max(0.02, cfg.glassTintOpacity * 0.65)),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.white.opacity(cfg.glassTintOpacity),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()

            if cfg.isWatermarkEnabled {
                watermarkImage
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 420 * cfg.watermarkScale, height: 420 * cfg.watermarkScale)
                    .opacity(cfg.watermarkOpacity)
                    .blendMode(cfg.watermarkBlendMode.swiftUIBlendMode)
                    .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
    }

    private var watermarkImage: Image {
        let customPath = appearance.settings.customWatermarkPath
        if let customNS = loadCustomNSImage(path: customPath) {
            return Image(nsImage: customNS)
        }
        if let nsImage = NSImage(named: "DexCraftWatermark") {
            return Image(nsImage: nsImage)
        }
        if let url = AppBundleResources.url(forResource: "DexCraftWatermark", withExtension: "png"),
           let fileImage = NSImage(contentsOf: url) {
            return Image(nsImage: fileImage)
        }
        return Image("DexCraftWatermark")
    }

    private func loadCustomNSImage(path: String) -> NSImage? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) else { return nil }
        return NSImage(contentsOfFile: trimmed)
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat, isDetached: Bool) -> some View {
        ZStack {
            backgroundLayer

            MixingRoomView(viewModel: viewModel, coordinator: coordinator, appearance: appearance, isDetached: isDetached)
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
    }
}
