import AppKit
import SwiftUI

/// Every queue item in a sortable table. Default order is attention first,
/// then active, then waiting, then completed. Sort order lives on AppModel
/// so View > Reset Queue Sort can restore it.
struct QueueTableView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    let filter: String
    var toggleInspector: () -> Void = {}

    private var rows: [QueueItem] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = needle.isEmpty ? monitor.items : monitor.items.filter { $0.searchableText.contains(needle) }
        return filtered.sorted(using: model.queueSortOrder)
    }

    var body: some View {
        @Bindable var monitor = monitor
        @Bindable var model = model
        Table(rows, selection: $monitor.selectedItemID, sortOrder: $model.queueSortOrder) {
            TableColumn("ID", value: \.id) { item in
                Text("#\(item.id)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60, max: 90)

            TableColumn("Title", value: \.displayTitle) { item in
                ItemTitle(item: item, weight: item.needsAttention ? .semibold : .regular)
            }
            .width(min: 180, ideal: 280)

            TableColumn("Stage", value: \.stageSortKey) { item in
                StageLabel(item: item)
            }
            .width(min: 110, ideal: 150, max: 200)

            TableColumn("Progress", value: \.progressFraction) { item in
                if item.isActive {
                    ProgressCell(item: item, progress: monitor.progress[item.id])
                } else {
                    EmptyView()
                }
            }
            .width(min: 100, ideal: 180, max: 260)

            TableColumn("Updated", value: \.updatedDate) { item in
                Text(item.updatedDate, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                    .help("Created \(item.createdDate.formatted(date: .abbreviated, time: .shortened))")
            }
            .width(min: 90, ideal: 120, max: 160)
        }
        .contextMenu(forSelectionType: QueueItem.ID.self) { ids in
            if let id = ids.first, let item = monitor.items.first(where: { $0.id == id }) {
                Button("Copy Title") { copy(item.displayTitle) }
                Button("Copy ID") { copy("\(item.id)") }
                if let path = item.finalPath {
                    Button("Copy Final Path") { copy(path) }
                    if FileManager.default.fileExists(atPath: path) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                }
                Divider()
                Button("Show in Inspector") { monitor.selectedItemID = id; toggleInspector() }
                if item.needsAttention {
                    Button("Show in Attention") { model.section = .attention; monitor.selectedItemID = id }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first { monitor.selectedItemID = id }
            toggleInspector()
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    filter.isEmpty ? "Queue is empty" : "No matches",
                    systemImage: filter.isEmpty ? "tray" : "magnifyingglass"
                )
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// Bar plus the number the bar can't show: "66% · 43 min left".
private struct ProgressCell: View {
    let item: QueueItem
    let progress: ItemProgress?

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: progress?.fraction ?? item.progressFraction)
                .accessibilityLabel(progress?.accessibilityText ?? item.activityDescription)
            Text(progress?.shortText ?? "…")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .help(item.activityDescription)
    }
}

/// "Review", "Failed", "Encoding" while running, "Queued · Encoding" while
/// waiting for the slot — so waiting and running never read the same.
private struct StageLabel: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text)
        }
        .foregroundStyle(item.needsAttention ? tint : (item.isWaiting ? .secondary : .primary))
        .help(help)
    }

    private var text: String {
        if item.hasFailed { return "Failed" }
        if item.needsReview { return "Review" }
        if item.isActive { return item.runningTasks.first?.type.displayName ?? item.stage.displayName }
        if item.isWaiting { return "Queued · \(item.stage.displayName)" }
        return item.stage.displayName
    }

    private var help: String {
        if item.isWaiting { return "Waiting for a \(item.stage.displayName.lowercased()) slot" }
        if item.isActive { return item.activityDescription }
        return item.attentionReason ?? item.stage.displayName
    }

    private var tint: Color {
        if item.hasFailed { return .red }
        if item.needsReview { return .orange }
        if item.isActive { return .accentColor }
        if item.isCompleted { return .green }
        return .secondary
    }
}
