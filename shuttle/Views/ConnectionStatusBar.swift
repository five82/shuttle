import SwiftUI

/// Bottom bar: freshness on the left, counts on the right. Becomes the
/// error line while disconnected, with Retry and Settings one click away.
struct ConnectionStatusBar: View {
    @Environment(SpindleMonitor.self) private var monitor
    let endpoint: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                leading(at: context.date)
                Spacer()
                Text("\(monitor.items.count) items · \(monitor.activeItems.count) active")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func leading(at date: Date) -> some View {
        switch monitor.connection {
        case .connecting:
            Text("Connecting to \(hostLabel)…")
        case .connected:
            if let last = monitor.lastRefresh {
                Text("Updated \(Self.ago(last, from: date)) · \(hostLabel)")
                    .monospacedDigit()
                    .help(endpoint)
            } else {
                Text(hostLabel).help(endpoint)
            }
        case .disconnected(let error, let since, let nextRetry):
            let retry = max(0, Int(nextRetry.timeIntervalSince(date).rounded()))
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(error)
            Text("\(hostLabel) · down since \(since.formatted(date: .omitted, time: .shortened)) · retrying in \(retry)s")
                .monospacedDigit()
                .lineLimit(1)
            Button("Retry") { monitor.refreshNow() }
                .controlSize(.mini)
                .help("Poll now instead of waiting for the backoff")
            SettingsLink { Text("Settings…") }
                .controlSize(.mini)
        }
    }

    /// "host:port" — the scheme is noise in a status bar; the full URL is
    /// in the tooltip.
    private var hostLabel: String {
        guard let url = URL(string: endpoint), let host = url.host else { return endpoint }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    static func ago(_ date: Date, from now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        if seconds < 2 { return "just now" }
        if seconds < 60 { return "\(seconds) s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60) h ago"
    }
}
