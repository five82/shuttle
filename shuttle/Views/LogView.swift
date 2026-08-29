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
            }
        }
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
            HStack(spacing: 10) {
                Picker("Level", selection: $tailer.minimumLevel) {
                    ForEach(LogLevel.filterable, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: compact ? 200 : 260)
                .help("Minimum level")

                if showsDaemonOnlyToggle {
                    Toggle("Daemon only", isOn: $tailer.daemonOnly)
                        .toggleStyle(.checkbox)
                        .help("Hide per-item entries")
                }

                TextField("Filter", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                Spacer()

                Toggle(isOn: $follow) {
                    Label("Follow", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .help("Keep the newest entry in view")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if let error = tailer.lastError, tailer.entries.isEmpty {
                ContentUnavailableView("Log Unavailable", systemImage: "doc.text.magnifyingglass", description: Text(error))
            } else if rows.isEmpty {
                ContentUnavailableView(
                    needle.isEmpty ? "No Entries" : "No Matches",
                    systemImage: needle.isEmpty ? "doc.text" : "magnifyingglass",
                    description: Text(needle.isEmpty ? "Nothing at \(tailer.minimumLevel.rawValue.capitalized) or above yet." : "No entries contain “\(search)”.")
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
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
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
