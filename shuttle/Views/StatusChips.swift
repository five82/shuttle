import SwiftUI

/// The always-visible health chips: daemon, drive, attention. Each is a
/// button that jumps to the place where the state is explained.
struct StatusChips: View {
    @Environment(AppModel.self) private var model
    @Environment(SpindleMonitor.self) private var monitor

    var body: some View {
        HStack(spacing: 8) {
            daemonChip
            driveChip
            if monitor.attentionCount > 0 {
                ChipButton(help: "Show the items that need attention (⌘3)") {
                    model.section = .attention
                } label: {
                    StatusChip(
                        label: "\(monitor.attentionCount) need\(monitor.attentionCount == 1 ? "s" : "") attention",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: monitor.attentionItems.contains(where: \.hasFailed) ? .red : .orange
                    )
                }
            }
        }
    }

    @ViewBuilder private var daemonChip: some View {
        ChipButton(help: monitor.daemonIssue ?? "Show daemon health (⌘5)") {
            model.section = .dependencies
        } label: {
            switch monitor.connection {
            case .connecting:
                StatusChip(label: "Connecting", systemImage: "circle.dotted", tint: .secondary)
            case .connected:
                if monitor.status?.running == false {
                    StatusChip(label: "Daemon stopped", systemImage: "circle.fill", tint: .red)
                } else if monitor.daemonIssue != nil {
                    StatusChip(label: "Daemon error", systemImage: "exclamationmark.circle.fill", tint: .red)
                } else if monitor.status?.isDraining == true {
                    StatusChip(label: "Daemon draining", systemImage: "circle.fill", tint: .orange)
                } else {
                    StatusChip(label: "Daemon running", systemImage: "circle.fill", tint: .green)
                }
            case .disconnected:
                StatusChip(label: "Disconnected", systemImage: "circle.slash", tint: .red)
            }
        }
    }

    @ViewBuilder private var driveChip: some View {
        switch monitor.driveState {
        case .unknown:
            ChipButton(help: "Drive state unknown") { model.section = .dependencies } label: {
                StatusChip(label: "Drive", systemImage: "opticaldisc", tint: .secondary)
            }
        case .available:
            ChipButton(help: "The drive is free for the next disc") { model.section = .now } label: {
                StatusChip(label: "Drive available", systemImage: "opticaldisc", tint: .green)
            }
        case .busy(let holders):
            let holder = holders.first
            let who = holder.map { " · #\($0.itemId)" } ?? ""
            ChipButton(help: holder.map { "Show #\($0.itemId)" } ?? "Drive busy") {
                if let holder { model.focus(itemID: holder.itemId) }
            } label: {
                StatusChip(label: "Drive busy\(who)", systemImage: "opticaldisc.fill", tint: .accentColor)
            }
        case .paused:
            ChipButton(help: "The disc monitor is paused; new discs are ignored") { model.section = .dependencies } label: {
                StatusChip(label: "Drive paused", systemImage: "pause.circle", tint: .orange)
            }
        }
    }
}

/// A plain-styled button around a chip: keeps the chip's look, adds a hover
/// fill and a pointing hand so it reads as clickable without being told.
struct ChipButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label

    @State private var hovering = false

    init(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.help = help
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .background(Color.primary.opacity(hovering ? 0.08 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor(hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct StatusChip: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .lineLimit(1)
    }
}

/// "Failed" or "Review" as a small tinted capsule; the one badge used by
/// Now, Attention, and the inspector so the state looks the same everywhere.
struct AttentionBadge: View {
    let item: QueueItem

    var body: some View {
        if item.needsAttention {
            let tint: Color = item.hasFailed ? .red : .orange
            Text(item.hasFailed ? "Failed" : "Review")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(tint.opacity(0.12), in: Capsule())
                .accessibilityLabel(item.hasFailed ? "Failed" : "Needs review")
        }
    }
}

/// One bar per running task. A single task is the usual bar-plus-number;
/// two (encoding beside the GPU branch) stack with the stage named, so the
/// number never jumps when one branch finishes.
struct ProgressStack: View {
    let progress: [ItemProgress]
    var fallback: String = "…"
    var barWidth: CGFloat? = nil
    var compact = false

    var body: some View {
        if progress.count > 1 {
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(progress, id: \.stage) { task in
                    HStack(spacing: 6) {
                        Text(task.stage.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        bar(task)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else if let task = progress.first {
            bar(task)
        } else {
            HStack(spacing: 8) {
                ProgressView(value: 0).frame(width: barWidth)
                Text(fallback).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }

    private func bar(_ task: ItemProgress) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: task.fraction)
                .controlSize(compact ? .small : .regular)
                .frame(width: barWidth)
                .accessibilityLabel(task.accessibilityText)
            Text(task.shortText)
                .font(.system(compact ? .caption2 : .caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

extension View {
    /// The pointing hand while `active`, back to the arrow otherwise. Rows
    /// and chips built from plain buttons get no cursor of their own.
    func pointingHandCursor(_ active: Bool) -> some View {
        modifier(PointingHandCursor(active: active))
    }
}

private struct PointingHandCursor: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: active) { _, hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            // A row that vanishes on a poll while hovered would leave the hand stuck.
            .onDisappear { if active { NSCursor.pop() } }
    }
}
