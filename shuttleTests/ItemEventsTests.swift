import XCTest
@testable import shuttle

@MainActor
final class ItemEventsTests: XCTestCase {
    private func batch(_ json: String) throws -> ItemEventBatch {
        try JSONDecoder().decode(ItemEventBatch.self, from: Data(json.utf8))
    }

    func testDecodeOptionalFieldsUnknownStageAndPresentation() throws {
        let page = try batch(#"{"events":[{"id":1,"itemId":21,"time":"2026-09-27T18:00:00Z","type":"stage_start","stage":"encoding"},{"id":2,"itemId":21,"time":"2026-09-27T18:00:02.123Z","type":"encoding_substage","stage":"new_stage","episodeKey":"e01","substage":"chunking","message":"segment done","percent":25.5,"durationSeconds":62}],"next":2}"#)
        XCTAssertEqual(page.events.count, 2)
        XCTAssertEqual(page.events[0].label, "Worker reserved (may wait for input)")
        XCTAssertNil(ItemEventsView.detail(page.events[0]))
        XCTAssertEqual(page.events[1].stage, .unknown("new_stage"))
        XCTAssertEqual(page.events[1].label, "Chunking")
        XCTAssertNotNil(page.events[1].timestamp)
        XCTAssertEqual(ItemEventsView.detail(page.events[1]), "chunking · e01 · segment done · 25.5% · 1m")
    }

    func testEncoderReservationAndOutcomesRemainVisible() throws {
        let page = try batch(#"{"events":[{"id":1,"itemId":21,"time":"2026-09-27T18:00:00Z","type":"stage_start","stage":"encoding"},{"id":2,"itemId":21,"time":"2026-09-27T18:00:01Z","type":"stage_start","stage":"ripping"},{"id":3,"itemId":21,"time":"2026-09-27T18:00:02Z","type":"encoding_substage","stage":"encoding","substage":"chunking"},{"id":4,"itemId":21,"time":"2026-09-27T18:00:03Z","type":"stage_complete","stage":"encoding"}],"next":4}"#)
        XCTAssertEqual(ItemEventsView.visibleEvents(Array(page.events.prefix(1))).count, 1)
        XCTAssertEqual(ItemEventsView.visibleEvents(page.events).map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(page.events.count, 4, "presentation must not change journal data or cursor")
    }

    func testExclusiveCursorCatchesUpAcrossPagesAndRetainsRowsOnError() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: [])
        let first = try batch(#"{"events":[{"id":1,"itemId":21,"time":"2026-09-27T18:00:00Z","type":"stage_start","stage":"encoding"}],"next":1}"#)
        let second = try batch(#"{"events":[{"id":1,"itemId":21,"time":"2026-09-27T18:00:00Z","type":"stage_start","stage":"encoding"},{"id":2,"itemId":21,"time":"2026-09-27T18:00:01Z","type":"stage_complete","stage":"encoding"}],"next":2}"#)
        api.eventScript[0] = first
        api.eventScript[1] = second
        let tailer = ItemEventTailer(itemID: 21, clientProvider: { api })
        await tailer.poll()
        XCTAssertEqual(tailer.events.map(\.id), [1])
        XCTAssertEqual(tailer.next, 1)
        await tailer.poll()
        XCTAssertEqual(tailer.events.map(\.id), [1, 2], "ignore duplicate or overlapping responses")
        XCTAssertEqual(api.eventRequests.map { $0.1 }, [0, 1])
        api.eventError = SpindleClientError.unreachable("offline")
        await tailer.poll()
        XCTAssertEqual(tailer.next, 2)
        XCTAssertEqual(tailer.events.count, 2)
        XCTAssertNotNil(tailer.lastError)
        api.eventError = nil
        await tailer.poll()
        XCTAssertNil(tailer.lastError)
        XCTAssertEqual(api.eventRequests.last?.1, 2)
    }

    func testMissingClientAndItemIsolation() async throws {
        let missing = ItemEventTailer(itemID: 21, clientProvider: { nil })
        await missing.poll()
        XCTAssertNotNil(missing.lastError)
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: [])
        api.eventScript[0] = try batch(#"{"events":[{"id":1,"itemId":22,"time":"2026-09-27T18:00:00Z","type":"stage_start","stage":"encoding"}],"next":1}"#)
        let tailer = ItemEventTailer(itemID: 21, clientProvider: { api })
        await tailer.poll()
        XCTAssertTrue(tailer.events.isEmpty)
        XCTAssertEqual(tailer.next, 1)
        let other = ItemEventTailer(itemID: 22, clientProvider: { api })
        await other.poll()
        XCTAssertEqual(api.eventRequests.last?.0, 22)
        XCTAssertEqual(api.eventRequests.last?.1, 0, "selection must start a fresh journal")
        XCTAssertEqual(other.events.map(\.id), [1])
    }
}
