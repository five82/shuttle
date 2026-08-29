import SwiftUI

/// Health: the daemon's own facts — process, paths, last error — the
/// scheduler's resources, the pipeline template, and the external tool
/// checks it ran at startup. The right home for "why is subtitling
/// skipped" and "why is nothing being dispatched".
struct DependenciesView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor
    var filter = ""

    var body: some View {
        if let status = monitor.status {
            let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
            let dependencies = status.dependencies
                .filter {
                    needle.isEmpty || "\($0.name) \($0.command) \($0.description) \($0.detail ?? "")".lowercased().contains(needle)
                }
                .sorted { a, b in
                    // Missing required first, then missing optional, then the rest in daemon order.
                    if a.severity != b.severity { return a.severity < b.severity }
                    return false
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

                    if !monitor.resources.isEmpty {
                        InspectorSection("Scheduler") {
                            ForEach(monitor.resources) { resource in
                                ResourceRow(resource: resource) { model.focus(itemID: $0) }
                            }
                        }
                    }

                    if !status.pipelineStages.isEmpty {
                        InspectorSection("Pipeline") {
                            ForEach(status.pipelineStages) { stage in
                                PipelineTemplateRow(stage: stage)
                            }
                        }
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
            NotConnectedView()
        }
    }
}

private extension DependencyStatus {
    /// 0 missing required, 1 missing optional, 2 available.
    var severity: Int {
        if available { return 2 }
        return optional ? 1 : 0
    }
}

/// "encode · 1 of 1 in use · #21 encoding", holder IDs clickable.
private struct ResourceRow: View {
    let resource: NamedResource
    let focus: (Int64) -> Void

    var body: some View {
        let status = resource.status
        let busy = status.used > 0
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(resource.name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: inspectorLabelWidth, alignment: .trailing)
            HStack(spacing: 6) {
                Text(busy ? "\(status.used) of \(status.capacity) in use" : "free · capacity \(status.capacity)")
                    .font(.callout)
                    .foregroundStyle(busy ? Color.accentColor : .primary)
                ForEach(status.holders, id: \.itemId) { holder in
                    Button("#\(holder.itemId) \(holder.task.displayName.lowercased())") { focus(holder.itemId) }
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .help("Show #\(holder.itemId) in the inspector")
                }
            }
        }
    }
}

/// One stage of the daemon's template: what it waits on and what it claims.
private struct PipelineTemplateRow: View {
    let stage: PipelineStageInfo

    var body: some View {
        let after = (stage.dependsOn ?? []).compactMap(Stage.init(rawValue:)).map(\.displayName)
        let claims = stage.claims ?? []
        var parts: [String] = []
        if !after.isEmpty { parts.append("after \(after.joined(separator: " + "))") }
        if !claims.isEmpty { parts.append("claims \(claims.joined(separator: ", "))") }
        return InspectorRow(stage.stage.displayName, parts.isEmpty ? "first stage" : parts.joined(separator: " · "))
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
