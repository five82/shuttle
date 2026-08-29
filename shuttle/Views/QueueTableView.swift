import AppKit
import SwiftUI

/// Which slice of the queue the table shows; the text filter applies on top.
enum QueueScope: String, CaseIterable, Identifiable {
    case all, active, attention, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .attention: return "Attention"
        case .completed: return "Completed"
        }
    }

    func includes(_ item: QueueItem) -> Bool {
        switch self {
        case .all: return true
        case .active: return item.isActive || item.isWaiting
        case .attention: return item.needsAttention
        case .completed: return item.isCompleted && !item.needsReview
        }
    }
}

/// Every queue item in a sortable table. Default order is attention first,
/// then active, then waiting, then completed. Sort order lives on AppModel
/// so View > Reset Queue Sort can restore it.
struct QueueTableView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    @Environment(AppSettingsStore.self) private var settingsStore
    let filter: String
    /// Reveals the inspector; never hides it, so a double-click on a row is
    /// always "show me this".
    var showInspector: () -> Void = {}

    @SceneStorage("queueScope") private var scope: QueueScope = .all

    private var rows: [QueueItem] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let scoped = monitor.items.filter(scope.includes)
        let filtered = needle.isEmpty ? scoped : scoped.filter { $0.searchableText.contains(needle) }
        return filtered.sorted(using: model.queueSortOrder)
    }

    var body: some View {
        @Bindable var monitor = monitor
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $scope) {
                    ForEach(QueueScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("Which items the table lists; the search field filters within them")
                Spacer()
                Text("\(rows.count) of \(monitor.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            table
        }
    }

    private var table: some View {
        @Bindable var monitor = monitor
        @Bindable var model = model
        return Table(rows, selection: $monitor.selectedItemID, sortOrder: $model.queueSortOrder) {
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

            TableColumn("Stage", value: \.stageRank) { item in
                StageLabel(item: item, reason: monitor.waitReasons[item.id])
            }
            .width(min: 110, ideal: 190, max: 260)

            TableColumn("Progress", value: \.progressFraction) { item in
                if item.isActive {
                    ProgressStack(progress: monitor.taskProgress[item.id] ?? [], compact: true)
                        .help(item.activityDescription)
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
                    if let local = settingsStore.settings.localLibraryURL(for: path) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([local])
                        }
                    }
                }
                Divider()
                Button("Show in Inspector") { monitor.selectedItemID = id; showInspector() }
                if item.needsAttention {
                    Button("Show in Attention") { model.section = .attention; monitor.selectedItemID = id }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first { monitor.selectedItemID = id }
            showInspector()
        }
        .overlay {
            if rows.isEmpty {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        let hasFilter = !filter.trimmingCharacters(in: .whitespaces).isEmpty
        let title: String
        let symbol: String
        if hasFilter {
            title = "No Matches"
            symbol = "magnifyingglass"
        } else {
            switch scope {
            case .all: title = "Queue Is Empty"; symbol = "tray"
            case .active: title = "Nothing Active"; symbol = "moon.zzz"
            case .attention: title = "Nothing Needs Attention"; symbol = "checkmark.circle"
            case .completed: title = "Nothing Completed Yet"; symbol = "checkmark.circle"
            }
        }
        return ContentUnavailableView(title, systemImage: symbol)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// "Review", "Failed", "Encoding" while running, "Queued · after Ripping"
/// or "Queued · waiting for GPU" while waiting — so waiting and running
/// never read the same, and waiting says why.
private struct StageLabel: View {
    let item: QueueItem
    let reason: WaitReason?

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(item.needsAttention ? tint : (item.isWaiting ? .secondary : .primary))
        .help(help)
    }

    private var text: String {
        if item.hasFailed { return "Failed" }
        if item.needsReview { return "Review" }
        if item.isActive {
            let running = item.runningTasks.map(\.type.displayName)
            return running.isEmpty ? item.stage.displayName : running.joined(separator: " + ")
        }
        if item.isWaiting {
            guard let reason else { return "Queued · \(item.stage.displayName)" }
            return "Queued · \(reason.short)"
        }
        return item.stage.displayName
    }

    private var help: String {
        if item.isWaiting { return reason?.detail ?? "Queued for \(item.stage.displayName)" }
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

extension AppSettings {
    /// The library path as a file URL on this Mac, only when the mapping
    /// resolves it and the file or directory actually exists here.
    func localLibraryURL(for remotePath: String) -> URL? {
        let candidates = [localLibraryPath(for: remotePath), remotePath].compactMap { $0 }
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
