import Foundation

/// `GET /api/logs`.
struct LogsResponse: Codable, Hashable, Sendable {
    var events: [LogEntry]
    /// Cursor to pass as `since` on the next request.
    var next: UInt64
}

struct LogEntry: Codable, Hashable, Sendable, Identifiable {
    var seq: UInt64
    var ts: String
    var level: String
    var msg: String
    var component: String?
    var stage: String?
    var itemID: Int64?
    var lane: String?
    var request: String?
    var fields: [String: String]?

    var id: UInt64 { seq }
    var timestamp: Date? { SpindleDate.parse(ts) }
    var levelValue: LogLevel { LogLevel(rawValue: level) ?? .unknown(level) }

    /// Fields as "key=value" pairs, message-like keys first, stable order.
    var fieldPairs: [(key: String, value: String)] {
        guard let fields, !fields.isEmpty else { return [] }
        let preferred = ["message", "error", "event_type", "episode_key", "stage", "path"]
        let ordered = preferred.filter { fields[$0] != nil } + fields.keys.filter { !preferred.contains($0) }.sorted()
        return ordered.map { ($0, fields[$0] ?? "") }
    }

    /// One-line rendering used by search and the compact row.
    var summary: String {
        var parts = [msg]
        if let stage, !stage.isEmpty { parts.append("stage=\(stage)") }
        parts += fieldPairs.map { "\($0.key)=\($0.value)" }
        return parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case seq, ts, level, msg, component, stage, lane, request, fields
        case itemID = "item_id"
    }
}

/// Spindle log levels, ordered. Unknown strings decode rather than fail.
enum LogLevel: Hashable, Sendable, Comparable {
    case debug, info, warn, error
    case unknown(String)

    var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        case .unknown: return -1
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

    static let filterable: [LogLevel] = [.debug, .info, .warn, .error]
}

extension LogLevel: RawRepresentable {
    init?(rawValue: String) {
        switch rawValue.uppercased() {
        case "DEBUG": self = .debug
        case "INFO": self = .info
        case "WARN", "WARNING": self = .warn
        case "ERROR": self = .error
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .unknown(let raw): return raw
        }
    }

    /// Query-parameter spelling.
    var queryValue: String { rawValue.lowercased() }
}
