import SwiftUI

/// Every queue item in a sortable table. Default order is attention first,
/// then active, then waiting, then completed.
struct QueueTableView: View {
    @Environment(SpindleMonitor.self) private var monitor
    let filter: String

    @State private var sortOrder: [KeyPathComparator<QueueItem>] = [
        KeyPathComparator(\.priorityRank),
        KeyPathComparator(\.id, order: .reverse),
    ]

    private var rows: [QueueItem] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = needle.isEmpty ? monitor.items : monitor.items.filter {
            $0.displayTitle.lowercased().contains(needle)
                || $0.discTitle.lowercased().contains(needle)
                || $0.stage.displayName.lowercased().contains(needle)
                || "#\($0.id)".contains(needle)
        }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var monitor = monitor
        Table(rows, selection: $monitor.selectedItemID, sortOrder: $sortOrder) {
            TableColumn("ID", value: \.id) { item in
                Text("#\(item.id)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 56, max: 72)

            TableColumn("Title", value: \.displayTitle) { item in
                Text(item.displayTitle)
                    .fontWeight(item.needsAttention ? .semibold : .regular)
            }

            TableColumn("Stage", value: \.stageSortKey) { item in
                StageLabel(item: item)
            }
            .width(min: 90, ideal: 120, max: 160)

            TableColumn("Progress", value: \.progressFraction) { item in
                if item.isActive {
                    ProgressView(value: item.progressFraction)
                } else {
                    Text("")
                }
            }
            .width(min: 80, ideal: 140, max: 220)

            TableColumn("Age", value: \.createdDate) { item in
                Text(item.createdDate, format: .relative(presentation: .numeric))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120, max: 160)
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
}

private struct StageLabel: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text)
        }
        .foregroundStyle(item.needsAttention ? tint : .primary)
    }

    private var text: String {
        if item.hasFailed { return "Failed" }
        if item.needsReview { return "Review" }
        if item.isActive { return item.runningTasks.first?.type.displayName ?? item.stage.displayName }
        return item.stage.displayName
    }

    private var tint: Color {
        if item.hasFailed { return .red }
        if item.needsReview { return .orange }
        if item.isActive { return .accentColor }
        if item.isCompleted { return .green }
        return .secondary
    }
}
