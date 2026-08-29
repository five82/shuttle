import Foundation
import XCTest
@testable import shuttle

/// JSON captured from a live Spindle daemon. Re-capture when the API changes:
///   curl -H "Authorization: Bearer $TOKEN" $SPINDLE/api/status | python3 -m json.tool > shuttleTests/Fixtures/status.json
enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureAnchor.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture \(name).json")
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(name))
    }

    static func status() throws -> StatusResponse {
        try decode(StatusResponse.self, from: "status")
    }

    static func queue() throws -> [QueueItem] {
        struct Envelope: Decodable { var items: [QueueItem] }
        return try decode(Envelope.self, from: "queue").items
    }

    /// A failed item; the live capture had none.
    static let failedItemJSON = """
    {
      "id": 99,
      "discTitle": "BROKEN_DISC",
      "displayTitle": "Broken Disc (1999)",
      "stage": "failed",
      "inProgress": false,
      "failedAtStage": "encoding",
      "errorMessage": "reel: exit status 3",
      "createdAt": "2026-08-28 10:00:00",
      "updatedAt": "2026-08-28T11:00:00Z",
      "needsReview": false,
      "tasks": [
        {"type": "identification", "state": "done", "progress": {"percent": 0, "message": ""}},
        {"type": "ripping", "state": "done", "progress": {"percent": 100, "message": ""}},
        {"type": "encoding", "state": "failed", "attempts": 2, "error": "reel: exit status 3", "progress": {"percent": 40, "message": "Phase 1/1"}}
      ]
    }
    """

    static func failedItem() throws -> QueueItem {
        try JSONDecoder().decode(QueueItem.self, from: Data(failedItemJSON.utf8))
    }
}

private final class FixtureAnchor {}
