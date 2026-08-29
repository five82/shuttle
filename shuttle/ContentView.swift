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
        case .dependencies: return "Filter health"
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
                Section("Queue") {
                    ForEach(SidebarSection.queueSections) { section in
                        sidebarRow(section)
                    }
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
                StaleBanner()
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
            .navigationSubtitle(hostLabel)
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

    /// Every section takes the one toolbar search field's text as its
    /// filter. Until the first snapshot every section shows the same
    /// not-connected screen; the sections' own empty states mean "connected
    /// and empty", never "unknown".
    @ViewBuilder
    private var sectionContent: some View {
        if monitor.status == nil {
            NotConnectedView()
        } else {
            switch model.section {
            case .now:
                NowView(filter: searchText)
            case .queue:
                QueueTableView(filter: searchText, showInspector: { inspectorVisible = true })
            case .attention:
                AttentionView(filter: searchText)
            case .log:
                LogView(itemID: nil, showsDaemonOnlyToggle: true, externalFilter: searchText)
            case .dependencies:
                DependenciesView(filter: searchText)
            }
        }
    }

    /// "host:port" for the title bar; the full URL stays in Settings.
    private var hostLabel: String {
        let endpoint = settingsStore.settings.baseURLString
        guard let url = URL(string: endpoint), let host = url.host else { return "" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .badge(badgeText(for: section))
            .tag(section)
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { inspectorVisible && model.section.showsInspector && monitor.selectedItemID != nil },
            set: { inspectorVisible = $0 }
        )
    }

    /// Sidebar counts: attention and health issues in colour, pending queue
    /// items in the quiet default. Text? so `.badge` shows nothing at zero.
    private func badgeText(for section: SidebarSection) -> Text? {
        switch section {
        case .now, .log:
            return nil
        case .dependencies:
            let missing = monitor.status?.dependencies.filter { !$0.available && !$0.optional }.count ?? 0
            let issues = missing + (monitor.daemonIssue == nil ? 0 : 1)
            return issues > 0 ? Text("\(issues)").foregroundStyle(.red).bold() : nil
        case .attention:
            let count = monitor.attentionCount
            guard count > 0 else { return nil }
            let failed = monitor.attentionItems.contains(where: \.hasFailed)
            return Text("\(count)").foregroundStyle(failed ? .red : .orange).bold()
        case .queue:
            let pending = monitor.activeItems.count + monitor.waitingItems.count
            return pending > 0 ? Text("\(pending)") : nil
        }
    }
}
