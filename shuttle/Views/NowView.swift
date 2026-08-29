import SwiftUI

/// The landing view: what needs me, what is running, what the daemon is
/// holding, what just finished. Rows are buttons that select the item in
/// the inspector beside this view. Attention and completed are capped so
/// Running stays above the fold; the full lists live one click away.
struct NowView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    var filter = ""

    private static let attentionCap = 3

    private var needle: String { filter.trimmingCharacters(in: .whitespaces).lowercased() }

    private func matching(_ items: [QueueItem]) -> [QueueItem] {
        needle.isEmpty ? items : items.filter { $0.searchableText.contains(needle) }
    }

    var body: some View {
        let attention = matching(monitor.attentionItems)
        let active = matching(monitor.activeItems)
        let waiting = matching(monitor.waitingItems)
        let completed = matching(monitor.recentlyCompleted)
        let nothingMatches = !needle.isEmpty && attention.isEmpty && active.isEmpty && waiting.isEmpty && completed.isEmpty

        if nothingMatches {
            ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("Nothing on Now contains “\(filter)”. The Queue lists every item."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let issue = monitor.daemonIssue {
                        NoticeBanner(title: "Daemon needs attention", detail: issue, tint: .red, help: "Show daemon health") {
                            model.section = .dependencies
                        }
                    } else if monitor.status?.isDraining == true {
                        NoticeBanner(title: "Daemon draining", detail: "Running work finishes; nothing new is dispatched.", tint: .orange, help: "Show daemon health") {
                            model.section = .dependencies
                        }
                    }

                    if !attention.isEmpty {
                        NowSection("Needs attention") {
                            ForEach(attention.prefix(Self.attentionCap)) { item in
                                NowRow(item: item) { AttentionRow(item: item) }
                            }
                            if attention.count > Self.attentionCap {
                                MoreLink("Show all \(attention.count) in Attention") { model.section = .attention }
                            }
                        }
                    }

                    NowSection("Running", accessory: { ResourcesRow(resources: monitor.resources) }) {
                        if active.isEmpty {
                            idleRow
                        } else {
                            ForEach(active) { item in
                                NowRow(item: item) { ActiveRow(item: item, progress: monitor.taskProgress[item.id] ?? []) }
                            }
                        }
                    }

                    if !waiting.isEmpty {
                        NowSection("Waiting · \(waiting.count)") {
                            ForEach(waiting) { item in
                                NowRow(item: item) { WaitingRow(item: item, reason: monitor.waitReasons[item.id]) }
                            }
                        }
                    }

                    if !completed.isEmpty {
                        NowSection("Recently completed") {
                            ForEach(completed) { item in
                                NowRow(item: item) { CompletedRow(item: item) }
                            }
                            MoreLink("Show all in Queue") { model.section = .queue }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Why nothing is running, when the daemon can say: the drive is free,
    /// the disc monitor is paused, or the daemon is draining.
    @ViewBuilder
    private var idleRow: some View {
        if !needle.isEmpty, !monitor.activeItems.isEmpty {
            Text("No running item matches “\(filter)”.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            let (symbol, text): (String, String) = {
                if monitor.status?.isDraining == true {
                    return ("pause.circle", "Nothing running. Daemon is draining — nothing new will be dispatched.")
                }
                switch monitor.driveState {
                case .available: return ("opticaldisc", "Nothing running. Drive available — insert a disc.")
                case .paused: return ("pause.circle", "Nothing running. Disc monitor paused — new discs are ignored.")
                case .busy, .unknown: return ("moon.zzz", "Nothing running.")
                }
            }()
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                Text(text)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}

/// A tinted, clickable notice: daemon stopped, workflow error, draining.
private struct NoticeBanner: View {
    let title: String
    let detail: String
    let tint: Color
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: tint == .red ? "exclamationmark.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(tint.opacity(hovering ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor(hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// "Show all 10 in Attention →" under a capped section.
private struct MoreLink: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.callout)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .pointingHandCursor(hovering)
        .onHover { hovering = $0 }
    }
}

private struct NowSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.6)
                accessory
            }
            content
        }
    }
}

extension NowSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

