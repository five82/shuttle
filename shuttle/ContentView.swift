import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case now
    case queue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Now"
        case .queue: return "Queue"
        }
    }

    var systemImage: String {
        switch self {
        case .now: return "gauge.with.dots.needle.33percent"
        case .queue: return "list.bullet.rectangle"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    @Environment(AppSettingsStore.self) private var settingsStore

    @State private var searchText = ""

    var body: some View {
        @Bindable var model = model
        let section = Binding<SidebarSection?>(
            get: { model.section },
            set: { model.section = $0 ?? .now }
        )
        NavigationSplitView {
            List(SidebarSection.allCases, selection: section) { section in
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
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch model.section {
                    case .now:
                        NowView()
                    case .queue:
                        QueueTableView(filter: searchText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                ConnectionStatusBar(endpoint: settingsStore.settings.baseURLString)
            }
            .navigationTitle(model.section.title)
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                StatusChips()
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter queue")
        .frame(minWidth: 900, minHeight: 600)
        .onOpenURL { url in
            if let link = DeepLink(url: url) {
                model.handle(link)
            }
        }
    }

    @ViewBuilder
    private func badge(for section: SidebarSection) -> some View {
        switch section {
        case .now:
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
