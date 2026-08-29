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
                finishedAt: task?.finishedDate
            )
        }
        if item.needsReview, let last = cells.lastIndex(where: { $0.state == .done }) {
            cells[last].flagged = true
        }
        return cells
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
                .frame(width: 90, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(cell.stage.displayName)
                        .font(.callout)
                        .foregroundStyle(cell.state == .running ? Color.accentColor : (cell.flagged ? .orange : .primary))
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
        if let started = cell.startedAt { parts.append("started \(started.formatted(date: .abbreviated, time: .shortened))") }
        if let finished = cell.finishedAt { parts.append("finished \(finished.formatted(date: .abbreviated, time: .shortened))") }
        if cell.attempts > 1 { parts.append("\(cell.attempts) attempts") }
        if let error = cell.error, !error.isEmpty { parts.append(error) }
        return parts.joined(separator: " · ")
    }
}
