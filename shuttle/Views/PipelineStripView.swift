import SwiftUI

/// One cell of the pipeline strip: a stage from the daemon's template
/// joined with the item's task for it, if any.
struct PipelineCell: Identifiable, Equatable {
    var stage: Stage
    var state: TaskState?
    var percent: Double
    var message: String
    var error: String?
    var attempts: Int

    var id: String { stage.rawValue }

    /// Stages come from `status.pipeline` so a new Spindle stage renders
    /// without a shuttle release; the item's own task order is the fallback.
    static func cells(for item: QueueItem, pipeline: [PipelineStageInfo]) -> [PipelineCell] {
        let tasks = Dictionary(item.taskList.map { ($0.type, $0) }, uniquingKeysWith: { first, _ in first })
        var order = pipeline.map(\.stage)
        for task in item.taskList where !order.contains(task.type) {
            order.append(task.type)
        }
        return order.map { stage in
            let task = tasks[stage]
            var state = task?.state
            if state == nil, item.isCompleted { state = .done }
            return PipelineCell(
                stage: stage,
                state: state,
                percent: task?.progress.percent ?? 0,
                message: task?.progress.message ?? "",
                error: task?.error,
                attempts: task?.attempts ?? 0
            )
        }
    }
}

struct PipelineStripView: View {
    let cells: [PipelineCell]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 4) {
                ForEach(cells) { cell in
                    PipelineCellView(cell: cell)
                }
            }
            ForEach(cells.filter { $0.state == .running && !$0.message.isEmpty }) { cell in
                HStack(spacing: 6) {
                    Text(cell.stage.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(cell.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct PipelineCellView: View {
    let cell: PipelineCell

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(label)
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(cell.state == nil || cell.state == .pending ? 0.08 : 0.14), in: RoundedRectangle(cornerRadius: 5))
        .help(helpText)
    }

    private var label: String {
        if cell.state == .running, cell.percent > 0 {
            return "\(cell.stage.displayName) \(Int(cell.percent.rounded()))%"
        }
        return cell.stage.displayName
    }

    private var symbol: String {
        switch cell.state {
        case .done: return "checkmark"
        case .running: return "circle.fill"
        case .failed: return "xmark"
        case .pending, .none, .unknown: return "circle"
        }
    }

    private var tint: Color {
        switch cell.state {
        case .done: return .green
        case .running: return .accentColor
        case .failed: return .red
        case .pending, .none, .unknown: return .secondary
        }
    }

    private var helpText: String {
        var parts = [cell.stage.displayName, cell.state?.rawValue ?? "not scheduled"]
        if cell.attempts > 1 { parts.append("\(cell.attempts) attempts") }
        if let error = cell.error, !error.isEmpty { parts.append(error) }
        return parts.joined(separator: " · ")
    }
}

/// Wraps children onto multiple lines. Enough for chips; not a general layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
