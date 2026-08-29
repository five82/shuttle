import SwiftUI

/// The daemon's own facts: process, paths, last error, and the external
/// tool checks it ran at startup. The right home for "why is subtitling
/// skipped".
struct DependenciesView: View {
    @Environment(SpindleMonitor.self) private var monitor

    var body: some View {
        if let status = monitor.status {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    InspectorSection("Daemon") {
                        InspectorRow("State", status.isDraining ? "Draining — nothing new is dispatched" : (status.running ? "Running" : "Stopped"), tint: status.isDraining ? .orange : nil)
                        InspectorRow("PID", String(status.pid), monospaced: true)
                        InspectorRow("Queue DB", status.queueDbPath, monospaced: true)
                        InspectorRow("Lock", status.lockFilePath, monospaced: true)
                        if !status.workflow.lastError.isEmpty {
                            InspectorRow("Last error", status.workflow.lastError, tint: .red)
                        }
                        if let disc = status.disc {
                            InspectorRow("Disc monitor", disc.paused ? "Paused" : "Watching", tint: disc.paused ? .orange : nil)
                        }
                        let stats = status.workflow.queueStats.sorted { $0.key < $1.key }
                        if !stats.isEmpty {
                            InspectorRow("Queue", stats.map { "\($0.value) \($0.key)" }.joined(separator: " · "))
                        }
                    }

                    InspectorSection("Dependencies") {
                        if status.dependencies.isEmpty {
                            Text("The daemon reported no dependency checks.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(status.dependencies) { dependency in
                                DependencyRow(dependency: dependency)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash", description: Text(monitor.connection.errorMessage ?? "Waiting for the daemon."))
        }
    }
}

private struct DependencyRow: View {
    let dependency: DependencyStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: dependency.available ? "checkmark.circle.fill" : (dependency.optional ? "minus.circle" : "xmark.circle.fill"))
                .foregroundStyle(dependency.available ? .green : (dependency.optional ? .secondary : .red))
                .frame(width: 72, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dependency.name).fontWeight(.medium)
                    if dependency.optional {
                        Text("optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(dependency.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let detail = dependency.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(dependency.available ? Color.secondary : Color.red)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
