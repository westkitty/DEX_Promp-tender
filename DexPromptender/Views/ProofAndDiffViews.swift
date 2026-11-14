import SwiftUI

struct ProofReportView: View {
    let report: ProofReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STRAIN & PROOF VALIDATION")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(report.summaryBadge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(report.hasBlockingIssues ? .red : (report.warningCount > 0 ? .orange : .green))
            }

            if let limit = report.characterLimit {
                Text("Length: \(report.characterCount) / \(limit) chars")
                    .font(.caption2.monospaced())
                    .foregroundStyle(report.characterCount > limit ? .red : .secondary)
            } else {
                Text("Length: \(report.characterCount) chars")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            ForEach(report.items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: item.severity))
                        .font(.caption)
                        .foregroundStyle(color(for: item.severity))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(item.category)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(item.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let remediation = item.remediation, !remediation.isEmpty {
                            Text("Fix: \(remediation)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(color(for: item.severity))
                        }
                    }
                }
                .padding(8)
                .glassInset(cornerRadius: 8)
            }
        }
        .padding(10)
        .glassCard()
    }

    private func icon(for severity: ProofSeverity) -> String {
        switch severity {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocking: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: ProofSeverity) -> Color {
        switch severity {
        case .pass: return .green
        case .warning: return .orange
        case .blocking: return .red
        }
    }
}

struct SemanticDiffView: View {
    let diff: SemanticDiffReport
    let provenance: [ProvenanceEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SEMANTIC ATTRIBUTION & TRANSFORM DIFF")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(diff.summaryHeadline)
                    .font(.caption2)
                    .foregroundStyle(.cyan)

                ForEach(diff.ingredientChanges) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.ingredientName)
                                .font(.caption2.weight(.semibold))
                            Spacer()
                            Text(item.attribution.badgeLabel)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        if !item.beforeSummary.isEmpty {
                            Text("Raw: \(item.beforeSummary)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if !item.afterSummary.isEmpty {
                            Text("Compiled: \(item.afterSummary)")
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }
                    }
                    .padding(8)
                    .glassInset(cornerRadius: 8)
                }
            }
            .padding(10)
            .glassCard()

            VStack(alignment: .leading, spacing: 6) {
                Text("PROVENANCE TRAIL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(provenance) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.source.badgeLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.mint)
                            .frame(width: 96, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.section)
                                .font(.caption2.weight(.medium))
                            Text(entry.note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                    .glassInset(cornerRadius: 6)
                }
            }
            .padding(10)
            .glassCard()

            VStack(alignment: .leading, spacing: 4) {
                Text("LINE DIFF")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(diff.lineDiffs.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(lineColor(line.kind))
                }
            }
            .padding(10)
            .glassCard()
        }
    }

    private func lineColor(_ kind: DiffKind) -> Color {
        switch kind {
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .unchanged: return Color.clear
        }
    }
}

struct APIPayloadView: View {
    let result: CompilationResult
    var onCopyPayload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TARGET API PAYLOAD (\(result.modelID))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy JSON") {
                    onCopyPayload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !result.recommendedParameters.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resolved Parameters")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(result.recommendedParameters.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(value)
                                .font(.caption2.monospaced())
                        }
                    }
                }
                .padding(8)
                .glassInset(cornerRadius: 8)
            }

            ScrollView {
                Text(result.structuredPayloadJSON)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(minHeight: 180, maxHeight: 340)
            .glassInset(cornerRadius: 8)
        }
        .padding(10)
        .glassCard()
    }
}
