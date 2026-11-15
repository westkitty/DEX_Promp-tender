import SwiftUI

struct RootPopoverView: View {
    @ObservedObject var viewModel: PromptEngineViewModel
    @ObservedObject var coordinator: PromptenderCoordinator
    @ObservedObject var appearance: AppearanceSettingsStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            content(
                width: geometry.size.width,
                height: geometry.size.height,
                isDetached: viewModel.isDetachedWindowActive
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.20),
            value: viewModel.isResultPanelVisible
        )
    }

    private var backgroundLayer: some View {
        PromptenderAppearanceLayer(appearance: appearance)
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat, isDetached: Bool) -> some View {
        ZStack {
            backgroundLayer

            MixingRoomView(
                viewModel: viewModel, coordinator: coordinator, appearance: appearance,
                isDetached: isDetached, availableWidth: width
            )
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
    }
}
