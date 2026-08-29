import Foundation

/// Why a queued item is not running right now, derived from the daemon's
/// pipeline template (`dependsOn`, `claims`), the item's own task states,
/// and scheduler occupancy. Answers "why isn't this moving?" without the
/// operator reading the DAG themselves.
enum WaitReason: Equatable, Sendable {
    /// The next task's dependency has not finished yet.
    case dependency(next: Stage, on: Stage)
    /// The next task is ready but its resource is fully in use.
    case resource(next: Stage, name: String, holders: [ResourceHolder])
    /// The next task is ready and nothing blocks it; it should dispatch soon.
    case ready(next: Stage)
    /// No pending task with a known cause; fall back to the item's stage.
    case queued(Stage)

    var next: Stage {
        switch self {
        case .dependency(let next, _), .resource(let next, _, _), .ready(let next), .queued(let next): return next
        }
    }

    /// One phrase for rows: "after Ripping", "GPU busy", "next up".
    var short: String {
        switch self {
        case .dependency(_, let on): return "after \(on.displayName)"
        case .resource(_, let name, _): return "\(Format.resource(name)) busy"
        case .ready: return "next up"
        case .queued: return "queued"
        }
    }

    /// A sentence for tooltips and the inspector.
    var detail: String {
        switch self {
        case .dependency(let next, let on):
            return "\(next.displayName) starts after \(on.displayName) finishes."
        case .resource(let next, let name, let holders):
            let who = holders.map { "#\($0.itemId)" }.joined(separator: ", ")
            let resource = Format.resource(name)
            return who.isEmpty
                ? "\(next.displayName) is ready but the \(resource) is in use."
                : "\(next.displayName) is ready but the \(resource) is in use by \(who)."
        case .ready(let next):
            return "\(next.displayName) is ready and should start on the next scheduler pass."
        case .queued(let stage):
            return "Queued for \(stage.displayName)."
        }
    }

    static func derive(
        for item: QueueItem,
        pipeline: [PipelineStageInfo],
        resources: [String: ResourceStatus]
    ) -> WaitReason {
        let template = Dictionary(pipeline.map { ($0.stage, $0) }, uniquingKeysWith: { first, _ in first })
        let tasks = Dictionary(item.taskList.map { ($0.type, $0) }, uniquingKeysWith: { first, _ in first })
        let pending = item.taskList.filter { $0.state == .pending }
        guard !pending.isEmpty else { return .queued(item.stage) }

        func dependencies(of task: PipelineTask) -> [Stage] {
            let names = task.dependsOn ?? template[task.type]?.dependsOn ?? []
            return names.compactMap(Stage.init(rawValue:))
        }
        func unmet(_ task: PipelineTask) -> [Stage] {
            dependencies(of: task).filter { tasks[$0]?.state != .done }
        }

        // The item's own stage first, so "Queued · Encoding" explains encoding.
        let ordered = pending.sorted { a, b in
            if a.type == item.stage { return true }
            if b.type == item.stage { return false }
            return a.type.rank < b.type.rank
        }

        let ready = ordered.filter { unmet($0).isEmpty }
        if !ready.isEmpty {
            var blocked: WaitReason?
            for task in ready {
                let claims = template[task.type]?.claims ?? []
                let full = claims.first { name in
                    guard let resource = resources[name] else { return false }
                    return resource.used >= resource.capacity
                }
                if let full {
                    if blocked == nil { blocked = .resource(next: task.type, name: full, holders: resources[full]?.holders ?? []) }
                } else {
                    return .ready(next: task.type)
                }
            }
            if let blocked { return blocked }
        }

        if let task = ordered.first, let on = unmet(task).first {
            return .dependency(next: task.type, on: on)
        }
        return .queued(item.stage)
    }
}
