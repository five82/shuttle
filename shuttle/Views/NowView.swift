import SwiftUI

/// The landing view: what needs me, what is running, what the daemon is
/// holding, what just finished. Rows are buttons that select the item in
/// the inspector beside this view.
struct NowView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    @Environment(AppSettingsStore.self) private var settingsStore
    var filter = ""

    private var needle: String { filter.trimmingCharacters(in: .whitespaces).lowercased() }

    private func matching(_ items: [QueueItem]) -> [QueueItem] {
        needle.isEmpty ? items : items.filter { $0.searchableText.contains(needle) }
    }

    var body: some View {
        if monitor.status == nil, settingsStore.settings.isPlaceholderAddress {
            ContentUnavailableView {
                Label("Set the Daemon Address", systemImage: "network")
            } description: {
                Text("Spindle runs on a Linux host on your network. Enter its address, such as http://spindle.local:7487, and its API token in Settings.")
            } actions: {
                SettingsLink { Text("Open Settings…") }
                    .buttonStyle(.borderedProminent)
            }
        } else if monitor.status == nil, case .disconnected(let error, _, _) = monitor.connection {
            ContentUnavailableView {
                Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(error)
            } actions: {
                Button("Retry Now") { monitor.refreshNow() }
                SettingsLink { Text("Open Settings…") }
            }
        } else if monitor.status == nil {
            ProgressView("Connecting…")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let issue = monitor.daemonIssue {
                        DaemonIssueBanner(issue: issue) { model.section = .dependencies }
                    }

                    let attention = matching(monitor.attentionItems)
                    let active = matching(monitor.activeItems)
                    let waiting = matching(monitor.waitingItems)
                    let completed = matching(monitor.recentlyCompleted)

                    if !attention.isEmpty {
                        NowSection("Needs attention") {
                            ForEach(attention) { item in
                                NowRow(item: item) { AttentionRow(item: item) }
                            }
                        }
                    }

                    NowSection("Running", accessory: { ResourcesRow(resources: monitor.resources) }) {
                        if active.isEmpty {
                            idleRow
                        } else {
                            ForEach(active) { item in
                                NowRow(item: item) { ActiveRow(item: item, progress: monitor.progress[item.id]) }
                            }
                        }
                    }

                    if !waiting.isEmpty {
                        NowSection("Waiting · \(waiting.count)") {
                            ForEach(waiting) { item in
                                NowRow(item: item) { WaitingRow(item: item) }
                            }
                        }
                    }

                    if !completed.isEmpty {
                        NowSection("Recently completed") {
                            ForEach(completed) { item in
                                NowRow(item: item) { CompletedRow(item: item) }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var idleRow: some View {
        if !needle.isEmpty, !monitor.activeItems.isEmpty {
            Text("No running item matches “\(filter)”.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            HStack(spacing: 10) {
                Image(systemName: monitor.driveState == .available ? "opticaldisc" : "moon.zzz")
                    .foregroundStyle(.secondary)
                Text(monitor.driveState == .available ? "Nothing running. Drive available — insert a disc." : "Nothing running.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}

private struct DaemonIssueBanner: View {
    let issue: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daemon needs attention").fontWeight(.semibold)
                    Text(issue)
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
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show daemon health")
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
            Text(item.hasFailed ? "Failed" : "Review")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
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
    let progress: ItemProgress?

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
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: progress?.fraction ?? item.progressFraction)
                    .frame(width: 140)
                    .accessibilityLabel(progress?.accessibilityText ?? item.activityDescription)
                Text(progress?.shortText ?? "…")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// "Encoding · Phase 1/1 - …", or "Encoding · started 4 min ago" until
    /// the task reports a message.
    private var detail: String {
        guard let progress else { return item.activityDescription }
        if !progress.message.isEmpty { return item.activityDescription }
        if let elapsed = progress.elapsedText(at: Date()) {
            return "\(progress.stage.displayName) · started \(elapsed) ago"
        }
        return item.activityDescription
    }
}

private struct WaitingRow: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            ItemID(id: item.id)
            ItemTitle(item: item)
            Spacer()
            Text("waiting for \(item.stage.displayName.lowercased())")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
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
            Text(item.updatedDate, format: .relative(presentation: .named))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
