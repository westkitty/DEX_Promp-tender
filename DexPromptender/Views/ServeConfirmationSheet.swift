import SwiftUI

struct ServeConfirmationSheet: View {
    @ObservedObject var coordinator: PromptenderCoordinator
    let confirmation: PendingServeConfirmation
    @ObservedObject var viewModel: PromptEngineViewModel

    private var isCurrent: Bool {
        coordinator.isLastResultCurrent(
            rawInput: viewModel.roughInput,
            variables: viewModel.variableValues,
            legacyOptions: viewModel.options
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONFIRM EXTERNAL SERVE")
                        .font(.headline)
                    Text(confirmation.destinationTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !isCurrent {
                Label("Draft changed since confirmation was opened. Mix again before submission.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout.weight(.semibold))
            }

            Text(confirmation.billingNotice)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                detailRow("Endpoint", value: confirmation.endpointURL)
                detailRow("Model ID", value: confirmation.modelID)
                detailRow("Proof Status", value: confirmation.result.proofReport.summaryBadge)
            }
            .padding(8)
            .glassInset(cornerRadius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Redacted Request Headers")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(confirmation.redactedHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    Text("\(key): \(value)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .glassInset(cornerRadius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Inspectable Request Payload JSON")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(confirmation.payloadPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(minHeight: 140, maxHeight: 220)
                .glassInset(cornerRadius: 6)
            }

            HStack {
                Button("Cancel") {
                    coordinator.pendingServeConfirmation = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(coordinator.isSubmittingServe ? "Submitting..." : "Confirm & Submit Request") {
                    Task {
                        await coordinator.confirmAndExecutePendingServe(
                            rawInput: viewModel.roughInput,
                            variables: viewModel.variableValues,
                            legacyOptions: viewModel.options
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isCurrent || coordinator.isSubmittingServe || confirmation.result.proofReport.hasBlockingIssues)
            }
        }
        .padding(16)
        .frame(minWidth: 340, idealWidth: 540, maxWidth: 540)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
