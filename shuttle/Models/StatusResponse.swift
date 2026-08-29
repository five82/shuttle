import Foundation

/// `GET /api/status`.
struct StatusResponse: Codable, Hashable, Sendable {
    var running: Bool
    var draining: Bool?
    var pid: Int
    var queueDbPath: String
    var lockFilePath: String
    var workflow: WorkflowStatus
    var dependencies: [DependencyStatus]
    var pipeline: [PipelineStageInfo]?
    var scheduler: SchedulerStatus?
    var disc: DiscStatus?

    var pipelineStages: [PipelineStageInfo] { pipeline ?? [] }
    var isDraining: Bool { draining ?? false }
}

struct WorkflowStatus: Codable, Hashable, Sendable {
    var running: Bool
    var queueStats: [String: Int]
    var lastError: String
}

struct DependencyStatus: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var command: String
    var description: String
    var optional: Bool
    var available: Bool
    var detail: String?

    var id: String { name }
}

/// One stage of the daemon's pipeline template, so the DAG is rendered from
/// data rather than hardcoded.
struct PipelineStageInfo: Codable, Hashable, Sendable, Identifiable {
    var stage: Stage
    var dependsOn: [String]?
    var claims: [String]?

    var id: String { stage.rawValue }
}

struct SchedulerStatus: Codable, Hashable, Sendable {
    var resources: [String: ResourceStatus]
}

struct ResourceStatus: Codable, Hashable, Sendable {
    var capacity: Int
    var used: Int
    var holders: [ResourceHolder]
}

struct ResourceHolder: Codable, Hashable, Sendable {
    var itemId: Int64
    var task: Stage
}

struct DiscStatus: Codable, Hashable, Sendable {
    var paused: Bool
}
