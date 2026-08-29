import SwiftUI

/// The always-visible health chips: daemon, drive, attention. Each is a
/// button that jumps to the place where the state is explained.
struct StatusChips: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor

    var body: some View {
        HStack(spacing: 8) {
            daemonChip
            driveChip
            if monitor.attentionCount > 0 {
                ChipButton(help: "Show the items that need attention (⌘3)") {
                    model.section = .attention
                } label: {
                    StatusChip(
                        label: "\(monitor.attentionCount) need\(monitor.attentionCount == 1 ? "s" : "") attention",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: monitor.attentionItems.contains(where: \.hasFailed) ? .red : .orange
                    )
                }
            }
        }
    }

    @ViewBuilder private var daemonChip: some View {
        ChipButton(help: monitor.daemonIssue ?? "Show daemon health (⌘5)") {
            model.section = .dependencies
        } label: {
            switch monitor.connection {
            case .connecting:
                StatusChip(label: "Connecting", systemImage: "circle.dotted", tint: .secondary)
            case .connected:
                if monitor.status?.running == false {
                    StatusChip(label: "Daemon stopped", systemImage: "circle.fill", tint: .red)
                } else if monitor.daemonIssue != nil {
                    StatusChip(label: "Daemon error", systemImage: "exclamationmark.circle.fill", tint: .red)
                } else if monitor.status?.isDraining == true {
                    StatusChip(label: "Daemon draining", systemImage: "circle.fill", tint: .orange)
                } else {
                    StatusChip(label: "Daemon running", systemImage: "circle.fill", tint: .green)
                }
            case .disconnected:
                StatusChip(label: "Disconnected", systemImage: "circle.slash", tint: .red)
            }
        }
    }

    @ViewBuilder private var driveChip: some View {
        switch monitor.driveState {
        case .unknown:
            ChipButton(help: "Drive state unknown") { model.section = .dependencies } label: {
                StatusChip(label: "Drive", systemImage: "opticaldisc", tint: .secondary)
            }
        case .available:
            ChipButton(help: "The drive is free for the next disc") { model.section = .now } label: {
                StatusChip(label: "Drive available", systemImage: "opticaldisc", tint: .green)
            }
        case .busy(let holders):
            let holder = holders.first
            let who = holder.map { " · #\($0.itemId)" } ?? ""
            ChipButton(help: holder.map { "Show #\($0.itemId)" } ?? "Drive busy") {
                if let holder { model.focus(itemID: holder.itemId) }
            } label: {
                StatusChip(label: "Drive busy\(who)", systemImage: "opticaldisc.fill", tint: .accentColor)
            }
        case .paused:
            ChipButton(help: "The disc monitor is paused; new discs are ignored") { model.section = .dependencies } label: {
                StatusChip(label: "Drive paused", systemImage: "pause.circle", tint: .orange)
            }
        }
    }
}

/// A plain-styled button around a chip, so chips keep their look but act.
private struct ChipButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label

    init(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.help = help
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .help(help)
    }
}

struct StatusChip: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .lineLimit(1)
    }
}
