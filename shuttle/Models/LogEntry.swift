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

    enum CodingKeys: String, CodingKey {
        case seq, ts, level, msg, component, stage, lane, request, fields
        case itemID = "item_id"
    }
}
