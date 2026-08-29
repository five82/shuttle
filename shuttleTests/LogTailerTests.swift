import XCTest
@testable import shuttle

@MainActor
final class LogTailerTests: XCTestCase {
    private func entry(_ seq: UInt64, level: String = "INFO", item: Int64? = nil) -> LogEntry {
        LogEntry(seq: seq, ts: "2026-08-28T12:00:00Z", level: level, msg: "m\(seq)", itemID: item, fields: nil)
    }

    private func makeAPI() throws -> MockSpindleAPI {
        MockSpindleAPI(status: try Fixtures.status(), queue: [])
    }

    func testInitialTailThenCursorCatchUp() async throws {
        let api = try makeAPI()
        api.logScript[nil] = LogsResponse(events: [entry(10), entry(11)], next: 12)
        api.logScript[12] = LogsResponse(events: [entry(12)], next: 13)
        api.logScript[13] = LogsResponse(events: [], next: 13)
        let tailer = LogTailer(clientProvider: { api }, sleeper: { _ in })

        await tailer.poll()
        XCTAssertEqual(tailer.entries.map(\.seq), [10, 11])
        XCTAssertEqual(tailer.next, 12)
        let first = try XCTUnwrap(api.logQueries.first)
        XCTAssertNil(first.since)
        XCTAssertTrue(first.tail)
        XCTAssertEqual(first.limit, LogTailer.initialWindow)
        XCTAssertEqual(first.minimumLevel, .info, "defaults to info to hide debug noise")

        await tailer.poll()
        XCTAssertEqual(tailer.entries.map(\.seq), [10, 11, 12])
        XCTAssertEqual(api.logQueries.last?.since, 12)
        XCTAssertFalse(api.logQueries.last!.tail)

        await tailer.poll()
        XCTAssertEqual(tailer.entries.count, 3, "empty catch-up adds nothing")
        XCTAssertEqual(tailer.next, 13)
        XCTAssertNil(tailer.lastError)
    }

    func testFilterChangesRestartFromTail() async throws {
        let api = try makeAPI()
        api.logScript[nil] = LogsResponse(events: [entry(5)], next: 6)
        let tailer = LogTailer(clientProvider: { api }, sleeper: { _ in })
        await tailer.poll()
        XCTAssertEqual(tailer.entries.count, 1)

        tailer.minimumLevel = .error
        XCTAssertEqual(tailer.entries, [], "level change clears the buffer")
        XCTAssertEqual(tailer.next, 0)
        await tailer.poll()
        XCTAssertEqual(api.logQueries.last?.minimumLevel, .error)
        XCTAssertTrue(api.logQueries.last!.tail)

        tailer.daemonOnly = true
        await tailer.poll()
        XCTAssertTrue(api.logQueries.last!.daemonOnly)

        tailer.itemID = 21
        await tailer.poll()
        XCTAssertEqual(api.logQueries.last?.itemID, 21)
    }

    func testBufferIsCappedAndDuplicatesDropped() async throws {
        let api = try makeAPI()
        api.logScript[nil] = LogsResponse(events: (1...UInt64(LogTailer.bufferLimit)).map { entry($0) }, next: UInt64(LogTailer.bufferLimit) + 1)
        let since = UInt64(LogTailer.bufferLimit) + 1
        api.logScript[since] = LogsResponse(events: [entry(since - 1), entry(since), entry(since + 1)], next: since + 2)
        let tailer = LogTailer(clientProvider: { api }, sleeper: { _ in })

        await tailer.poll()
        XCTAssertEqual(tailer.entries.count, LogTailer.bufferLimit)
        await tailer.poll()
        XCTAssertEqual(tailer.entries.count, LogTailer.bufferLimit, "capped")
        XCTAssertEqual(tailer.entries.last?.seq, since + 1)
        XCTAssertEqual(tailer.entries.first?.seq, 3, "oldest dropped, re-sent seq below the cursor ignored")
    }

    func testErrorsAreReportedAndBufferKept() async throws {
        let api = try makeAPI()
        api.logScript[nil] = LogsResponse(events: [entry(1)], next: 2)
        let tailer = LogTailer(clientProvider: { api }, sleeper: { _ in })
        await tailer.poll()

        let failing = LogTailer(clientProvider: { nil }, sleeper: { _ in })
        await failing.poll()
        XCTAssertTrue(failing.lastError?.contains("valid URL") == true)
        XCTAssertEqual(tailer.entries.count, 1)
    }

    func testStartAndStop() async throws {
        let api = try makeAPI()
        api.logScript[nil] = LogsResponse(events: [entry(1)], next: 2)
        let tailer = LogTailer(clientProvider: { api }, sleeper: { _ in })
        tailer.start()
        XCTAssertTrue(tailer.isRunning)
        try await Task.sleep(for: .milliseconds(30))
        tailer.stop()
        XCTAssertFalse(tailer.isRunning)
        XCTAssertGreaterThan(api.logQueries.count, 0)
        XCTAssertEqual(tailer.entries.map(\.seq), [1])
    }

    func testLogLevelAndQueryItems() {
        XCTAssertEqual(LogLevel(rawValue: "warning"), .warn)
        XCTAssertEqual(LogLevel(rawValue: "ERROR"), .error)
        XCTAssertEqual(LogLevel(rawValue: "trace"), .unknown("trace"))
        XCTAssertTrue(LogLevel.debug < LogLevel.error)
        XCTAssertTrue(LogLevel.unknown("x") < LogLevel.debug)

        let query = LogQuery(since: 42, limit: 10, tail: true, itemID: 7, minimumLevel: .warn, component: "ripper", daemonOnly: true)
        let items = Dictionary(uniqueKeysWithValues: query.queryItems.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items, ["since": "42", "limit": "10", "tail": "1", "item": "7", "level": "warn", "component": "ripper", "daemon_only": "1"])
        XCTAssertTrue(LogQuery().queryItems.isEmpty)
    }

    func testEntryFormatting() throws {
        let logs = try Fixtures.decode(LogsResponse.self, from: "logs")
        let first = try XCTUnwrap(logs.events.first)
        XCTAssertEqual(first.levelValue, .debug)
        XCTAssertEqual(first.fieldPairs.first?.key, "message", "message-like fields come first")
        XCTAssertTrue(first.summary.hasPrefix("reel verbose message=TQ final"))
        XCTAssertTrue(first.summary.contains("episode_key=main"))
    }
}
