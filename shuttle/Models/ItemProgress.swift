import Foundation

/// What a running item is doing right now, derived once per snapshot by the
/// monitor so rows never decode the encoding blob in a render path.
struct ItemProgress: Equatable, Sendable {
    /// 0...1 of the furthest-along running task.
    var fraction: Double
    var stage: Stage
    var message: String
    var startedAt: Date?
    var etaSeconds: Double?
    var speed: Double?
    var currentFrame: Int64?
    var totalFrames: Int64?
    var bytesCopied: Int64?
    var totalBytes: Int64?
    var measured = true
    var measurement: String? = nil

    var hasStarted: Bool { measured && (fraction > 0 || (bytesCopied ?? 0) > 0) }

    var percentText: String { Format.percent(fraction) }

    /// "43m left" from the encoder or a running rip's elapsed progress.
    var etaText: String? {
        guard let etaSeconds, etaSeconds > 0 else { return nil }
        return "\(EncodingDetails.duration(etaSeconds)) left"
    }

    /// "1.3x"
    var speedText: String? {
        guard let speed, speed > 0 else { return nil }
        return String(format: "%.1fx", speed)
    }

    /// "12 min" since the running task started.
    func elapsedText(at now: Date) -> String? {
        guard let startedAt else { return nil }
        let seconds = now.timeIntervalSince(startedAt)
        guard seconds >= 1 else { return nil }
        return EncodingDetails.duration(seconds)
    }

    /// One short line for rows: "66% · 43m left", "12.3 GB / 40 GB",
    /// or "Starting…" before the task reports anything. Prefer the ETA to
    /// byte counts when both exist so the text fits narrow progress columns.
    var shortText: String {
        if let measurement { return measurement }
        if let totalBytes, totalBytes > 0, etaText == nil {
            let copied = ByteCountFormatter.string(fromByteCount: bytesCopied ?? 0, countStyle: .file)
            let all = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(copied) / \(all)"
        }
        guard measured else { return message.isEmpty ? "Working…" : message }
        guard hasStarted else { return "Starting…" }
        var parts = [percentText]
        if let eta = etaText { parts.append(eta) }
        return parts.joined(separator: " · ")
    }

    /// The inspector line: "66% · 1.3x · 177,507 / 258,775 frames · 43 min left".
    var detailText: String {
        if let measurement { return [message, measurement].filter { !$0.isEmpty }.joined(separator: " · ") }
        guard measured else { return message.isEmpty ? "Working…" : message }
        guard hasStarted else { return "Starting…" }
        var parts = [percentText]
        if let speed = speedText { parts.append(speed) }
        if let current = currentFrame, let total = totalFrames, total > 0 {
            parts.append("\(current.formatted()) / \(total.formatted()) frames")
        }
        if let totalBytes, totalBytes > 0 {
            let copied = ByteCountFormatter.string(fromByteCount: bytesCopied ?? 0, countStyle: .file)
            let all = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            parts.append("\(copied) / \(all)")
        }
        if let eta = etaText { parts.append(eta) }
        return parts.joined(separator: " · ")
    }

    /// VoiceOver: "Encoding, 66 percent, 43 minutes left".
    var accessibilityText: String {
        var parts = [stage.displayName, measurement ?? (measured ? (hasStarted ? "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down))) percent" : "starting") : (message.isEmpty ? "working" : message))]
        if let eta = etaText { parts.append(eta) }
        return parts.joined(separator: ", ")
    }
}

extension QueueItem {
    /// nil unless a task is working: the furthest-along working task, which
    /// is what a single bar shows. Decodes the encoding blob, so call it from
    /// the monitor, not from a view body.
    var progress: ItemProgress? {
        progressList.max { $0.fraction < $1.fraction }
    }

    /// One progress per working task in pipeline order. Encoding runs beside
    /// the GPU branch, so an item can have two; rows stack a bar per task.
    var progressList: [ItemProgress] { progressList(at: Date()) }

    /// One scoped entry per working task; measured activities take precedence
    /// over the legacy task progress slot. Never infer stage progress or ETA.
    func progressList(at now: Date) -> [ItemProgress] {
        workingTasks.sorted { $0.type.rank < $1.type.rank }.map { task in
            let running = task.activities?.filter { $0.state == "running" } ?? []
            let measured = running.first { ($0.total ?? 0) > 0 }
            let activity = measured ?? running.first
            let hasActivities = task.id != nil || !(task.activities ?? []).isEmpty
            var progress = ItemProgress(
                fraction: hasActivities ? (measured.map { min(max(Double($0.completed ?? 0) / Double($0.total ?? 1), 0), 1) } ?? 0)
                    : min(max(task.progress.percent / 100, 0), 1),
                stage: task.type,
                message: activity?.message ?? task.progress.message.trimmingCharacters(in: .whitespaces),
                startedAt: activity?.startedAt.flatMap(SpindleDate.parse) ?? task.startedDate,
                bytesCopied: hasActivities ? nil : task.progress.bytesCopied,
                totalBytes: hasActivities ? nil : task.progress.totalBytes
            )
            if hasActivities {
                progress.measured = measured != nil
                progress.measurement = measured?.measurement
            } else if task.type == .encoding, let encoding = encodingDetails {
                progress.etaSeconds = encoding.etaSeconds
                progress.speed = encoding.averageSpeed
                progress.currentFrame = encoding.currentFrame
                progress.totalFrames = encoding.totalFrames
            }
            return progress
        }
    }
}
