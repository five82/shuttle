import SwiftUI

/// Log tail with a level picker, optional daemon-only switch, local text
/// filter, and follow. Used for the daemon log and the inspector's Log tab.
struct LogView: View {
    @Environment(AppSettingsStore.self) private var settingsStore

    let itemID: Int64?
    var showsDaemonOnlyToggle = false
    var compact = false

    @State private var tailer: LogTailer?
    @State private var follow = true
    @State private var search = ""

    var body: some View {
        Group {
            if let tailer {
                content(tailer)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: itemID) {
            let tailer = LogTailer(clientProvider: { settingsStore.makeClient() }, itemID: itemID)
            self.tailer = tailer
            tailer.start()
        }
        .onDisappear {
            tailer?.stop()
            tailer = nil
        }
    }

    @ViewBuilder
    private func content(_ tailer: LogTailer) -> some View {
        @Bindable var tailer = tailer
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = needle.isEmpty ? tailer.entries : tailer.entries.filter { $0.summary.lowercased().contains(needle) }

        VStack(spacing: 0) {
            toolbar(tailer)
                .controlSize(.small)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, 6)

            Divider()

            if let error = tailer.lastError, tailer.entries.isEmpty {
                emptyState("Log Unavailable", systemImage: "doc.text.magnifyingglass", description: error)
            } else if rows.isEmpty {
                emptyState(
                    needle.isEmpty ? "No Entries" : "No Matches",
                    systemImage: needle.isEmpty ? "doc.text" : "magnifyingglass",
                    description: needle.isEmpty ? "Nothing at \(tailer.minimumLevel.rawValue.capitalized) or above yet." : "No entries contain “\(search)”."
                )
            } else {
                ScrollViewReader { proxy in
                    List(rows) { entry in
                        LogRow(entry: entry, showsItem: itemID == nil, compact: compact)
                            .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                            .id(entry.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: rows.last?.id) { _, last in
                        if follow, let last { proxy.scrollTo(last, anchor: .bottom) }
                    }
                    .onChange(of: follow) { _, on in
                        if on, let last = rows.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                    }
                    .onAppear {
                        if let last = rows.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Divider()
            HStack {
                Text("\(rows.count) of \(tailer.entries.count) entries")
                if let error = tailer.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                Spacer()
                Text("Level ≥ \(tailer.minimumLevel.rawValue)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    @ViewBuilder
    private func toolbar(_ tailer: LogTailer) -> some View {
        @Bindable var tailer = tailer
        if compact {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    levelPicker($tailer.minimumLevel)
                    Spacer(minLength: 0)
                    followToggle
                }
                filterField
            }
        } else {
            HStack(spacing: 10) {
                levelPicker($tailer.minimumLevel)
                    .frame(width: 260)
                if showsDaemonOnlyToggle {
                    Toggle("Daemon only", isOn: $tailer.daemonOnly)
                        .toggleStyle(.checkbox)
                        .help("Hide per-item entries")
                }
                filterField
                    .frame(maxWidth: 260)
                Spacer()
                followToggle
            }
        }
    }

    private func levelPicker(_ selection: Binding<LogLevel>) -> some View {
        Picker("Level", selection: selection) {
            ForEach(LogLevel.filterable, id: \.self) { level in
                Text(level.rawValue.capitalized).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Minimum level")
    }

    private var filterField: some View {
        TextField("Filter", text: $search)
            .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private var followToggle: some View {
        let toggle = Toggle(isOn: $follow) {
            Label("Follow", systemImage: "arrow.down.to.line")
        }
        .toggleStyle(.button)
        .help("Keep the newest entry in view")
        if compact {
            toggle.labelStyle(.iconOnly)
        } else {
            toggle.labelStyle(.titleAndIcon)
        }
    }

    // MARK: Empty state

    /// Fills the log area so the surrounding layout never collapses toward
    /// the vertical centre; smaller in the inspector.
    @ViewBuilder
    private func emptyState(_ title: String, systemImage: String, description: String) -> some View {
        Group {
            if compact {
                VStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            } else {
                ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LogRow: View {
    let entry: LogEntry
    let showsItem: Bool
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(time)
                    .foregroundStyle(.secondary)
                Text(entry.levelValue.rawValue)
                    .fontWeight(.bold)
                    .foregroundStyle(levelTint)
                    .frame(width: 44, alignment: .leading)
                if showsItem, let id = entry.itemID, id > 0 {
                    Text("#\(id)")
                        .foregroundStyle(Color.accentColor)
                }
                if let component = entry.component, !component.isEmpty {
                    Text(component)
                        .foregroundStyle(.secondary)
                }
                Text(entry.msg)
                    .foregroundStyle(entry.levelValue >= .warn ? levelTint : .primary)
                    .textSelection(.enabled)
            }
            let pairs = entry.fieldPairs
            if !pairs.isEmpty {
                Text(pairs.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
                    .foregroundStyle(entry.levelValue == .error ? .red : .secondary)
                    .textSelection(.enabled)
                    .lineLimit(compact ? 3 : nil)
                    .padding(.leading, compact ? 0 : 60)
            }
        }
        .font(.system(compact ? .caption : .callout, design: .monospaced))
    }

    private var time: String {
        guard let date = entry.timestamp else { return entry.ts }
        return date.formatted(date: .omitted, time: .standard)
    }

    private var levelTint: Color {
        switch entry.levelValue {
        case .debug: return .secondary
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        case .unknown: return .secondary
        }
    }
}
