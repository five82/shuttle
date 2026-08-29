import AppKit
import SwiftUI

/// Trailing inspector for the selected item. Overview is a fixed section
/// skeleton — Attention, Pipeline, Media, Output, Episodes, Meta — where
/// rows appear by data presence, never by state branching, so positions
/// stay learnable.
struct ItemInspectorView: View {
    @Environment(SpindleMonitor.self) private var monitor

    enum Tab: String, CaseIterable, Identifiable {
        case overview, episodes
        var id: String { rawValue }
    }

    @State private var tab: Tab = .overview

    private var item: QueueItem? {
        guard let id = monitor.selectedItemID else { return nil }
        if let detail = monitor.selectedItemDetail, detail.id == id { return detail }
        return monitor.items.first { $0.id == id }
    }

    var body: some View {
        if let item {
            VStack(spacing: 0) {
                header(item)
                Divider()
                if item.isEpisodic {
                    Picker("", selection: $tab) {
                        Text("Overview").tag(Tab.overview)
                        Text("Episodes · \(item.episodeList.count)").tag(Tab.episodes)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(10)
                }
                switch tab {
                case .overview:
                    OverviewView(item: item, pipeline: monitor.status?.pipelineStages ?? [])
                case .episodes:
                    EpisodesView(item: item)
                }
            }
            .onChange(of: item.isEpisodic) { _, episodic in
                if !episodic { tab = .overview }
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.trailing", description: Text("Select an item in the queue."))
        }
    }

    private func header(_ item: QueueItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(item.id)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(item.displayTitle)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                StatusChip(label: stageLabel(item), systemImage: stageSymbol(item), tint: stageTint(item))
                if let type = item.mediaType {
                    StatusChip(label: type.uppercased(), systemImage: type == "tv" ? "tv" : "film", tint: .secondary)
                }
                if let disc = item.discNumber, disc > 0 {
                    StatusChip(label: "Disc \(disc)", systemImage: "opticaldisc", tint: .secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stageLabel(_ item: QueueItem) -> String {
        if item.hasFailed { return "Failed" }
        if item.needsReview { return "Review" }
        if item.isActive { return item.activityDescription.components(separatedBy: " · ").first ?? item.stage.displayName }
        return item.stage.displayName
    }

    private func stageSymbol(_ item: QueueItem) -> String {
        if item.hasFailed { return "xmark.circle.fill" }
        if item.needsReview { return "exclamationmark.triangle.fill" }
        if item.isActive { return "circle.fill" }
        if item.isCompleted { return "checkmark.circle.fill" }
        return "circle"
    }

    private func stageTint(_ item: QueueItem) -> Color {
        if item.hasFailed { return .red }
        if item.needsReview { return .orange }
        if item.isActive { return .accentColor }
        if item.isCompleted { return .green }
        return .secondary
    }
}

// MARK: - Overview

private struct OverviewView: View {
    let item: QueueItem
    let pipeline: [PipelineStageInfo]

    var body: some View {
        let encoding = item.encodingDetails
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                attention(encoding)
                InspectorSection("Pipeline") {
                    PipelineStripView(cells: PipelineCell.cells(for: item, pipeline: pipeline))
                }
                media(encoding)
                output(encoding)
                episodes
                meta
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func attention(_ encoding: EncodingDetails?) -> some View {
        let warning = encoding?.warning?.trimmingCharacters(in: .whitespaces) ?? ""
        let validation = encoding?.validation
        let failingSteps = (validation?.passed == false) ? validation?.stepList ?? [] : []
        if item.needsAttention || !warning.isEmpty || !failingSteps.isEmpty {
            InspectorSection("Attention", tint: item.hasFailed ? .red : .orange) {
                if item.needsReview {
                    InspectorRow("Review", item.reviewReasons?.joined(separator: "; ") ?? "Needs operator review", tint: .orange)
                }
                if let task = item.failedTask {
                    InspectorRow("Failed", "\(task.type.displayName)\(task.attempts.map { $0 > 1 ? " · \($0) attempts" : "" } ?? "")", tint: .red)
                    if let error = task.error, !error.isEmpty {
                        InspectorRow("Error", error)
                    }
                } else if let message = item.errorMessage, !message.isEmpty {
                    InspectorRow("Error", message, tint: .red)
                }
                if let issue = encoding?.error {
                    if let title = issue.title, !title.isEmpty, title != item.errorMessage {
                        InspectorRow("Cause", title)
                    }
                    if let context = issue.context, !context.isEmpty { InspectorRow("Context", context) }
                    if let suggestion = issue.suggestion, !suggestion.isEmpty { InspectorRow("Suggest", suggestion, tint: .green) }
                }
                if !warning.isEmpty {
                    InspectorRow("Warning", warning, tint: .orange)
                }
                if let at = item.failedAtStage, item.taskList.isEmpty {
                    InspectorRow("Failed at", at.displayName, tint: .red)
                }
                if item.hasFailed, let files = item.fileStateSummary {
                    InspectorRow("Files", files)
                }
                ForEach(failingSteps) { step in
                    ValidationStepRow(step: step)
                }
            }
        }
    }

    @ViewBuilder
    private func media(_ encoding: EncodingDetails?) -> some View {
        let rows: [(String, String, Color?)] = [
            ("Source", item.source?.summary ?? "", nil),
            ("Video", encoding?.videoSummary ?? "", nil),
            ("Audio", item.primaryAudioDescription?.replacingOccurrences(of: " | ", with: " · ") ?? "", nil),
            ("Tracks", (item.commentaryCount ?? 0) > 0 ? "\(item.commentaryCount!) commentary track\(item.commentaryCount! == 1 ? "" : "s")" : "", nil),
            ("Config", encoding?.configSummary ?? "", nil),
            ("Quality", encoding?.qualitySummary ?? "", nil),
            ("ID", contentIDSummary, nil),
            ("TMDB", item.tmdbID.map(String.init) ?? "", nil),
        ].filter { !$0.1.isEmpty }
        if !rows.isEmpty {
            InspectorSection("Media") {
                ForEach(rows, id: \.0) { row in
                    InspectorRow(row.0, row.1, tint: row.2)
                }
                if let cid = item.contentId, cid.completed == true {
                    if cid.sequenceContiguous == false {
                        InspectorRow("", "Episode sequence not contiguous", tint: .orange)
                    }
                    if cid.episodesSynchronized == false {
                        InspectorRow("", "Episodes not synchronized", tint: .orange)
                    }
                }
            }
        }
    }

    private var contentIDSummary: String {
        guard let cid = item.contentId, let method = cid.method, !method.isEmpty else { return "" }
        var value = method
        if (cid.transcribedEpisodes ?? 0) > 0 || (cid.matchedEpisodes ?? 0) > 0 {
            value += " · \(cid.matchedEpisodes ?? 0) matched · \(cid.unresolvedEpisodes ?? 0) unresolved · \(cid.lowConfidenceCount ?? 0) low confidence"
        }
        if let source = cid.referenceSource, !source.isEmpty {
            value += " · ref \(source)"
            if let count = cid.referenceEpisodes, count > 0 { value += " (\(count) episodes)" }
        }
        return value
    }

    @ViewBuilder
    private func output(_ encoding: EncodingDetails?) -> some View {
        let validation = encoding?.validation
        let checks: String = {
            guard let validation, !validation.stepList.isEmpty else { return "" }
            let counts = "\(validation.passedCount)/\(validation.stepList.count)"
            return validation.passed == false ? "Failed · \(counts)" : "Passed · \(counts)"
        }()
        let subs: String = {
            let sources = item.episodeList.compactMap { $0.subtitleSource?.lowercased() }.filter { !$0.isEmpty }
            guard !sources.isEmpty else { return "" }
            let counts = Dictionary(grouping: sources, by: { $0 }).mapValues(\.count)
            return counts.sorted { $0.key < $1.key }.map { item.episodeList.count == 1 ? $0.key : "\($0.value) \($0.key)" }.joined(separator: " · ")
        }()
        let rows: [(String, String, Color?)] = [
            ("Est", encoding?.sizeEstimate ?? "", Color.accentColor),
            ("Size", encoding?.sizeResult ?? "", nil),
            ("Encode", encoding?.encodeStats ?? "", nil),
            ("Checks", checks, validation?.passed == false ? Color.red : Color.green),
            ("Subs", subs, nil),
            ("Files", item.hasFailed ? "" : (item.fileStateSummary ?? ""), nil),
        ].filter { !$0.1.isEmpty }
        if !rows.isEmpty || item.finalPath != nil {
            InspectorSection("Output") {
                ForEach(rows, id: \.0) { row in
                    InspectorRow(row.0, row.1, tint: row.2)
                }
                if validation?.passed == true {
                    ForEach(validation?.stepList ?? []) { step in
                        ValidationStepRow(step: step)
                    }
                }
                if let path = item.finalPath {
                    OutputPathRow(path: path)
                }
            }
        }
    }

    @ViewBuilder
    private var episodes: some View {
        if item.isEpisodic, let totals = item.episodeTotals {
            InspectorSection("Episodes") {
                InspectorRow("Progress", "\(totals.planned) planned · \(totals.ripped) ripped · \(totals.encoded) encoded · \(totals.final) final")
                let matched = item.episodeList.filter { ($0.matchedEpisode ?? 0) > 0 }.count
                if matched > 0, matched < item.episodeList.count {
                    InspectorRow("", "Episode numbers not confirmed", tint: .orange)
                }
                if let identified = item.episodeIdentifiedCount, identified > 0 {
                    InspectorRow("Identified", "\(identified) of \(item.episodeList.count)")
                }
            }
        }
    }

    private var meta: some View {
        InspectorSection("Meta") {
            InspectorRow("Created", item.createdDate.formatted(date: .abbreviated, time: .shortened))
            InspectorRow("Updated", item.updatedDate.formatted(date: .abbreviated, time: .shortened))
            if item.discTitle != item.displayTitle, !item.discTitle.isEmpty {
                InspectorRow("Disc title", item.discTitle)
            }
            if let fingerprint = item.discFingerprint, !fingerprint.isEmpty {
                InspectorRow("Fingerprint", String(fingerprint.prefix(12)) + "…", monospaced: true)
                    .help(fingerprint)
            }
            if item.userStopped == true {
                InspectorRow("Stopped", "by operator", tint: .orange)
            }
        }
    }
}

// MARK: - Building blocks

struct InspectorSection<Content: View>: View {
    let title: String
    var tint: Color = .secondary
    @ViewBuilder let content: Content

    init(_ title: String, tint: Color = .secondary, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .kerning(0.6)
            content
        }
    }
}

struct InspectorRow: View {
    let label: String
    let value: String
    var tint: Color? = nil
    var monospaced = false

    init(_ label: String, _ value: String, tint: Color? = nil, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.tint = tint
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ValidationStepRow: View {
    let step: EncodingValidationStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: step.passed == true ? "checkmark" : "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(step.passed == true ? .green : .red)
                .frame(width: 72, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.name ?? "Check").font(.callout)
                if let details = step.details, !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The final path with Reveal in Finder when the library is reachable from
/// this Mac, or Copy Path when it is not.
private struct OutputPathRow: View {
    let path: String

    private var localURL: URL? {
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Path")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if let localURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([localURL])
                        }
                    }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
