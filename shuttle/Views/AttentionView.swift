import SwiftUI

/// Triage list: every failed or review item with its lead reason. Clicking a
/// row opens it in the inspector.
struct AttentionView: View {
    @Environment(SpindleMonitor.self) private var monitor

    var body: some View {
        @Bindable var monitor = monitor
        if monitor.attentionItems.isEmpty {
            ContentUnavailableView {
                Label("Nothing Needs Attention", systemImage: "checkmark.circle")
            } description: {
                Text("Failed and review items will appear here.")
            }
        } else {
            List(monitor.attentionItems, selection: $monitor.selectedItemID) { item in
                AttentionListRow(item: item)
                    .tag(item.id)
            }
        }
    }
}

private struct AttentionListRow: View {
    let item: QueueItem

    private var tint: Color { item.hasFailed ? .red : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("#\(item.id)")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.displayTitle).fontWeight(.semibold)
                    Text(item.hasFailed ? "Failed" : "Review")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                if let reason = item.attentionReason {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(item.updatedDate, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
