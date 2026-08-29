import Foundation

/// One queue item as returned by `GET /api/queue` and `GET /api/queue/{id}`.
/// `ripSpec` is present only on single-item GETs.
struct QueueItem: Codable, Identifiable, Hashable, Sendable {
    var id: Int64
    var discTitle: String
    var displayTitle: String
    var discNumber: Int?
    var stage: Stage
    var inProgress: Bool
    var failedAtStage: Stage?
    var errorMessage: String?
    var createdAt: String
    var updatedAt: String
    var discFingerprint: String?
    var needsReview: Bool
    var userStopped: Bool?
    var reviewReasons: [String]?
    var metadata: JSONValue?
    var ripSpec: JSONValue?
    var tasks: [PipelineTask]?
    var encoding: JSONValue?
    var episodes: [Episode]?
    var episodeTotals: EpisodeTotals?
    var episodeIdentifiedCount: Int?
    var subtitleGeneration: SubtitleGeneration?
    var primaryAudioDescription: String?
    var commentaryCount: Int?
    var contentId: ContentIdentification?
    var source: SourceTitle?
}

struct PipelineTask: Codable, Hashable, Sendable, Identifiable {
    var type: Stage
    var state: TaskState
    var attempts: Int?
    var error: String?
    var dependsOn: [String]?
    var startedAt: String?
    var finishedAt: String?
    var progress: TaskProgress
    var activeAssetKey: String?

    var id: String { type.rawValue }
}

struct TaskProgress: Codable, Hashable, Sendable {
    var percent: Double
    var message: String
    var bytesCopied: Int64?
    var totalBytes: Int64?
}

struct Episode: Codable, Hashable, Sendable, Identifiable {
    var key: String
    var season: Int
    var episode: Int
    var episodeEnd: Int?
    var title: String?
    var stage: String
    var status: String?
    var errorMessage: String?
    var active: Bool?
    var runtimeSeconds: Int?
    var sourceTitleId: Int?
    var sourceTitle: String?
    var outputBasename: String?
    var rippedPath: String?
    var encodedPath: String?
    var subtitledPath: String?
    var finalPath: String?
    var subtitleSource: String?
    var subtitleLanguage: String?
    var subtitleValidation: String?
    var subtitleReviewIssues: [String]?
    var subtitleSevereIssues: [String]?
    var commentaryTracks: Int?
    var excludedTracks: Int?
    var matchScore: Double?
    var matchConfidence: Double?
    var matchedEpisode: Int?
    var matchedEpisodeEnd: Int?
    var needsReview: Bool?
    var reviewReason: String?

    var id: String { key }
}

struct EpisodeTotals: Codable, Hashable, Sendable {
    var planned: Int
    var ripped: Int
    var encoded: Int
    var final: Int
}

struct SubtitleGeneration: Codable, Hashable, Sendable {
    var opensubtitles: Int
    var skipped: Int
}

struct ContentIdentification: Codable, Hashable, Sendable {
    var method: String?
    var referenceSource: String?
    var referenceEpisodes: Int?
    var transcribedEpisodes: Int?
    var matchedEpisodes: Int?
    var unresolvedEpisodes: Int?
    var lowConfidenceCount: Int?
    var reviewThreshold: Double?
    var sequenceContiguous: Bool?
    var episodesSynchronized: Bool?
    var completed: Bool?
}

struct SourceTitle: Codable, Hashable, Sendable {
    var titleId: Int
    var name: String?
    var durationSeconds: Int?
}

// MARK: - Derived values

extension QueueItem {
    var createdDate: Date { SpindleDate.parse(createdAt) ?? .distantPast }
    var updatedDate: Date { SpindleDate.parse(updatedAt) ?? .distantPast }

    var taskList: [PipelineTask] { tasks ?? [] }
    var runningTasks: [PipelineTask] { taskList.filter { $0.state == .running } }

    var hasFailed: Bool { stage == .failed }
    var isCompleted: Bool { stage == .completed }
    var isActive: Bool { inProgress || !runningTasks.isEmpty }
    var isWaiting: Bool { !isActive && !stage.isTerminal }
    var needsAttention: Bool { needsReview || hasFailed }

    /// The single line an operator needs to know why this item needs them.
    var attentionReason: String? {
        if let task = taskList.first(where: { $0.state == .failed }) {
            let error = task.error?.trimmingCharacters(in: .whitespaces) ?? ""
            return error.isEmpty ? "\(task.type.displayName) failed" : "\(task.type.displayName) failed: \(error)"
        }
        if needsReview, let reasons = reviewReasons, !reasons.isEmpty {
            return reasons.joined(separator: "; ")
        }
        if let message = errorMessage?.trimmingCharacters(in: .whitespaces), !message.isEmpty {
            if let at = failedAtStage { return "\(at.displayName) failed: \(message)" }
            return message
        }
        if let at = failedAtStage { return "\(at.displayName) failed" }
        if hasFailed { return "Failed" }
        if needsReview { return "Needs review" }
        return nil
    }

    /// Progress of the furthest-along running task, 0...1.
    var progressFraction: Double {
        let percent = runningTasks.map(\.progress.percent).max() ?? 0
        return min(max(percent / 100, 0), 1)
    }

    /// "Encoding · Phase 1/1 - Encoding foo.mkv", or the stage name when idle.
    var activityDescription: String {
        let running = runningTasks
        guard !running.isEmpty else { return stage.displayName }
        return running.map { task in
            let message = task.progress.message.trimmingCharacters(in: .whitespaces)
            return message.isEmpty ? task.type.displayName : "\(task.type.displayName) · \(message)"
        }.joined(separator: "  ·  ")
    }

    /// Default queue order: failed, review, active, waiting, completed.
    var priorityRank: Int {
        if hasFailed { return 0 }
        if needsReview { return 1 }
        if isActive { return 2 }
        if isWaiting { return 3 }
        return 4
    }

    var stageSortKey: String { stage.displayName }
}

extension PipelineTask {
    var startedDate: Date? { startedAt.flatMap(SpindleDate.parse) }
    var finishedDate: Date? { finishedAt.flatMap(SpindleDate.parse) }
}
