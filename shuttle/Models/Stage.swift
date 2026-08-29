import Foundation

/// A queue item stage or task type. Spindle uses the same names for both.
/// Unknown names decode rather than failing the poll, so a new Spindle stage
/// shows up as its raw name instead of breaking the app.
enum Stage: Hashable, Sendable {
    case identification
    case ripping
    case episodeIdentification
    case encoding
    case analysis
    case subtitling
    case apply
    case organizing
    case completed
    case failed
    case unknown(String)

    var isTerminal: Bool {
        self == .completed || self == .failed
    }

    var displayName: String {
        switch self {
        case .identification: return "Identification"
        case .ripping: return "Ripping"
        case .episodeIdentification: return "Episode ID"
        case .encoding: return "Encoding"
        case .analysis: return "Analysis"
        case .subtitling: return "Subtitling"
        case .apply: return "Apply"
        case .organizing: return "Organizing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .unknown(let raw): return raw
        }
    }
}

extension Stage: RawRepresentable, Codable {
    init?(rawValue: String) {
        switch rawValue {
        case "identification": self = .identification
        case "ripping": self = .ripping
        case "episode_identification": self = .episodeIdentification
        case "encoding": self = .encoding
        case "analysis": self = .analysis
        case "subtitling": self = .subtitling
        case "apply": self = .apply
        case "organizing": self = .organizing
        case "completed": self = .completed
        case "failed": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .identification: return "identification"
        case .ripping: return "ripping"
        case .episodeIdentification: return "episode_identification"
        case .encoding: return "encoding"
        case .analysis: return "analysis"
        case .subtitling: return "subtitling"
        case .apply: return "apply"
        case .organizing: return "organizing"
        case .completed: return "completed"
        case .failed: return "failed"
        case .unknown(let raw): return raw
        }
    }
}

/// Scheduler state of one task.
enum TaskState: Hashable, Sendable {
    case pending
    case running
    case done
    case failed
    case unknown(String)
}

extension TaskState: RawRepresentable, Codable {
    init?(rawValue: String) {
        switch rawValue {
        case "pending": self = .pending
        case "running": self = .running
        case "done": self = .done
        case "failed": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .pending: return "pending"
        case .running: return "running"
        case .done: return "done"
        case .failed: return "failed"
        case .unknown(let raw): return raw
        }
    }
}
