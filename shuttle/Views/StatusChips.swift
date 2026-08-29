import SwiftUI

/// The always-visible health chips: daemon, drive, attention.
struct StatusChips: View {
    @Environment(SpindleMonitor.self) private var monitor

    var body: some View {
        HStack(spacing: 8) {
            daemonChip
            driveChip
            if monitor.attentionCount > 0 {
                StatusChip(
                    label: "\(monitor.attentionCount) need\(monitor.attentionCount == 1 ? "s" : "") attention",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: monitor.attentionItems.contains(where: \.hasFailed) ? .red : .orange
                )
            }
        }
    }

    @ViewBuilder private var daemonChip: some View {
        switch monitor.connection {
        case .connecting:
            StatusChip(label: "Connecting", systemImage: "circle.dotted", tint: .secondary)
        case .connected:
            if monitor.status?.isDraining == true {
                StatusChip(label: "Daemon draining", systemImage: "circle.fill", tint: .orange)
            } else {
                StatusChip(label: "Daemon running", systemImage: "circle.fill", tint: .green)
            }
        case .disconnected:
            StatusChip(label: "Disconnected", systemImage: "circle.slash", tint: .red)
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
