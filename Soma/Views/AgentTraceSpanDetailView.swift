import SwiftUI

struct AgentTraceTimelineEntry: Identifiable {
    let span: AgentTraceSpan
    let ordinal: Int
    let traceStartedAt: Date

    var id: UUID {
        span.id
    }

    var relativeMilliseconds: Double {
        max(0, span.endedAt.timeIntervalSince(traceStartedAt) * 1000)
    }
}

struct AgentTraceSpanPayloadSection: Equatable, Identifiable {
    let title: String
    let value: String
    var isError: Bool = false

    var id: String {
        title
    }
}

enum AgentTraceSpanPayloads {
    static func sections(
        for span: AgentTraceSpan,
        metadata: TraceSpanMetadata
    ) -> [AgentTraceSpanPayloadSection] {
        var result: [AgentTraceSpanPayloadSection] = []
        if span.kind == .model, let tools = metadata.exposedToolSummary, !tools.isEmpty {
            result.append(AgentTraceSpanPayloadSection(title: "绑定工具", value: tools))
        }
        if let input = span.input, !input.isEmpty {
            result.append(AgentTraceSpanPayloadSection(title: "入参", value: input))
        }
        if let output = span.output, !output.isEmpty {
            result.append(AgentTraceSpanPayloadSection(title: "返回", value: output))
        }
        if let metadataText = span.metadata, !metadataText.isEmpty {
            result.append(AgentTraceSpanPayloadSection(title: "元数据", value: metadataText))
        }
        if span.kind != .output, let error = span.errorMessage, !error.isEmpty {
            result.append(
                AgentTraceSpanPayloadSection(title: "错误", value: error, isError: true)
            )
        }
        return result
    }
}

struct AgentTraceSpanRow: View {
    let entry: AgentTraceTimelineEntry
    let provider: String
    let model: String

    private var span: AgentTraceSpan {
        entry.span
    }

    private var metadata: TraceSpanMetadata {
        TraceSpanMetadata(span.metadata)
    }

    var body: some View {
        NavigationLink {
            AgentTraceSpanDetailView(
                entry: entry,
                provider: provider,
                model: model
            )
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(spanColor.opacity(0.12))
                    Image(systemName: TraceStyle.icon(for: span.kind))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(spanColor)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(TraceStyle.displayTitle(for: span, ordinal: entry.ordinal))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(span.status == .failed ? .red : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(TraceStyle.relative(entry.relativeMilliseconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(primarySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                    if let secondarySummary {
                        Text(secondarySummary)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                    }
                    if let error = span.errorMessage, !error.isEmpty,
                       [.failed, .cancelled].contains(span.status)
                    {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(
            "\(TraceStyle.displayTitle(for: span, ordinal: entry.ordinal))，\(primarySummary)"
        )
        .accessibilityHint("查看完整入参、返回与元数据")
    }

    private var spanColor: Color {
        if [.failed, .cancelled].contains(span.status) {
            return .red
        }
        return TraceStyle.color(for: span.kind)
    }

    private var primarySummary: String {
        switch span.kind {
        case .model:
            return "\(provider)/\(model)"
        case .skill:
            if let skillID = metadata.string("skill_id") {
                return skillID
            }
            return span.status.title
        case .tool:
            return span.status == .succeeded ? "调用成功" : span.status.title
        case .output:
            return span.status.title
        }
    }

    private var secondarySummary: String? {
        var parts = [TraceStyle.duration(span.durationMilliseconds)]
        switch span.kind {
        case .model:
            if let tokenSummary = metadata.tokenSummary {
                parts.append(tokenSummary)
            }
            if let latencySummary = metadata.latencySummary {
                parts.append(latencySummary)
            }
        case .skill:
            parts.insert(span.status.title, at: 0)
        case .tool, .output:
            return parts.first
        }
        return parts.joined(separator: " · ")
    }
}

struct AgentTraceSpanDetailView: View {
    let entry: AgentTraceTimelineEntry
    let provider: String
    let model: String

    private var span: AgentTraceSpan {
        entry.span
    }

    private var sections: [AgentTraceSpanPayloadSection] {
        AgentTraceSpanPayloads.sections(
            for: span,
            metadata: TraceSpanMetadata(span.metadata)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TraceStyle.displayTitle(for: span, ordinal: entry.ordinal))
                        .font(.title3.weight(.semibold))
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if sections.isEmpty {
                    Text("这次调用没有保存入参或返回。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(section.value)
                                .font(.caption.monospaced())
                                .foregroundStyle(section.isError ? .red : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                }
            }
            .padding(16)
        }
        .appPageBackground()
        .navigationTitle("调用详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusLine: String {
        [
            span.status.title,
            TraceStyle.duration(span.durationMilliseconds),
            span.kind == .model ? "\(provider)/\(model)" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
