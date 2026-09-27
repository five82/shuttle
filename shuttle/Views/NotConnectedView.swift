import SwiftUI

/// The one screen every section shows before the first snapshot: set the
/// address, connecting, or an error with the hint that usually fixes it.
/// Sections never render their own empty states while nothing is known, so
/// a first launch that lands on Attention cannot say "nothing needs you".
struct NotConnectedView: View {
    @Environment(SpindleMonitor.self) private var monitor
    @Environment(AppSettingsStore.self) private var settingsStore

    enum State: Equatable {
        case setAddress
        case connecting
        case disconnected(error: String, hint: String?)
    }

    /// Before the first snapshot, the placeholder is an instruction rather
    /// than a connection failure; a real address can show actionable errors.
    static func state(placeholder: Bool, connection: ConnectionState) -> State {
        if placeholder { return .setAddress }
        if case .disconnected(let error, _, _) = connection {
            return .disconnected(error: error, hint: SpindleMonitor.hint(for: error))
        }
        return .connecting
    }

    var body: some View {
        switch Self.state(placeholder: settingsStore.settings.isPlaceholderAddress, connection: monitor.connection) {
        case .setAddress:
            ContentUnavailableView {
                Label("Set the Daemon Address", systemImage: "network")
            } description: {
                Text("Spindle runs on a Linux host on your network. Enter its address, such as http://spindle.local:7487, and its API token in Settings.")
            } actions: {
                SettingsLink { Text("Open Settings…") }
                    .buttonStyle(.borderedProminent)
            }
        case .disconnected(let error, let hint):
            ContentUnavailableView {
                Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                VStack(spacing: 6) {
                    Text(error)
                    if let hint {
                        Text(hint)
                            .foregroundStyle(.secondary)
                    }
                }
            } actions: {
                Button("Retry Now") { monitor.refreshNow() }
                SettingsLink { Text("Open Settings…") }
            }
        case .connecting:
            ProgressView("Connecting…")
        }
    }
}

/// Shown above the content while the daemon is unreachable but a snapshot
/// is still on screen, so live-looking numbers are read as history.
struct StaleBanner: View {
    @Environment(SpindleMonitor.self) private var monitor

    var body: some View {
        if case .disconnected(let error, _, _) = monitor.connection, let last = monitor.lastRefresh {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Showing data from \(last.formatted(date: .omitted, time: .shortened)) · \(Format.ago(last, from: context.date))")
                            .fontWeight(.medium)
                            .monospacedDigit()
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Retry") { monitor.refreshNow() }
                        .controlSize(.small)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.10))
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }
}
