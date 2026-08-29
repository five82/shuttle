import SwiftUI

/// The menu bar popover: drive, running, attention. Read-only; every row
/// opens the main window at that item.
struct MenuBarView: View {
    @Environment(SpindleMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if monitor.status == nil {
                Text(monitor.connection.errorMessage ?? "Connecting…")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                driveSection

                if !monitor.attentionItems.isEmpty {
                    section("Needs attention") {
                        ForEach(monitor.attentionItems.prefix(5)) { item in
                            MenuRow(item: item, detail: item.attentionReason ?? "", tint: item.hasFailed ? .red : .orange)
                        }
                    }
                }

                section("Running") {
                    if monitor.activeItems.isEmpty {
                        Text("Nothing running.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.activeItems) { item in
                            MenuRow(item: item, detail: item.activityDescription, tint: .accentColor, progress: item.progressFraction)
                        }
                    }
                }

                if !monitor.waitingItems.isEmpty {
                    Text("\(monitor.waitingItems.count) waiting")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Open shuttle") {
                    openWindow(id: MainWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                freshness
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            switch monitor.connection {
            case .connected:
                StatusChip(label: "Daemon running", systemImage: "circle.fill", tint: .green)
            case .connecting:
                StatusChip(label: "Connecting", systemImage: "circle.dotted", tint: .secondary)
            case .disconnected:
                StatusChip(label: "Disconnected", systemImage: "circle.slash", tint: .red)
            }
            if monitor.attentionCount > 0 {
                StatusChip(label: "\(monitor.attentionCount)", systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var driveSection: some View {
        section("Drive") {
            switch monitor.driveState {
            case .unknown:
                Text("Unknown").foregroundStyle(.secondary)
            case .available:
                Label("Available — insert a disc", systemImage: "opticaldisc")
                    .foregroundStyle(.green)
            case .paused:
                Label("Paused", systemImage: "pause.circle")
                    .foregroundStyle(.orange)
            case .busy(let holders):
                let ids = holders.map { "#\($0.itemId)" }.joined(separator: ", ")
                let task = holders.first?.task.displayName.lowercased() ?? "busy"
                Label("Busy · \(task) \(ids)", systemImage: "opticaldisc.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let last = monitor.lastRefresh {
                Text("Updated \(ConnectionStatusBar.ago(last, from: context.date))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            content()
        }
    }
}

private struct MenuRow: View {
    let item: QueueItem
    let detail: String
    let tint: Color
    var progress: Double? = nil

    var body: some View {
        Button {
            DeepLink.open(.item(item.id))
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("#\(item.id)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let progress {
                        ProgressView(value: progress)
                            .controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum MainWindow {
    static let id = "main"
}
