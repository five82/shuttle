import Foundation

/// One queue item as returned by `GET /api/queue` and `GET /api/queue/{id}`.
/// `ripSpec` is present only on single-item GETs. `stage` is the scheduler's
/// coarse position and lags during overlap windows; `tasks` carry the live
/// truth. A scheduled encoding worker is idle until it has an active asset.
struct QueueItem: Codable, Identifiable, Hashable, Sendable {
    var id: Int64
    var discTitle: String
    var displayTitle: String
    var discNumber: Int?
    var stage: Stage
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
    var id: Int64? = nil
    var activities: [TaskActivity]? = nil
    var encoding: JSONValue? = nil
    var attempts: Int?
    var error: String?
    var dependsOn: [String]?
    var startedAt: String?
    var finishedAt: String?
    var progress: TaskProgress
    var activeAssetKey: String?

    /// Encoding reserves a worker before a ripped asset is available and
    /// between episodes. Other running tasks begin work immediately.
    var isWorking: Bool {
        guard state == .running else { return false }
        if let activities, !activities.isEmpty { return activities.contains { $0.state == "running" } }
        return type != .encoding || !(activeAssetKey ?? "").isEmpty
    }

    var waitingMessage: String? {
        activities?.first { $0.state == "waiting" && $0.message?.isEmpty == false }?.message
    }
}

/// A bounded, task-scoped lane. A total of zero means the operation has no
/// measured denominator; it must not be presented as a percentage.
struct TaskActivity: Codable, Hashable, Sendable {
    var id: String
    var operation: String
    var assetKey: String?
    var state: String
    var message: String?
    var startedAt: String?
    var updatedAt: String?
    var advancedAt: String?
    var completed: Int64?
    var total: Int64?
    var unit: String?

    var measurement: String? {
        guard let total, total > 0, let completed else { return nil }
        return "\(completed.formatted())/\(total.formatted())\(unit.map { " \($0)" } ?? "")"
    }

    var summary: String {
        [message?.trimmingCharacters(in: .whitespaces), measurement]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
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
    var finalSizeBytes: Int64?
    var finalRoute: String?
    var finalValidation: JSONValue?
    var encodeStats: JSONValue?
    var audioAnalysis: JSONValue?
    var subtitleSkipReason: String?
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
    var workingTasks: [PipelineTask] { taskList.filter(\.isWorking) }

    var hasFailed: Bool { stage == .failed }
    var isCompleted: Bool { stage == .completed }
    var isActive: Bool { !workingTasks.isEmpty }
    var isWaiting: Bool { !isActive && !stage.isTerminal }
    var explicitWait: String? { taskList.compactMap(\.waitingMessage).first }
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

    /// Sort value for the queue table; only measured operations contribute.
    var progressFraction: Double {
        workingTasks.map { task in
            if task.id != nil || !(task.activities ?? []).isEmpty {
                guard let activity = task.activities?.first(where: { $0.state == "running" && ($0.total ?? 0) > 0 }),
                      let total = activity.total, total > 0 else { return 0 }
                return min(max(Double(activity.completed ?? 0) / Double(total), 0), 1)
            }
            return min(max(task.progress.percent / 100, 0), 1)
        }.max() ?? 0
    }

    /// "Encoding · Phase 1/1 - Encoding foo.mkv", or the stage name when idle.
    var activityDescription: String {
        let running = workingTasks
        guard !running.isEmpty else { return stage.displayName }
        return running.map { task in
            let activities = task.activities?.filter { $0.state == "running" } ?? []
            let message = activities.isEmpty ? task.progress.message.trimmingCharacters(in: .whitespaces)
                : activities.map(\.summary).filter { !$0.isEmpty }.joined(separator: " · ")
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

    /// Pipeline position for the Queue table's Stage column.
    var stageRank: Int { stage.rank }

    /// "Movie" / "TV" for chips.
    var mediaTypeLabel: String? {
        switch mediaType {
        case "tv": return "TV"
        case "movie": return "Movie"
        case let other?: return other.capitalized
        case nil: return nil
        }
    }

    /// Text the queue filter matches against: title, disc title, stage, ID,
    /// and the attention reason so "audio stream" finds the failing item.
    var searchableText: String {
        [displayTitle, discTitle, stage.displayName, "#\(id)", attentionReason ?? ""]
            .joined(separator: " ")
            .lowercased()
    }
}

extension PipelineTask {
    var startedDate: Date? { startedAt.flatMap(SpindleDate.parse) }
    var finishedDate: Date? { finishedAt.flatMap(SpindleDate.parse) }
}
