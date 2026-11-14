import SwiftUI

struct ReadinessBadge: View {
    let state: ReadinessState

    private var tint: Color {
        switch state {
        case .capabilityProven, .currentlyReady:
            return .green
        case .availableToUser, .capabilityAdvertised:
            return .mint
        case .runtimeReachable:
            return .cyan
        case .sourceImplemented:
            return .blue
        case .unknown:
            return .gray
        case .blocked:
            return .orange
        }
    }

    private var iconName: String {
        switch state {
        case .capabilityProven, .currentlyReady:
            return "checkmark.seal.fill"
        case .availableToUser, .capabilityAdvertised:
            return "checkmark.circle.fill"
        case .runtimeReachable:
            return "dot.radiowaves.left.and.right"
        case .sourceImplemented:
            return "doc.text.fill"
        case .unknown:
            return "questionmark.circle"
        case .blocked:
            return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(state.badgeLabel)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.35), lineWidth: 0.75)
                )
        )
    }
}

struct TargetReadinessAndMixControlsView: View {
    @ObservedObject var coordinator: PromptenderCoordinator
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 8) {
                Text("TARGET RECIPE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ReadinessBadge(state: coordinator.readiness(for: coordinator.activeRecipe))
            }

            HStack(spacing: 8) {
                Picker("Destination", selection: $coordinator.selectedDestination) {
                    ForEach(TargetDestination.allCases) { destination in
                        Text(destination.displayName).tag(destination)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                let recipes = coordinator.availableRecipes(for: coordinator.selectedDestination)
                Picker("Recipe", selection: $coordinator.selectedRecipeID) {
                    ForEach(recipes) { recipe in
                        Text(recipe.name).tag(recipe.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !compact {
                Text(coordinator.activeRecipe.promptDialectNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text("Mix Mode")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Mix Mode", selection: $coordinator.mixMode) {
                    ForEach(MixMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Text(coordinator.mixMode.plainDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Intent", selection: Binding(
                    get: { coordinator.hintedIntent },
                    set: { coordinator.hintedIntent = $0 }
                )) {
                    Text("Auto Intent").tag(Optional<IntentKind>.none)
                    ForEach(IntentKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(Optional(kind))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 160)
            }
        }
        .padding(10)
        .glassCard()
    }
}
