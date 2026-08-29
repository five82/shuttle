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
        case .dependencies: return "Dependencies"
        }
    }

    var showsInspector: Bool { self == .queue || self == .attention }

    var systemImage: String {
        switch self {
        case .now: return "gauge.with.dots.needle.33percent"
        case .queue: return "list.bullet.rectangle"
        case .attention: return "exclamationmark.triangle"
        case .log: return "doc.text.magnifyingglass"
        case .dependencies: return "checklist"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    @Environment(AppSettingsStore.self) private var settingsStore

    @State private var searchText = ""
    @State private var inspectorVisible = true

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
                Group {
                    switch model.section {
                    case .now:
                        NowView()
                    case .queue:
                        QueueTableView(filter: searchText)
                    case .attention:
                        AttentionView()
                    case .log:
                        LogView(itemID: nil, showsDaemonOnlyToggle: true)
                    case .dependencies:
                        DependenciesView()
                    }
                }
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
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter queue")
        .frame(minWidth: 1100, minHeight: 620)
        .onOpenURL { url in
            if let link = DeepLink(url: url) {
                model.handle(link)
            }
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
            if let missing = monitor.status?.dependencies.filter({ !$0.available && !$0.optional }).count, missing > 0 {
                Text("\(missing)")
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
            if !monitor.items.isEmpty {
                Text("\(monitor.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
