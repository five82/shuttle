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

    var hasStarted: Bool { fraction > 0 || (bytesCopied ?? 0) > 0 }

    var percentText: String { Format.percent(fraction) }

    /// "43 min left" from the encoder's estimate.
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

    /// One short line for rows: "66% · 43 min left", "12.3 GB / 40 GB",
    /// or "Starting…" before the task reports anything.
    var shortText: String {
        if let totalBytes, totalBytes > 0 {
            let copied = ByteCountFormatter.string(fromByteCount: bytesCopied ?? 0, countStyle: .file)
            let all = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(copied) / \(all)"
        }
        guard hasStarted else { return "Starting…" }
        var parts = [percentText]
        if let eta = etaText { parts.append(eta) }
        return parts.joined(separator: " · ")
    }

    /// The inspector line: "66% · 1.3x · 177,507 / 258,775 frames · 43 min left".
    var detailText: String {
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
        var parts = [stage.displayName, hasStarted ? "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down))) percent" : "starting"]
        if let eta = etaText { parts.append(eta) }
        return parts.joined(separator: ", ")
    }
}

extension QueueItem {
    /// nil unless a task is running: the furthest-along running task, which
    /// is what a single bar shows. Decodes the encoding blob, so call it from
    /// the monitor, not from a view body.
    var progress: ItemProgress? {
        progressList.max { $0.fraction < $1.fraction }
    }

    /// One progress per running task in pipeline order. Encoding runs beside
    /// the GPU branch, so an item can have two; rows stack a bar per task.
    var progressList: [ItemProgress] {
        let encoding = runningTasks.contains { $0.type == .encoding } ? encodingDetails : nil
        return runningTasks
            .sorted { $0.type.rank < $1.type.rank }
            .map { task in
                var progress = ItemProgress(
                    fraction: min(max(task.progress.percent / 100, 0), 1),
                    stage: task.type,
                    message: task.progress.message.trimmingCharacters(in: .whitespaces),
                    startedAt: task.startedDate,
                    bytesCopied: task.progress.bytesCopied,
                    totalBytes: task.progress.totalBytes
                )
                if task.type == .encoding, let encoding {
                    if let percent = encoding.percent, percent > 0, progress.fraction == 0 {
                        progress.fraction = min(max(percent / 100, 0), 1)
                    }
                    progress.etaSeconds = encoding.etaSeconds
                    progress.speed = encoding.averageSpeed
                    progress.currentFrame = encoding.currentFrame
                    progress.totalFrames = encoding.totalFrames
                }
                return progress
            }
    }
}
