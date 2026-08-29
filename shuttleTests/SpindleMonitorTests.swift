import XCTest
@testable import shuttle

/// A scripted SpindleAPI. Set the results before each refresh.
final class MockSpindleAPI: SpindleAPI, @unchecked Sendable {
    var statusResult: Result<StatusResponse, Error>
    var queueResult: Result<[QueueItem], Error>
    var statusCalls = 0
    var queueCalls = 0

    init(status: StatusResponse, queue: [QueueItem]) {
        statusResult = .success(status)
        queueResult = .success(queue)
    }

    func health() async throws {}

    func status() async throws -> StatusResponse {
        statusCalls += 1
        return try statusResult.get()
    }

    func queue() async throws -> [QueueItem] {
        queueCalls += 1
        return try queueResult.get()
    }

    func item(id: Int64) async throws -> QueueItem {
        guard let item = try queueResult.get().first(where: { $0.id == id }) else {
            throw SpindleClientError.httpStatus(404)
        }
        return item
    }

    func logs(since: UInt64?, limit: Int?, itemID: Int64?) async throws -> LogsResponse {
        LogsResponse(events: [], next: 0)
    }
}

@MainActor
final class SpindleMonitorTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeMonitor(_ api: MockSpindleAPI?) -> SpindleMonitor {
        let clockBox = ClockBox(date: clock)
        return SpindleMonitor(
            clientProvider: { api },
            pollInterval: 2,
            maxBackoff: 30,
            sleeper: { _ in },
            now: { clockBox.date }
        )
    }

    func testSuccessfulRefreshAppliesSnapshotAndDerivedState() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: try Fixtures.queue())
        let monitor = makeMonitor(api)

        let ok = await monitor.refresh()

        XCTAssertTrue(ok)
        XCTAssertTrue(monitor.connection.isConnected)
        XCTAssertEqual(monitor.consecutiveFailures, 0)
        XCTAssertEqual(monitor.items.count, 24)
        XCTAssertNotNil(monitor.lastRefresh)
        XCTAssertEqual(monitor.activeItems.map(\.id), [21])
        XCTAssertEqual(monitor.attentionItems.map(\.id), [19])
        XCTAssertEqual(monitor.attentionCount, 1)
        XCTAssertEqual(monitor.waitingItems.map(\.id), [22, 23, 24])
        XCTAssertEqual(monitor.recentlyCompleted.count, 5)
        XCTAssertEqual(monitor.recentlyCompleted.first?.id, 20)
        XCTAssertEqual(monitor.driveState, .available)
        XCTAssertEqual(monitor.resources.map(\.name), ["drive", "encode", "gpu"])
        XCTAssertEqual(monitor.resources.first { $0.name == "encode" }?.status.used, 1)
    }

    func testPartialFailureLeavesSnapshotUntouched() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: try Fixtures.queue())
        let monitor = makeMonitor(api)
        await monitor.refresh()
        let firstRefresh = monitor.lastRefresh

        api.queueResult = .failure(SpindleClientError.unreachable("timed out"))
        let ok = await monitor.refresh()

        XCTAssertFalse(ok)
        XCTAssertEqual(monitor.items.count, 24, "stale data must remain visible")
        XCTAssertNotNil(monitor.status)
        XCTAssertEqual(monitor.lastRefresh, firstRefresh)
        XCTAssertEqual(monitor.consecutiveFailures, 1)
        guard case .disconnected(let error, let since, let nextRetry) = monitor.connection else {
            return XCTFail("expected disconnected, got \(monitor.connection)")
        }
        XCTAssertTrue(error.contains("unreachable"))
        XCTAssertEqual(since, clock)
        XCTAssertEqual(nextRetry.timeIntervalSince(clock), 4, accuracy: 0.001)
    }

    func testRepeatedFailuresBackOffAndKeepOutageStart() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: try Fixtures.queue())
        api.statusResult = .failure(SpindleClientError.unreachable("refused"))
        let monitor = makeMonitor(api)

        for _ in 0..<5 { await monitor.refresh() }

        XCTAssertEqual(monitor.consecutiveFailures, 5)
        guard case .disconnected(_, let since, let nextRetry) = monitor.connection else {
            return XCTFail("expected disconnected")
        }
        XCTAssertEqual(since, clock)
        XCTAssertEqual(nextRetry.timeIntervalSince(clock), 30, accuracy: 0.001, "capped at maxBackoff")

        api.statusResult = .success(try Fixtures.status())
        let ok = await monitor.refresh()
        XCTAssertTrue(ok)
        XCTAssertEqual(monitor.consecutiveFailures, 0)
        XCTAssertTrue(monitor.connection.isConnected)
    }

    func testBackoffSchedule() {
        XCTAssertEqual(SpindleMonitor.backoff(failures: 0, base: 2, max: 30), 2)
        XCTAssertEqual(SpindleMonitor.backoff(failures: 1, base: 2, max: 30), 4)
        XCTAssertEqual(SpindleMonitor.backoff(failures: 3, base: 2, max: 30), 16)
        XCTAssertEqual(SpindleMonitor.backoff(failures: 4, base: 2, max: 30), 30)
        XCTAssertEqual(SpindleMonitor.backoff(failures: 100, base: 2, max: 30), 30)
    }

    func testUnauthorizedIsReportedDistinctly() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: [])
        api.statusResult = .failure(SpindleClientError.unauthorized)
        let monitor = makeMonitor(api)

        await monitor.refresh()

        XCTAssertEqual(monitor.connection.errorMessage, "Spindle rejected the API token.")
    }

    func testInvalidSettingsFailWithoutAClient() async {
        let monitor = makeMonitor(nil)
        let ok = await monitor.refresh()
        XCTAssertFalse(ok)
        XCTAssertTrue(monitor.connection.errorMessage?.contains("not a valid URL") == true)
    }

    func testSelectionIsIDStickyAndClearsWhenItemVanishes() async throws {
        let items = try Fixtures.queue()
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: items)
        let monitor = makeMonitor(api)
        await monitor.refresh()

        monitor.selectedItemID = 21
        api.queueResult = .success(items.reversed())
        await monitor.refresh()
        XCTAssertEqual(monitor.selectedItemID, 21, "reordering must not change selection")

        api.queueResult = .success(items.filter { $0.id != 21 })
        await monitor.refresh()
        XCTAssertNil(monitor.selectedItemID)
    }

    func testDriveStateFromStatus() throws {
        var status = try Fixtures.status()
        XCTAssertEqual(SpindleMonitor.driveState(from: status), .available)

        let holder = ResourceHolder(itemId: 7, task: .ripping)
        status.scheduler?.resources["drive"] = ResourceStatus(capacity: 1, used: 1, holders: [holder])
        XCTAssertEqual(SpindleMonitor.driveState(from: status), .busy([holder]))

        status.disc = DiscStatus(paused: true)
        XCTAssertEqual(SpindleMonitor.driveState(from: status), .busy([holder]), "busy outranks paused")

        status.scheduler?.resources["drive"] = ResourceStatus(capacity: 1, used: 0, holders: [])
        XCTAssertEqual(SpindleMonitor.driveState(from: status), .paused)

        status.scheduler = nil
        XCTAssertEqual(SpindleMonitor.driveState(from: status), .unknown)
    }

    func testFailedItemsSortAheadOfReview() async throws {
        var items = try Fixtures.queue()
        items.append(try Fixtures.failedItem())
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: items)
        let monitor = makeMonitor(api)

        await monitor.refresh()

        XCTAssertEqual(monitor.attentionItems.map(\.id), [99, 19])
    }

    func testEventsFireOnlyAfterFirstSnapshot() async throws {
        var items = try Fixtures.queue()
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: items)
        let monitor = makeMonitor(api)
        var received: [[MonitorEvent]] = []
        monitor.onEvents = { received.append($0) }
        var snapshots = 0
        monitor.onSnapshot = { snapshots += 1 }

        await monitor.refresh()
        XCTAssertEqual(received, [], "first poll seeds, never notifies")
        XCTAssertEqual(snapshots, 1)

        let index = try XCTUnwrap(items.firstIndex { $0.id == 21 })
        items[index].stage = .completed
        items[index].inProgress = false
        items[index].tasks = nil
        api.queueResult = .success(items)
        await monitor.refresh()

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.map(\.kind), [.completed])
        XCTAssertEqual(received.first?.first?.item?.id, 21)
        XCTAssertEqual(monitor.lastEvents.count, 1)
        XCTAssertEqual(snapshots, 2)

        api.queueResult = .failure(SpindleClientError.unreachable("down"))
        await monitor.refresh()
        XCTAssertEqual(snapshots, 2, "failed polls don't report snapshots")
    }

    func testStartPollsAndStopCancels() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: try Fixtures.queue())
        let monitor = makeMonitor(api)

        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        // The mock sleeper returns immediately, so the loop spins; let it run a little.
        try await Task.sleep(for: .milliseconds(50))
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertGreaterThan(api.statusCalls, 0)
        XCTAssertTrue(monitor.connection.isConnected)
    }
}

private final class ClockBox: @unchecked Sendable {
    var date: Date
    init(date: Date) { self.date = date }
}
