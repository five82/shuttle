import XCTest
@testable import shuttle

final class DecodingTests: XCTestCase {
    func testStatusDecodes() throws {
        let status = try Fixtures.status()
        XCTAssertTrue(status.running)
        XCTAssertFalse(status.isDraining)
        XCTAssertEqual(status.pipelineStages.count, 8)
        XCTAssertEqual(status.pipelineStages.first?.stage, .identification)
        XCTAssertEqual(status.pipelineStages.first?.claims, ["drive"])
        XCTAssertEqual(status.workflow.queueStats["completed"], 20)
        XCTAssertFalse(status.dependencies.isEmpty)

        let drive = try XCTUnwrap(status.scheduler?.resources["drive"])
        XCTAssertEqual(drive.capacity, 1)
        XCTAssertEqual(drive.used, 0)

        let encode = try XCTUnwrap(status.scheduler?.resources["encode"])
        XCTAssertEqual(encode.holders.first?.itemId, 21)
        XCTAssertEqual(encode.holders.first?.task, .encoding)
        XCTAssertEqual(status.disc?.paused, false)
    }

    func testQueueDecodes() throws {
        let items = try Fixtures.queue()
        XCTAssertEqual(items.count, 24)

        let active = try XCTUnwrap(items.first { $0.id == 21 })
        XCTAssertEqual(active.stage, .encoding)
        XCTAssertTrue(active.inProgress)
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.runningTasks.map(\.type), [.encoding])
        XCTAssertEqual(active.taskList.count, 8)
        XCTAssertEqual(active.activityDescription, "Encoding · Phase 1/1 - Encoding The Wolf of Wall Street_t00.mkv")
        XCTAssertEqual(active.priorityRank, 2)

        let ripping = try XCTUnwrap(active.taskList.first { $0.type == .ripping })
        XCTAssertEqual(ripping.state, .done)
        XCTAssertEqual(ripping.progress.totalBytes, 85_082_276_600)
        XCTAssertEqual(ripping.dependsOn, ["identification"])
        XCTAssertNotNil(ripping.startedDate)

        XCTAssertEqual(active.source?.durationSeconds, 10793)
        XCTAssertEqual(active.metadata?["title"]?.stringValue, "The Wolf of Wall Street")
        XCTAssertEqual(active.metadata?["movie"]?.boolValue, true)
        XCTAssertEqual(active.encoding?["encoder"]?.stringValue, "SVT-AV1")
        XCTAssertEqual(active.encoding?["original_size"]?.intValue, 85_082_276_600)
        XCTAssertNil(active.ripSpec, "list endpoint must not include the rip spec")

        let review = try XCTUnwrap(items.first { $0.id == 19 })
        XCTAssertTrue(review.needsReview)
        XCTAssertTrue(review.needsAttention)
        XCTAssertEqual(review.priorityRank, 1)
        XCTAssertEqual(review.reviewReasons?.count, 1)
        XCTAssertTrue(review.attentionReason?.hasPrefix("final_validation") == true)

        let waiting = try XCTUnwrap(items.first { $0.id == 22 })
        XCTAssertTrue(waiting.isWaiting)
        XCTAssertFalse(waiting.isActive)
        XCTAssertEqual(waiting.priorityRank, 3)

        let completed = try XCTUnwrap(items.first { $0.id == 1 })
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.priorityRank, 4)
        XCTAssertNotEqual(completed.createdDate, .distantPast)
    }

    func testItemDetailIncludesRipSpec() throws {
        struct Envelope: Decodable { var item: QueueItem }
        let item = try Fixtures.decode(Envelope.self, from: "item").item
        XCTAssertEqual(item.id, 21)
        XCTAssertNotNil(item.ripSpec)
    }

    func testLogsDecode() throws {
        let logs = try Fixtures.decode(LogsResponse.self, from: "logs")
        XCTAssertEqual(logs.next, 255)
        XCTAssertEqual(logs.events.count, 20)
        let first = try XCTUnwrap(logs.events.first)
        XCTAssertEqual(first.seq, 235)
        XCTAssertEqual(first.itemID, 16)
        XCTAssertEqual(first.level, "DEBUG")
        XCTAssertNotNil(first.timestamp)
        XCTAssertEqual(first.fields?["episode_key"], "main")
    }

    func testFailedItem() throws {
        let item = try Fixtures.failedItem()
        XCTAssertTrue(item.hasFailed)
        XCTAssertTrue(item.needsAttention)
        XCTAssertEqual(item.failedAtStage, .encoding)
        XCTAssertEqual(item.attentionReason, "Failed at encoding: reel: exit status 3")
        XCTAssertEqual(item.priorityRank, 0)
        XCTAssertFalse(item.isActive)
        XCTAssertEqual(item.taskList.last?.state, .failed)
        XCTAssertEqual(item.taskList.last?.attempts, 2)
    }

    func testUnknownStageAndStateDecodeInsteadOfFailing() throws {
        let json = """
        {"id": 5, "discTitle": "x", "displayTitle": "x", "stage": "frobnicate", "inProgress": false,
         "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z", "needsReview": false,
         "tasks": [{"type": "frobnicate", "state": "queued", "progress": {"percent": 0, "message": ""}}]}
        """
        let item = try JSONDecoder().decode(QueueItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.stage, .unknown("frobnicate"))
        XCTAssertEqual(item.stage.displayName, "frobnicate")
        XCTAssertFalse(item.stage.isTerminal)
        XCTAssertEqual(item.taskList.first?.state, .unknown("queued"))

        let encoded = try JSONEncoder().encode(item.stage)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"frobnicate\"")
    }

    func testStageRawValuesRoundTrip() {
        let stages: [Stage] = [.identification, .ripping, .episodeIdentification, .encoding, .analysis, .subtitling, .apply, .organizing, .completed, .failed]
        for stage in stages {
            XCTAssertEqual(Stage(rawValue: stage.rawValue), stage)
        }
        XCTAssertEqual(Stage.episodeIdentification.rawValue, "episode_identification")
    }

    func testSpindleDateFormats() throws {
        let z = try XCTUnwrap(SpindleDate.parse("2026-08-28T15:44:29Z"))
        XCTAssertEqual(z.timeIntervalSince1970, 1_787_931_869, accuracy: 0.5)

        let fractional = try XCTUnwrap(SpindleDate.parse("2026-08-28T11:29:09.642764699-04:00"))
        XCTAssertEqual(fractional.timeIntervalSince1970, 1_787_930_949.64, accuracy: 0.01)

        let sqlite = try XCTUnwrap(SpindleDate.parse("2026-08-28 15:44:29"))
        XCTAssertEqual(sqlite, z)

        XCTAssertNil(SpindleDate.parse(""))
        XCTAssertNil(SpindleDate.parse("yesterday"))
    }

    func testJSONValueAccessors() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a": 1.5, "b": "s", "c": true, "d": null, "e": [1, 2]}"#.utf8))
        XCTAssertEqual(value["a"]?.doubleValue, 1.5)
        XCTAssertEqual(value["a"]?.intValue, 1)
        XCTAssertEqual(value["b"]?.stringValue, "s")
        XCTAssertEqual(value["c"]?.boolValue, true)
        XCTAssertEqual(value["d"], .null)
        XCTAssertEqual(value["e"], .array([.number(1), .number(2)]))
        XCTAssertNil(value["missing"])
        XCTAssertNil(value["b"]?.doubleValue)
    }
}
