import SwiftUI

/// Bottom bar: freshness on the left, counts on the right. Becomes the
/// error line while disconnected.
struct ConnectionStatusBar: View {
    @Environment(SpindleMonitor.self) private var monitor
    let endpoint: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
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
            Text("Connecting to \(endpoint)…")
        case .connected:
            if let last = monitor.lastRefresh {
                Text("Updated \(Self.ago(last, from: date)) · \(endpoint)")
            } else {
                Text(endpoint)
            }
        case .disconnected(let error, let since, let nextRetry):
            let retry = max(0, Int(nextRetry.timeIntervalSince(date).rounded()))
            Label(
                "\(error) Down since \(since.formatted(date: .omitted, time: .shortened)). Retrying in \(retry)s.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
            .lineLimit(1)
            .truncationMode(.middle)
        }
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
