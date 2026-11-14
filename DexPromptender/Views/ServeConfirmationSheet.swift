import SwiftUI

struct ServeConfirmationSheet: View {
    @ObservedObject var coordinator: PromptenderCoordinator
    let confirmation: PendingServeConfirmation

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
                        await coordinator.confirmAndExecutePendingServe()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isSubmittingServe || confirmation.result.proofReport.hasBlockingIssues)
            }
        }
        .padding(16)
        .frame(width: 540)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 85, alignment: .leading)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer()
        }
    }
}
