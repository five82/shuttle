import SwiftUI

/// Health: the daemon's own facts — process, paths, last error — and the
/// external tool checks it ran at startup. The right home for "why is
/// subtitling skipped" and "why is nothing being dispatched".
struct DependenciesView: View {
    @Environment(SpindleMonitor.self) private var monitor
    var filter = ""

    var body: some View {
        if let status = monitor.status {
            let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
            let dependencies = needle.isEmpty ? status.dependencies : status.dependencies.filter {
                "\($0.name) \($0.command) \($0.description) \($0.detail ?? "")".lowercased().contains(needle)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    InspectorSection("Daemon", tint: monitor.daemonIssue == nil ? .secondary : .red) {
                        if let issue = monitor.daemonIssue {
                            InspectorRow("Problem", issue, tint: .red)
                        }
                        InspectorRow("State", status.isDraining ? "Draining — nothing new is dispatched" : (status.running ? "Running" : "Stopped"), tint: status.isDraining ? .orange : (status.running ? nil : .red))
                        if let disc = status.disc {
                            InspectorRow("Disc monitor", disc.paused ? "Paused — new discs are ignored" : "Watching", tint: disc.paused ? .orange : nil)
                        }
                        let stats = status.workflow.queueStats.sorted { $0.key < $1.key }
                        if !stats.isEmpty {
                            InspectorRow("Queue", stats.map { "\($0.value) \($0.key)" }.joined(separator: " · "))
                        }
                        if !status.workflow.lastError.isEmpty {
                            InspectorRow("Last error", status.workflow.lastError, tint: .red)
                        }
                        InspectorRow("PID", String(status.pid), monospaced: true)
                        InspectorRow("Queue DB", status.queueDbPath, monospaced: true)
                        InspectorRow("Lock", status.lockFilePath, monospaced: true)
                    }

                    let missing = status.dependencies.filter { !$0.available && !$0.optional }.count
                    InspectorSection(missing > 0 ? "Dependencies · \(missing) missing" : "Dependencies", tint: missing > 0 ? .red : .secondary) {
                        if status.dependencies.isEmpty {
                            Text("The daemon reported no dependency checks.")
                                .foregroundStyle(.secondary)
                        } else if dependencies.isEmpty {
                            Text("No dependencies match “\(filter)”.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dependencies) { dependency in
                                DependencyRow(dependency: dependency)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView {
                Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(monitor.connection.errorMessage ?? "Waiting for the daemon.")
            } actions: {
                Button("Retry Now") { monitor.refreshNow() }
                SettingsLink { Text("Open Settings…") }
            }
        }
    }
}

private struct DependencyRow: View {
    let dependency: DependencyStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: dependency.available ? "checkmark.circle.fill" : (dependency.optional ? "minus.circle" : "xmark.circle.fill"))
                .foregroundStyle(dependency.available ? .green : (dependency.optional ? .secondary : .red))
                .frame(width: 20)
                .accessibilityLabel(dependency.available ? "available" : (dependency.optional ? "optional, missing" : "missing"))
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
