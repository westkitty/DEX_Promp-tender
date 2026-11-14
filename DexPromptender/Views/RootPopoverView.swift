import SwiftUI

struct RootPopoverView: View {
    @ObservedObject var viewModel: PromptEngineViewModel
    @ObservedObject var coordinator: PromptenderCoordinator

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
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.cyan.opacity(0.10),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()

            Image("DexCraftWatermark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 420, height: 420)
                .opacity(0.72)
                .blendMode(.screen)
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat, isDetached: Bool) -> some View {
        ZStack {
            backgroundLayer

            MixingRoomView(viewModel: viewModel, coordinator: coordinator, isDetached: isDetached)
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
    }
}
