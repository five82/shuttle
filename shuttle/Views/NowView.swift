import SwiftUI

/// The landing view: what needs me, what is running, what the daemon is
/// holding, what just finished.
struct NowView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor

    var body: some View {
        if monitor.status == nil, case .disconnected(let error, _, _) = monitor.connection {
            ContentUnavailableView {
                Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(error)
            }
        } else if monitor.status == nil {
            ProgressView("Connecting…")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !monitor.attentionItems.isEmpty {
                        NowSection("Needs attention") {
                            ForEach(monitor.attentionItems) { item in
                                AttentionRow(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.focus(itemID: item.id) }
                            }
                        }
                    }

                    NowSection("Running") {
                        if monitor.activeItems.isEmpty {
                            idleRow
                        } else {
                            ForEach(monitor.activeItems) { item in
                                ActiveRow(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.focus(itemID: item.id) }
                            }
                        }
                    }

                    if !monitor.waitingItems.isEmpty {
                        NowSection("Waiting · \(monitor.waitingItems.count)") {
                            ForEach(monitor.waitingItems) { item in
                                WaitingRow(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.focus(itemID: item.id) }
                            }
                        }
                    }

                    if !monitor.resources.isEmpty {
                        NowSection("Resources") {
                            ResourcesRow(resources: monitor.resources)
                        }
                    }

                    if !monitor.recentlyCompleted.isEmpty {
                        NowSection("Recently completed") {
                            ForEach(monitor.recentlyCompleted) { item in
                                CompletedRow(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.focus(itemID: item.id) }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var idleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: monitor.driveState == .available ? "opticaldisc" : "moon.zzz")
                .foregroundStyle(.secondary)
            Text(monitor.driveState == .available ? "Nothing running. Drive available — insert a disc." : "Nothing running.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct NowSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
            content
        }
    }
}

private struct ItemID: View {
    let id: Int64
    var body: some View {
        Text("#\(id)")
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .leading)
    }
}

private struct AttentionRow: View {
    let item: QueueItem

    private var tint: Color { item.hasFailed ? .red : .orange }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ItemID(id: item.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).fontWeight(.semibold)
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
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct ActiveRow: View {
    let item: QueueItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ItemID(id: item.id)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle).fontWeight(.semibold)
                Text(item.activityDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: item.progressFraction)
                    .frame(width: 140)
                Text(progressLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var progressLabel: String {
        if let task = item.runningTasks.first(where: { ($0.progress.totalBytes ?? 0) > 0 }),
           let total = task.progress.totalBytes {
            let copied = ByteCountFormatter.string(fromByteCount: task.progress.bytesCopied ?? 0, countStyle: .file)
            let all = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "\(copied) / \(all)"
        }
        return item.progressFraction > 0 ? "\(Int((item.progressFraction * 100).rounded()))%" : "…"
    }
}

private struct WaitingRow: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            ItemID(id: item.id)
            Text(item.displayTitle)
            Spacer()
            Text("waiting for \(item.stage.displayName.lowercased())")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct ResourcesRow: View {
    let resources: [NamedResource]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(resources) { resource in
                let busy = resource.status.used > 0
                let holders = resource.status.holders.map { "#\($0.itemId)" }.joined(separator: " ")
                Text("\(resource.name) \(resource.status.used)/\(resource.status.capacity)\(holders.isEmpty ? "" : " · \(holders)")")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(busy ? Color.accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((busy ? Color.accentColor : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

private struct CompletedRow: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            ItemID(id: item.id)
            Text(item.displayTitle)
            Spacer()
            Text(item.updatedDate, format: .relative(presentation: .named))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
