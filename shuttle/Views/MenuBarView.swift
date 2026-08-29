import SwiftUI

/// The menu bar popover: drive, running, attention. Read-only; every row
/// opens the main window at that item, every chip at the section that
/// explains it.
///
/// `MenuBarExtra(.window)` sizes its panel from the content's fitting size
/// and does not always grow when sections appear later, which clipped the
/// footer. The body is measured explicitly and capped, so the panel always
/// has a definite height and long lists scroll instead of overflowing.
struct MenuBarView: View {
    @Environment(SpindleMonitor.self) private var monitor
    @Environment(AppSettingsStore.self) private var settingsStore
    @Environment(\.openWindow) private var openWindow

    @State private var bodyHeight: CGFloat = 0

    static let width: CGFloat = 340
    private static let maxBodyHeight: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            ScrollView(.vertical) {
                sections
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(bodyHeight, Self.maxBodyHeight))

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Header

    /// Drive first — that is what the icon encodes — then attention, then a
    /// daemon chip only when the daemon is not simply running.
    private var header: some View {
        HStack(spacing: 8) {
            if monitor.connection.isConnected {
                driveChip
            }
            if monitor.attentionCount > 0 {
                ChipButton(help: "Show the items that need attention") {
                    DeepLink.open(.section(.attention))
                } label: {
                    StatusChip(label: "\(monitor.attentionCount)", systemImage: "exclamationmark.triangle.fill", tint: monitor.attentionItems.contains(where: \.hasFailed) ? .red : .orange)
                }
            }
            switch monitor.connection {
            case .connected:
                if monitor.status?.running == false {
                    healthChip("Daemon stopped", systemImage: "circle.fill", tint: .red)
                } else if monitor.daemonIssue != nil {
                    healthChip("Daemon error", systemImage: "exclamationmark.circle.fill", tint: .red)
                } else if monitor.status?.isDraining == true {
                    healthChip("Draining", systemImage: "circle.fill", tint: .orange)
                }
            case .connecting:
                StatusChip(label: "Connecting", systemImage: "circle.dotted", tint: .secondary)
            case .disconnected:
                if settingsStore.settings.isPlaceholderAddress {
                    SettingsLink {
                        StatusChip(label: "Set address in Settings", systemImage: "network", tint: .orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    healthChip("Disconnected", systemImage: "circle.slash", tint: .red)
                }
            }
            Spacer()
        }
    }

    private func healthChip(_ label: String, systemImage: String, tint: Color) -> some View {
        ChipButton(help: monitor.daemonIssue ?? monitor.connection.errorMessage ?? "Show daemon health") {
            DeepLink.open(.section(.dependencies))
        } label: {
            StatusChip(label: label, systemImage: systemImage, tint: tint)
        }
    }

    @ViewBuilder private var driveChip: some View {
        switch monitor.driveState {
        case .unknown:
            healthChip("Drive", systemImage: "opticaldisc", tint: .secondary)
        case .available:
            ChipButton(help: "The drive is free for the next disc") {
                DeepLink.open(.section(.now))
            } label: {
                StatusChip(label: "Drive available", systemImage: "opticaldisc", tint: .green)
            }
        case .busy(let holders):
            let holder = holders.first
            let who = holder.map { " · #\($0.itemId)" } ?? ""
            ChipButton(help: holder.map { "Show #\($0.itemId)" } ?? "Drive busy") {
                DeepLink.open(holder.map { .item($0.itemId) } ?? .section(.now))
            } label: {
                StatusChip(label: "Drive busy\(who)", systemImage: "opticaldisc.fill", tint: .accentColor)
            }
        case .paused:
            healthChip("Drive paused", systemImage: "pause.circle", tint: .orange)
        }
    }

    // MARK: Body

    @ViewBuilder
    private var sections: some View {
        VStack(alignment: .leading, spacing: 14) {
            if monitor.status == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.connection.errorMessage ?? "Connecting…")
                        .foregroundStyle(.secondary)
                    if let error = monitor.connection.errorMessage, let hint = SpindleMonitor.hint(for: error) {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                if let issue = monitor.daemonIssue {
                    section("Daemon") {
                        Label(issue, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 6)
                    }
                }

                driveSection

                if !monitor.attentionItems.isEmpty {
                    section("Needs attention") {
                        ForEach(monitor.attentionItems.prefix(5)) { item in
                            MenuRow(item: item, detail: item.attentionReason ?? "", tint: item.hasFailed ? .red : .orange)
                        }
                        if monitor.attentionItems.count > 5 {
                            MenuLinkRow(title: "and \(monitor.attentionItems.count - 5) more", help: "Show all in Attention") {
                                DeepLink.open(.section(.attention))
                            }
                        }
                    }
                }

                section("Running") {
                    if monitor.activeItems.isEmpty {
                        Text(idleText)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    } else {
                        ForEach(monitor.activeItems) { item in
                            MenuRow(item: item, detail: item.activityDescription, tint: .accentColor, progress: monitor.taskProgress[item.id] ?? [])
                        }
                    }
                }

                if !monitor.waitingItems.isEmpty {
                    MenuLinkRow(title: "\(monitor.waitingItems.count) waiting", help: "Show the queue") {
                        DeepLink.open(.section(.queue))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleText: String {
        if monitor.status?.isDraining == true { return "Nothing running — daemon draining." }
        if monitor.driveState == .paused { return "Nothing running — disc monitor paused." }
        return "Nothing running."
    }

    @ViewBuilder
    private var driveSection: some View {
        section("Drive") {
            Group {
                switch monitor.driveState {
                case .unknown:
                    Label("Unknown", systemImage: "opticaldisc")
                        .foregroundStyle(.secondary)
                case .available:
                    Label("Available — insert a disc", systemImage: "opticaldisc")
                        .foregroundStyle(.green)
                case .paused:
                    Label("Paused — new discs are ignored", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                case .busy(let holders):
                    let ids = holders.map { "#\($0.itemId)" }.joined(separator: ", ")
                    let task = holders.first?.task.displayName.lowercased() ?? "busy"
                    Label("Busy · \(task) \(ids)", systemImage: "opticaldisc.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, 6)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Open shuttle") {
                openWindow(id: MainWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            freshness
            Menu {
                Button("Refresh Now") { monitor.refreshNow() }
                    .keyboardShortcut("r")
                SettingsLink { Text("Settings…") }
                    .keyboardShortcut(",")
                Divider()
                Button("Quit shuttle") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Refresh, Settings, Quit")
        }
        .font(.callout)
    }

    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let last = monitor.lastRefresh {
                Text(monitor.connection.isConnected ? "Updated \(Format.ago(last, from: context.date))" : "As of \(last.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(monitor.connection.isConnected ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .monospacedDigit()
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
                .padding(.leading, 6)
                .padding(.bottom, 2)
            content()
        }
    }
}

private struct MenuRow: View {
    let item: QueueItem
    let detail: String
    let tint: Color
    var progress: [ItemProgress] = []

    @State private var hovering = false

    var body: some View {
        Button {
            DeepLink.open(.item(item.id))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(item.id)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(minWidth: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !progress.isEmpty {
                        ProgressStack(progress: progress, compact: true)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandCursor(hovering)
        .onHover { hovering = $0 }
        .help(detail.isEmpty ? "Show #\(item.id) in shuttle" : "\(detail)\n\nClick to show #\(item.id) in shuttle")
    }
}

/// A quiet one-line row that opens a section: "3 waiting", "and 2 more".
private struct MenuLinkRow: View {
    let title: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.callout)
            .foregroundStyle(hovering ? Color.accentColor : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor(hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}

enum MainWindow {
    static let id = "main"
}
