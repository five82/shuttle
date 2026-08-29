import SwiftUI

/// The menu bar popover: drive, running, attention. Read-only; every row
/// opens the main window at that item.
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
                StatusChip(label: "\(monitor.attentionCount)", systemImage: "exclamationmark.triangle.fill", tint: monitor.attentionItems.contains(where: \.hasFailed) ? .red : .orange)
            }
            switch monitor.connection {
            case .connected:
                if monitor.status?.running == false {
                    StatusChip(label: "Daemon stopped", systemImage: "circle.fill", tint: .red)
                } else if monitor.daemonIssue != nil {
                    StatusChip(label: "Daemon error", systemImage: "exclamationmark.circle.fill", tint: .red)
                } else if monitor.status?.isDraining == true {
                    StatusChip(label: "Draining", systemImage: "circle.fill", tint: .orange)
                }
            case .connecting:
                StatusChip(label: "Connecting", systemImage: "circle.dotted", tint: .secondary)
            case .disconnected:
                if settingsStore.settings.isPlaceholderAddress {
                    StatusChip(label: "Set address in Settings", systemImage: "network", tint: .orange)
                } else {
                    StatusChip(label: "Disconnected", systemImage: "circle.slash", tint: .red)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var driveChip: some View {
        switch monitor.driveState {
        case .unknown:
            StatusChip(label: "Drive", systemImage: "opticaldisc", tint: .secondary)
        case .available:
            StatusChip(label: "Drive available", systemImage: "opticaldisc", tint: .green)
        case .busy(let holders):
            let who = holders.first.map { " · #\($0.itemId)" } ?? ""
            StatusChip(label: "Drive busy\(who)", systemImage: "opticaldisc.fill", tint: .accentColor)
        case .paused:
            StatusChip(label: "Drive paused", systemImage: "pause.circle", tint: .orange)
        }
    }

    // MARK: Body

    @ViewBuilder
    private var sections: some View {
        VStack(alignment: .leading, spacing: 14) {
            if monitor.status == nil {
                Text(monitor.connection.errorMessage ?? "Connecting…")
                    .foregroundStyle(.secondary)
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
                            Text("and \(monitor.attentionItems.count - 5) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                        }
                    }
                }

                section("Running") {
                    if monitor.activeItems.isEmpty {
                        Text("Nothing running.")
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    } else {
                        ForEach(monitor.activeItems) { item in
                            MenuRow(item: item, detail: item.activityDescription, tint: .accentColor, progress: monitor.progress[item.id])
                        }
                    }
                }

                if !monitor.waitingItems.isEmpty {
                    Text("\(monitor.waitingItems.count) waiting")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Updated \(ConnectionStatusBar.ago(last, from: context.date))")
                    .foregroundStyle(.secondary)
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
    var progress: ItemProgress? = nil

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
                    if let progress {
                        HStack(spacing: 8) {
                            ProgressView(value: progress.fraction)
                                .controlSize(.small)
                                .accessibilityLabel(progress.accessibilityText)
                            Text(progress.shortText)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
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
        .onHover { hovering = $0 }
        .help(detail.isEmpty ? "Show #\(item.id) in shuttle" : "\(detail)\n\nClick to show #\(item.id) in shuttle")
    }
}

enum MainWindow {
    static let id = "main"
}
