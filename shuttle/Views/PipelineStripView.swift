import SwiftUI

/// One row of the pipeline list: a stage from the daemon's template joined
/// with the item's task for it, if any.
struct PipelineCell: Identifiable, Equatable {
    var stage: Stage
    var state: TaskState?
    var percent: Double
    var message: String
    var error: String?
    var attempts: Int
    var startedAt: Date?
    var finishedAt: Date?
    /// The stage that handed a completed item to review, tinted so the list
    /// agrees with the Review chip instead of reading all-green.
    var flagged = false
    /// 0 on the main chain; 1+ for a branch that runs beside it, so the
    /// DAG's fork (encoding alongside the GPU branch) shows as an indent.
    var depth = 0
    /// Scheduler resources the stage claims, from the template: "gpu".
    var claims: [String] = []

    var id: String { stage.rawValue }

    /// Wall time the task took, or has taken so far.
    func duration(at now: Date) -> TimeInterval? {
        guard let startedAt else { return nil }
        let end = finishedAt ?? (state == .running ? now : nil)
        guard let end, end > startedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    /// Stages come from `status.pipeline` so a new Spindle stage renders
    /// without a shuttle release; the item's own task order is the fallback.
    static func cells(for item: QueueItem, pipeline: [PipelineStageInfo]) -> [PipelineCell] {
        let tasks = Dictionary(item.taskList.map { ($0.type, $0) }, uniquingKeysWith: { first, _ in first })
        var order = pipeline.map(\.stage)
        for task in item.taskList where !order.contains(task.type) {
            order.append(task.type)
        }
        let template = Dictionary(pipeline.map { ($0.stage, $0) }, uniquingKeysWith: { first, _ in first })
        let depths = branchDepths(pipeline: pipeline)
        var cells = order.map { stage in
            let task = tasks[stage]
            var state = task?.state
            if state == nil, item.isCompleted { state = .done }
            return PipelineCell(
                stage: stage,
                state: state,
                percent: task?.progress.percent ?? 0,
                message: task?.progress.message ?? "",
                error: task?.error,
                attempts: task?.attempts ?? 0,
                startedAt: task?.startedDate,
                finishedAt: task?.finishedDate,
                depth: depths[stage] ?? 0,
                claims: template[stage]?.claims ?? []
            )
        }
        if item.needsReview, let last = cells.lastIndex(where: { $0.state == .done }) {
            cells[last].flagged = true
        }
        return cells
    }
}

extension PipelineCell {
    /// Branch depth per stage. A stage is one deeper than its parent when
    /// the parent forks and this is not the fork's first child; a join
    /// (several dependencies) returns to the shallowest of them.
    static func branchDepths(pipeline: [PipelineStageInfo]) -> [Stage: Int] {
        var children: [Stage: [Stage]] = [:]
        var parents: [Stage: [Stage]] = [:]
        for info in pipeline {
            let deps = (info.dependsOn ?? []).compactMap(Stage.init(rawValue:))
            parents[info.stage] = deps
            for dep in deps { children[dep, default: []].append(info.stage) }
        }
        var depths: [Stage: Int] = [:]
        func depth(_ stage: Stage, _ visiting: Set<Stage> = []) -> Int {
            if let known = depths[stage] { return known }
            guard !visiting.contains(stage) else { return 0 }
            let deps = parents[stage] ?? []
            let value: Int
            if deps.isEmpty {
                value = 0
            } else if deps.count > 1 {
                value = deps.map { depth($0, visiting.union([stage])) }.min() ?? 0
            } else {
                let parent = deps[0]
                let siblings = children[parent] ?? []
                let forkIndex = siblings.firstIndex(of: stage) ?? 0
                value = depth(parent, visiting.union([stage])) + (siblings.count > 1 && forkIndex > 0 ? 1 : 0)
            }
            depths[stage] = value
            return value
        }
        for info in pipeline { _ = depth(info.stage) }
        return depths
    }
}

/// The pipeline as a vertical list: state, stage, and how long it took —
/// one line per stage, so the DAG reads top to bottom instead of wrapping.
struct PipelineListView: View {
    let cells: [PipelineCell]
    var progress: ItemProgress?

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 3) {
            ForEach(cells) { cell in
                PipelineRow(cell: cell, progress: cell.state == .running ? progress : nil, now: now)
            }
        }
    }
}

private struct PipelineRow: View {
    let cell: PipelineCell
    let progress: ItemProgress?
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: inspectorLabelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if cell.depth > 0 {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .padding(.leading, CGFloat(cell.depth - 1) * 12)
                            .accessibilityLabel("runs alongside")
                    }
                    Text(cell.stage.displayName)
                        .font(.callout)
                        .foregroundStyle(cell.state == .running ? Color.accentColor : (cell.flagged ? .orange : .primary))
                    ForEach(cell.claims, id: \.self) { claim in
                        Text(claim)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                            .help("Claims the \(Format.resource(claim)) while it runs")
                    }
                    Spacer(minLength: 8)
                    Text(trailing)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(cell.state == .failed ? .red : .secondary)
                        .lineLimit(2)
                }
            }
        }
        .help(helpText)
    }

    /// "1h 12m", "66% · 43 min left", or "" for stages that never ran.
    private var trailing: String {
        if cell.state == .running {
            if let progress { return progress.shortText }
            if cell.percent > 0 { return "\(Int(cell.percent.rounded()))%" }
            return cell.duration(at: now).map(EncodingDetails.duration) ?? "running"
        }
        if let duration = cell.duration(at: now) { return EncodingDetails.duration(duration) }
        return ""
    }

    private var note: String? {
        if cell.state == .running, !cell.message.isEmpty { return cell.message }
        if cell.state == .failed, let error = cell.error, !error.isEmpty { return error }
        if cell.flagged { return "Routed to review" }
        if cell.attempts > 1 { return "\(cell.attempts) attempts" }
        return nil
    }

    private var symbol: String {
        switch cell.state {
        case .done: return cell.flagged ? "exclamationmark.triangle.fill" : "checkmark"
        case .running: return "circle.fill"
        case .failed: return "xmark"
        case .pending, .none, .unknown: return "circle"
        }
    }

    private var tint: Color {
        switch cell.state {
        case .done: return cell.flagged ? .orange : .green
        case .running: return .accentColor
        case .failed: return .red
        case .pending, .none, .unknown: return .secondary
        }
    }

    private var helpText: String {
        var parts = [cell.stage.displayName, cell.state?.rawValue ?? "not scheduled"]
        if cell.depth > 0 { parts.append("runs alongside the main chain") }
        if let started = cell.startedAt { parts.append("started \(started.formatted(date: .abbreviated, time: .shortened))") }
        if let finished = cell.finishedAt { parts.append("finished \(finished.formatted(date: .abbreviated, time: .shortened))") }
        if cell.attempts > 1 { parts.append("\(cell.attempts) attempts") }
        if let error = cell.error, !error.isEmpty { parts.append(error) }
        return parts.joined(separator: " · ")
    }
}
