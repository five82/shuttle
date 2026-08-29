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
                            MenuRow(item: item, detail: item.activityDescription, tint: .accentColor, progress: item.progressFraction)
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
                    Label("Paused", systemImage: "pause.circle")
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
    var progress: Double? = nil

    @State private var hovering = false

    var body: some View {
        Button {
            DeepLink.open(.item(item.id))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(item.id)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(width: 34, alignment: .leading)
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
                        ProgressView(value: progress)
                            .controlSize(.small)
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
        .help("Show #\(item.id) in shuttle")
    }
}

enum MainWindow {
    static let id = "main"
}
