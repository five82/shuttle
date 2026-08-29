import AppKit
import SwiftUI

/// Log tail with a minimum-level picker, optional daemon-only switch, local
/// text filter, and follow. Used for the daemon log and the inspector's Log
/// tab. When `externalFilter` is set the toolbar search field owns the text
/// filter and no local field is shown.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettingsStore.self) private var settingsStore

    let itemID: Int64?
    var showsDaemonOnlyToggle = false
    var compact = false
    var externalFilter: String? = nil

    @State private var tailer: LogTailer?
    @State private var follow = true
    @State private var search = ""
    /// The newest seq the operator has seen; new entries past it are counted
    /// while follow is off.
    @State private var seenSeq: UInt64 = 0

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

    private var filterText: String { externalFilter ?? search }

    @ViewBuilder
    private func content(_ tailer: LogTailer) -> some View {
        @Bindable var tailer = tailer
        let needle = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = needle.isEmpty ? tailer.entries : tailer.entries.filter { $0.summary.lowercased().contains(needle) }
        let unseen = follow ? 0 : rows.filter { $0.seq > seenSeq }.count

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
                    description: needle.isEmpty ? "Nothing at \(tailer.minimumLevel.rawValue.capitalized) or above yet." : "No entries contain “\(filterText)”."
                )
            } else {
                ScrollViewReader { proxy in
                    List(rows) { entry in
                        LogRow(entry: entry, showsItem: itemID == nil, compact: compact) { id in
                            model.focus(itemID: id)
                        }
                        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        .listRowBackground(rowBackground(entry))
                        .id(entry.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: rows.last?.id) { _, last in
                        if follow, let last {
                            proxy.scrollTo(last, anchor: .bottom)
                            seenSeq = last
                        }
                    }
                    .onChange(of: follow) { _, on in
                        if on, let last = rows.last?.id {
                            proxy.scrollTo(last, anchor: .bottom)
                            seenSeq = last
                        } else if !on, let last = rows.last?.id {
                            seenSeq = last
                        }
                    }
                    .onAppear {
                        if let last = rows.last?.id {
                            proxy.scrollTo(last, anchor: .bottom)
                            seenSeq = last
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if unseen > 0 {
                            Button {
                                follow = true
                            } label: {
                                Label("\(unseen) new", systemImage: "arrow.down")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.regularMaterial, in: Capsule())
                                    .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 8)
                            .help("Scroll to the newest entries and follow")
                        }
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
                if follow {
                    Label("Following", systemImage: "arrow.down.to.line")
                } else {
                    Label("Paused", systemImage: "pause")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowBackground(_ entry: LogEntry) -> Color {
        switch entry.levelValue {
        case .error: return Color.red.opacity(0.08)
        case .warn: return Color.orange.opacity(0.07)
        default: return .clear
        }
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
                if externalFilter == nil {
                    filterField
                }
            }
        } else {
            HStack(spacing: 10) {
                Text("Min level")
                    .foregroundStyle(.secondary)
                levelPicker($tailer.minimumLevel)
                    .frame(width: 260)
                if showsDaemonOnlyToggle {
                    Toggle("Daemon only", isOn: $tailer.daemonOnly)
                        .toggleStyle(.checkbox)
                        .help("Hide per-item entries")
                }
                if externalFilter == nil {
                    filterField
                        .frame(maxWidth: 260)
                }
                Spacer()
                followToggle
            }
        }
    }

    private func levelPicker(_ selection: Binding<LogLevel>) -> some View {
        Picker("Minimum level", selection: selection) {
            ForEach(LogLevel.filterable, id: \.self) { level in
                Text(level.rawValue.capitalized).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Show this level and above")
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
    let focusItem: (Int64) -> Void

    @State private var expanded = false

    /// Keys shown inline; everything else folds behind "+N fields".
    private static let inlineKeys: Set<String> = ["message", "error", "event_type", "episode_key", "stage", "path", "reason"]

    var body: some View {
        let pairs = entry.fieldPairs
        let inline = pairs.filter { Self.inlineKeys.contains($0.key) }
        let folded = pairs.filter { !Self.inlineKeys.contains($0.key) }
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(time)
                    .foregroundStyle(.secondary)
                    .help(entry.timestamp?.formatted(date: .complete, time: .complete) ?? entry.ts)
                Text(entry.levelValue.rawValue)
                    .fontWeight(.bold)
                    .foregroundStyle(levelTint)
                    .frame(width: 44, alignment: .leading)
                if showsItem, let id = entry.itemID, id > 0 {
                    Button("#\(id)") { focusItem(id) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help("Show #\(id) in the inspector")
                }
                if let stage = entry.stage, !stage.isEmpty {
                    Text(stage)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 3))
                }
                if let component = entry.component, !component.isEmpty {
                    Text(component)
                        .foregroundStyle(.secondary)
                }
                Text(entry.msg)
                    .foregroundStyle(entry.levelValue >= .warn ? levelTint : .primary)
                    .textSelection(.enabled)
            }
            if !pairs.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    let shown = expanded ? pairs : inline
                    if !shown.isEmpty {
                        Text(shown.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
                            .foregroundStyle(entry.levelValue == .error ? .red : .secondary)
                            .textSelection(.enabled)
                            .lineLimit(expanded ? nil : (compact ? 3 : 2))
                            .truncationMode(.middle)
                    }
                    if !folded.isEmpty {
                        Button(expanded ? "less" : "+\(folded.count) field\(folded.count == 1 ? "" : "s")") {
                            expanded.toggle()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help(expanded ? "Hide the other fields" : folded.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
                    }
                }
                .padding(.leading, compact ? 0 : 60)
            }
        }
        .font(.system(compact ? .caption : .callout, design: .monospaced))
        .contextMenu {
            Button("Copy Line") { copy(line) }
            if !pairs.isEmpty {
                Button("Copy Fields") { copy(pairs.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")) }
            }
            if showsItem, let id = entry.itemID, id > 0 {
                Divider()
                Button("Show #\(id)") { focusItem(id) }
            }
        }
    }

    private var line: String {
        var parts = [entry.ts, entry.levelValue.rawValue]
        if let id = entry.itemID, id > 0 { parts.append("#\(id)") }
        if let component = entry.component, !component.isEmpty { parts.append(component) }
        parts.append(entry.summary)
        return parts.joined(separator: " ")
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Time only for today; date prefix once the tail crosses midnight.
    private var time: String {
        guard let date = entry.timestamp else { return entry.ts }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .standard)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
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