/// A clickable, hoverable, selectable row. Keyboard-focusable and a
/// VoiceOver button, unlike a bare tap gesture.
private struct NowRow<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    let item: QueueItem
    @ViewBuilder let content: Content

    @State private var hovering = false

    init(item: QueueItem, @ViewBuilder content: () -> Content) {
        self.item = item
        self.content = content()
    }

    var body: some View {
        let selected = monitor.selectedItemID == item.id
        Button {
            model.focus(itemID: item.id)
        } label: {
            content
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : (hovering ? Color.primary.opacity(0.05) : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandCursor(hovering)
        .onHover { hovering = $0 }
        .help("Show #\(item.id) in the inspector")
        .accessibilityLabel("\(item.displayTitle), #\(item.id)")
    }
}

private struct ItemID: View {
    let id: Int64
    var body: some View {
        Text("#\(id)")
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, alignment: .leading)
    }
}

/// Title plus the small facts that tell twins apart: media type, disc number.
struct ItemTitle: View {
    let item: QueueItem
    var weight: Font.Weight = .regular

    var body: some View {
        HStack(spacing: 6) {
            Text(item.displayTitle).fontWeight(weight)
            if item.mediaType == "tv" {
                Image(systemName: "tv")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("TV")
                    .accessibilityLabel("TV")
            }
            if let disc = item.discNumber, disc > 0 {
                Text("Disc \(disc)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
    }
}

private struct AttentionRow: View {
    let item: QueueItem

    private var tint: Color { item.hasFailed ? .red : .orange }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ItemID(id: item.id)
            VStack(alignment: .leading, spacing: 2) {
                ItemTitle(item: item, weight: .semibold)
                if let reason = item.attentionReason {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            AttentionBadge(item: item)
        }
        .padding(10)
        .padding(.leading, 4)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct ActiveRow: View {
    let item: QueueItem
    let progress: [ItemProgress]

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ItemID(id: item.id)
            VStack(alignment: .leading, spacing: 4) {
                ItemTitle(item: item, weight: .semibold)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            ProgressStack(progress: progress, fallback: item.activityDescription, barWidth: 140)
        }
        .padding(.vertical, 6)
    }

    /// "Encoding · Phase 1/1 - …", or "Encoding · started 4m ago" until
    /// the task reports a message.
    private var detail: String {
        guard progress.count == 1, let only = progress.first else { return item.activityDescription }
        if !only.message.isEmpty { return item.activityDescription }
        if let elapsed = only.elapsedText(at: Date()) {
            return "\(only.stage.displayName) · started \(elapsed) ago"
        }
        return item.activityDescription
    }
}

private struct WaitingRow: View {
    let item: QueueItem
    let reason: WaitReason?

    var body: some View {
        HStack(spacing: 10) {
            ItemID(id: item.id)
            ItemTitle(item: item)
            Spacer()
            Text(text)
                .font(.callout)
                .foregroundStyle(tint)
                .help(reason?.detail ?? "Queued for \(item.stage.displayName.lowercased())")
        }
        .padding(.vertical, 3)
    }

    private var tint: Color {
        if case .ready = reason { return .accentColor }
        return .secondary
    }

    /// "Encoding · waiting for encode slot", "Analysis · after Ripping".
    private var text: String {
        guard let reason else { return "queued for \(item.stage.displayName.lowercased())" }
        return "\(reason.next.displayName) · \(reason.short)"
    }
}

/// Scheduler resource occupancy as small chips: "encode 1/1 · #21".
private struct ResourcesRow: View {
    let resources: [NamedResource]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(resources) { resource in
                let busy = resource.status.used > 0
                let holders = resource.status.holders.map { "#\($0.itemId)" }.joined(separator: " ")
                Text("\(resource.name) \(resource.status.used)/\(resource.status.capacity)\(holders.isEmpty ? "" : " · \(holders)")")
                    .font(.caption)
                    .foregroundStyle(busy ? Color.accentColor : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .help("\(resource.name): \(resource.status.used) of \(resource.status.capacity) in use")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Format.resource(resource.name)): \(resource.status.used) of \(resource.status.capacity) in use\(holders.isEmpty ? "" : " by \(holders)")")
            }
        }
    }
}

private struct CompletedRow: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            ItemID(id: item.id)
            ItemTitle(item: item)
            Spacer()
            if let size = item.encodingDetails?.encodedSize, size > 0 {
                Text(EncodingDetails.bytes(size))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(item.updatedDate, format: .relative(presentation: .named))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
