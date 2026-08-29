import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case now
    case queue
    case attention
    case log
    case dependencies

    static let queueSections: [SidebarSection] = [.now, .queue, .attention]
    static let daemonSections: [SidebarSection] = [.log, .dependencies]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Now"
        case .queue: return "Queue"
        case .attention: return "Attention"
        case .log: return "Log"
        case .dependencies: return "Health"
        }
    }

    /// Sections where selecting an item opens the inspector beside it.
    var showsInspector: Bool { self == .now || self == .queue || self == .attention }

    /// What the toolbar search field filters in this section. One field is
    /// always present: adding and removing it per section makes SwiftUI
    /// re-insert the toolbar item and AppKit throws on the duplicate.
    var searchPrompt: String {
        switch self {
        case .now: return "Filter now"
        case .queue: return "Filter queue"
        case .attention: return "Filter attention"
        case .log: return "Filter log"
        case .dependencies: return "Filter dependencies"
        }
    }

    var systemImage: String {
        switch self {
        case .now: return "gauge.with.dots.needle.33percent"
        case .queue: return "list.bullet.rectangle"
        case .attention: return "exclamationmark.triangle"
        case .log: return "doc.text.magnifyingglass"
        case .dependencies: return "heart.text.square"
        }
    }

    /// ⌘1 … ⌘5, in sidebar order.
    var shortcutKey: KeyEquivalent {
        switch self {
        case .now: return "1"
        case .queue: return "2"
        case .attention: return "3"
        case .log: return "4"
        case .dependencies: return "5"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    @Environment(AppSettingsStore.self) private var settingsStore

    @State private var searchText = ""
    @SceneStorage("inspectorVisible") private var inspectorVisible = true

    var body: some View {
        @Bindable var model = model
        let section = Binding<SidebarSection?>(
            get: { model.section },
            set: { model.section = $0 ?? .now }
        )
        NavigationSplitView {
            List(selection: section) {
                ForEach(SidebarSection.queueSections) { section in
                    sidebarRow(section)
                }
                Section("Daemon") {
                    ForEach(SidebarSection.daemonSections) { section in
                        sidebarRow(section)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .inspector(isPresented: inspectorBinding) {
                        ItemInspectorView()
                            .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
                    }

                Divider()
                ConnectionStatusBar(endpoint: settingsStore.settings.baseURLString)
            }
            .navigationTitle(model.section.title)
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                StatusChips()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorVisible.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector (⌥⌘I)")
                .keyboardShortcut("i", modifiers: [.option, .command])
                .disabled(!model.section.showsInspector || monitor.selectedItemID == nil)
            }
        }
        .onChange(of: monitor.selectedItemID) { _, id in
            if id != nil { inspectorVisible = true }
        }
        .onChange(of: model.section) { _, _ in
            searchText = ""
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: model.section.searchPrompt)
        .frame(minWidth: 900, minHeight: 600)
        .onOpenURL { url in
            if let link = DeepLink(url: url) {
                model.handle(link)
            }
        }
    }

    /// Every section takes the one toolbar search field's text as its filter.
    @ViewBuilder
    private var sectionContent: some View {
        switch model.section {
        case .now:
            NowView(filter: searchText)
        case .queue:
            QueueTableView(filter: searchText, toggleInspector: { inspectorVisible.toggle() })
        case .attention:
            AttentionView(filter: searchText)
        case .log:
            LogView(itemID: nil, showsDaemonOnlyToggle: true, externalFilter: searchText)
        case .dependencies:
            DependenciesView(filter: searchText)
        }
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label {
            HStack {
                Text(section.title)
                Spacer()
                badge(for: section)
            }
        } icon: {
            Image(systemName: section.systemImage)
        }
        .tag(section)
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { inspectorVisible && model.section.showsInspector && monitor.selectedItemID != nil },
            set: { inspectorVisible = $0 }
        )
    }

    @ViewBuilder
    private func badge(for section: SidebarSection) -> some View {
        switch section {
        case .now, .log:
            EmptyView()
        case .dependencies:
            let missing = monitor.status?.dependencies.filter { !$0.available && !$0.optional }.count ?? 0
            let issues = missing + (monitor.daemonIssue == nil ? 0 : 1)
            if issues > 0 {
                Text("\(issues)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        case .attention:
            if monitor.attentionCount > 0 {
                Text("\(monitor.attentionCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(monitor.attentionItems.contains(where: \.hasFailed) ? .red : .orange)
            }
        case .queue:
            let pending = monitor.activeItems.count + monitor.waitingItems.count
            if pending > 0 {
                Text("\(pending)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("\(pending) item\(pending == 1 ? "" : "s") still in the pipeline")
            }
        }
    }
}
