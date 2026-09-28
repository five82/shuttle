import AppKit
import SwiftUI

/// Trailing inspector for the selected item. Overview is a fixed section
/// skeleton — Attention, Pipeline, Media, Output, Episodes, Meta — where
/// rows appear by data presence, never by state branching, so positions
/// stay learnable.
struct ItemInspectorView: View {
    @Environment(SpindleMonitor.self) private var monitor

    enum Tab: String, CaseIterable, Identifiable {
        case overview, episodes, log, events
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
                Picker("", selection: $tab) {
                    Text("Overview").tag(Tab.overview)
                    if item.isEpisodic {
                        Text("Episodes · \(item.episodeList.count)").tag(Tab.episodes)
                    }
                    Text("Log").tag(Tab.log)
                    Text("Events").tag(Tab.events)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                switch tab {
                case .overview:
                    OverviewView(item: item, pipeline: monitor.status?.pipelineStages ?? [], progress: monitor.taskProgress[item.id] ?? [])
                case .episodes:
                    EpisodesView(item: item)
                case .log:
                    LogView(itemID: item.id, compact: true)
                case .events:
                    ItemEventsView(itemID: item.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: item.isEpisodic) { _, episodic in
                if !episodic, tab == .episodes { tab = .overview }
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.trailing", description: Text("Select an item in the queue."))
        }
    }

    private func header(_ item: QueueItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("#\(item.id)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                CopyButton(text: "\(item.id)", help: "Copy ID")
                Spacer()
                Text("Updated \(item.updatedDate, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(item.displayTitle)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                StatusChip(label: Self.stageLabel(item, reason: monitor.waitReasons[item.id]), systemImage: stageSymbol(item), tint: stageTint(item))
                    .help(Self.stageHelp(item, reason: monitor.waitReasons[item.id]))
                if let type = item.mediaTypeLabel {
                    StatusChip(label: type, systemImage: item.mediaType == "tv" ? "tv" : "film", tint: .secondary)
                }
                if let disc = item.discNumber, disc > 0 {
                    StatusChip(label: "Disc \(disc)", systemImage: "opticaldisc", tint: .secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func stageLabel(_ item: QueueItem, reason: WaitReason?) -> String {
        if item.hasFailed { return "Failed" }
        if item.needsReview { return "Review" }
        if item.isActive { return item.activityDescription.components(separatedBy: " · ").first ?? item.stage.displayName }
        if item.isWaiting {
            if item.explicitWait != nil { return "Waiting · \(item.taskList.first { $0.waitingMessage != nil }?.type.displayName ?? item.stage.displayName)" }
            if let reason { return "Queued · \(reason.short)" }
            return "Queued · \(item.stage.displayName)"
        }
        return item.stage.displayName
    }

    static func stageHelp(_ item: QueueItem, reason: WaitReason?) -> String {
        if item.isWaiting { return item.explicitWait ?? reason?.detail ?? item.stage.displayName }
        if item.isActive { return item.activityDescription }
        return item.attentionReason ?? item.stage.displayName
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
    let progress: [ItemProgress]

    var body: some View {
        let encoding = item.encodingDetails
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                attention(encoding)
                InspectorSection("Pipeline") {
                    PipelineListView(cells: PipelineCell.cells(for: item, pipeline: pipeline), progress: progress)
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
        let finalFailures = item.episodeList.filter { episode in
            let validation = episode.finalValidation
            return validation?["passed"]?.boolValue == false ||
                (validation?["error"]?.stringValue?.isEmpty == false)
        }
        if item.needsAttention || !warning.isEmpty || !failingSteps.isEmpty || !finalFailures.isEmpty {
            InspectorSection("Attention", tint: item.hasFailed ? .red : .orange) {
                if item.needsReview {
                    let reasons = item.reviewReasons?.filter { !$0.isEmpty } ?? []
                    if reasons.isEmpty {
                        InspectorRow("Review", "Needs operator review", tint: .orange)
                    } else {
                        ForEach(Array(reasons.enumerated()), id: \.offset) { index, reason in
                            ReasonRow(label: index == 0 ? "Review" : "", reason: reason, tint: .orange)
                        }
                    }
                }
                if let task = item.failedTask {
                    InspectorRow("Failed", "\(task.type.displayName)\(task.attempts.map { $0 > 1 ? " · \($0) attempts" : "" } ?? "")", tint: .red)
                    if let error = task.error, !error.isEmpty {
                        ReasonRow(label: "Error", reason: error, tint: nil)
                    }
                } else if let message = item.errorMessage, !message.isEmpty {
                    ReasonRow(label: "Error", reason: message, tint: .red)
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
                ForEach(finalFailures) { episode in
                    InspectorRow("Final check", "\(episode.key): \(episode.finalValidation?["error"]?.stringValue ?? "failed post-Apply validation")", tint: .red)
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
            ("Identify", item.contentId?.inspectorSummary ?? "", nil),
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

    @ViewBuilder
    private func output(_ encoding: EncodingDetails?) -> some View {
        let validation = encoding?.validation
        let checks: String = {
            guard let validation, !validation.stepList.isEmpty else { return "" }
            let counts = "\(validation.passedCount)/\(validation.stepList.count)"
            return validation.passed == false ? "Failed · \(counts)" : "Passed · \(counts)"
        }()
        let subs = item.inspectorSubtitleSummary
        let rows: [(String, String, Color?)] = [
            ("Progress", progress.max { $0.fraction < $1.fraction }?.detailText ?? "", Color.accentColor),
            ("Encode est.", encoding?.sizeEstimate ?? "", Color.accentColor),
            ("Encode size", encoding?.sizeResult ?? "", nil),
            ("Encode", encoding?.encodeStats ?? "", nil),
            ("Encode checks", checks, validation?.passed == false ? Color.red : Color.green),
            ("Delivered", item.deliveredSummary, item.episodeList.contains { $0.finalValidation?["passed"]?.boolValue == false } ? Color.red : nil),
            ("Subtitles", subs, nil),
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    InspectorRow("Fingerprint", String(fingerprint.prefix(12)) + "…", monospaced: true)
                        .help(fingerprint)
                    CopyButton(text: fingerprint, help: "Copy fingerprint")
                }
            }
            if item.userStopped == true {
                InspectorRow("Stopped", "by operator", tint: .orange)
            }
        }
    }
}

// MARK: - Inspector summaries

extension ContentIdentification {
    /// Method, match counts, and reference provenance shown under Media.
    var inspectorSummary: String {
        guard let method, !method.isEmpty else { return "" }
        var value = method
        if (transcribedEpisodes ?? 0) > 0 || (matchedEpisodes ?? 0) > 0 {
            value += " · \(matchedEpisodes ?? 0) matched · \(unresolvedEpisodes ?? 0) unresolved · \(lowConfidenceCount ?? 0) low confidence"
        }
        if let referenceSource, !referenceSource.isEmpty {
            value += " · ref \(referenceSource)"
            if let referenceEpisodes, referenceEpisodes > 0 { value += " (\(referenceEpisodes) episodes)" }
        }
        return value
    }
}

extension QueueItem {
    /// Final post-Apply facts are per file, not the encoder's intermediate
    /// validation of a file that may later have been rewritten.
    var deliveredSummary: String {
        let files = episodeList.filter { !($0.finalPath ?? "").isEmpty }
        guard !files.isEmpty else { return "" }
        let bytes = files.compactMap(\.finalSizeBytes).filter { $0 > 0 }.reduce(Int64(0), +)
        let checks = files.compactMap(\.finalValidation)
        let passed = checks.filter { $0["passed"]?.boolValue == true && $0["av_sync"]?["passed"]?.boolValue == true }.count
        var parts = ["\(files.count) delivered"]
        if bytes > 0 { parts.append(EncodingDetails.bytes(bytes)) }
        if !checks.isEmpty { parts.append("final post-Apply: \(passed)/\(checks.count) passed") }
        return parts.joined(separator: " · ")
    }

    /// Stable, case-insensitive source counts for the Output section.
    var inspectorSubtitleSummary: String {
        let sources = episodeList.compactMap { $0.subtitleSource?.lowercased() }.filter { !$0.isEmpty }
        guard !sources.isEmpty else { return "" }
        let counts = Dictionary(grouping: sources, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.key < $1.key }.map { episodeList.count == 1 ? $0.key : "\($0.value) \($0.key)" }.joined(separator: " · ")
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

/// Width of the trailing-aligned label column shared by every row style,
/// wide enough for "Disc monitor", "Fingerprint", and "Validation".
let inspectorLabelWidth: CGFloat = 90

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
                .lineLimit(1)
                .frame(width: inspectorLabelWidth, alignment: .trailing)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A daemon reason string such as "final_validation: main: audio stream 0
/// duration …" with its machine-y prefix set off from the message, so the
/// eye lands on the part that says what happened.
struct ReasonRow: View {
    let label: String
    let reason: String
    let tint: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: inspectorLabelWidth, alignment: .trailing)
            text
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var text: Text {
        let (prefix, message) = Self.split(reason)
        var body = Text(message).foregroundStyle(tint ?? .primary)
        if let prefix {
            let heading = Text(prefix).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(.secondary)
            body = Text("\(heading)\n\(body)")
        }
        return body
    }

    /// Splits leading "token: token: " segments — no spaces inside — from
    /// the human message. Returns nil prefix when there is nothing to split.
    static func split(_ reason: String) -> (String?, String) {
        var rest = Substring(reason)
        var parts: [String] = []
        while let range = rest.range(of: ": ") {
            let token = rest[..<range.lowerBound]
            guard !token.isEmpty, !token.contains(" "), token.count <= 32 else { break }
            parts.append(String(token))
            rest = rest[range.upperBound...]
        }
        guard !parts.isEmpty, !rest.isEmpty else { return (nil, reason) }
        return (parts.joined(separator: " · "), String(rest))
    }
}

/// Copies `text` and shows a checkmark for a moment so the click is seen
/// to have done something.
struct CopyButton: View {
    let text: String
    let help: String

    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeIn(duration: 0.2)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(copied ? .bold : .regular))
                .foregroundStyle(copied ? AnyShapeStyle(.green) : (hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .pointingHandCursor(hovering)
        .onHover { hovering = $0 }
        .help(copied ? "Copied" : help)
        .accessibilityLabel(copied ? "Copied" : help)
    }
}

/// A small bordered button that confirms the copy in its own label.
struct CopyTextButton: View {
    let title: String
    let text: String

    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
        .frame(minWidth: 70)
    }
}

private struct ValidationStepRow: View {
    let step: EncodingValidationStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: step.passed == true ? "checkmark" : "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(step.passed == true ? .green : .red)
                .frame(width: inspectorLabelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.name ?? "Check").font(.callout)
                if let details = step.details, !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The final path with Reveal in Finder when the library mapping in
/// Settings resolves it to something on this Mac, else Copy Path; the reason
/// Reveal is absent lives in the tooltip rather than under every item.
private struct OutputPathRow: View {
    @Environment(AppSettingsStore.self) private var settingsStore
    let path: String

    private var localURL: URL? {
        settingsStore.settings.localLibraryURL(for: path)
    }

    private var revealHint: String {
        settingsStore.settings.libraryLocalPrefix.isEmpty
            ? "Set the library mount in Settings to reveal files in Finder."
            : "Not found under \(settingsStore.settings.libraryLocalPrefix) on this Mac."
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Path")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: inspectorLabelWidth, alignment: .trailing)
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
                    CopyTextButton(title: "Copy Path", text: path)
                    if localURL == nil {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.tertiary)
                            .help(revealHint)
                            .accessibilityLabel(revealHint)
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
