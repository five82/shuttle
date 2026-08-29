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
                trailing
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
                Text("Updated \(Format.ago(last, from: date))")
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
                .help(SpindleMonitor.hint(for: error).map { "\(error)\n\n\($0)" } ?? error)
            Text("down since \(since.formatted(date: .omitted, time: .shortened)) · \(retry > 0 ? "retrying in \(retry)s" : "retrying…")")
                .monospacedDigit()
                .lineLimit(1)
            Button("Retry") { monitor.refreshNow() }
                .controlSize(.mini)
                .help("Poll now instead of waiting for the backoff")
            SettingsLink { Text("Settings…") }
                .controlSize(.mini)
        }
    }

    /// Counts, marked as history while disconnected.
    @ViewBuilder
    private var trailing: some View {
        if monitor.status != nil {
            let counts = "\(monitor.items.count) items · \(monitor.activeItems.count) active"
            if let last = monitor.lastRefresh, !monitor.connection.isConnected {
                Text("\(counts) · as of \(last.formatted(date: .omitted, time: .shortened))")
            } else {
                Text(counts)
            }
        }
    }

    /// "host:port" — the scheme is noise in a status bar; the full URL is
    /// in the tooltip.
    private var hostLabel: String {
        guard let url = URL(string: endpoint), let host = url.host else { return endpoint }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }
}
