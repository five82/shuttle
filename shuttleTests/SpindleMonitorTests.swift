import XCTest
@testable import shuttle

/// A scripted SpindleAPI. Set the results before each refresh.
final class MockSpindleAPI: SpindleAPI, @unchecked Sendable {
    var statusResult: Result<StatusResponse, Error>
    var queueResult: Result<[QueueItem], Error>
    var statusCalls = 0
    var queueCalls = 0
    var itemCalls = 0
    var detail: QueueItem?

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
        itemCalls += 1
        if let detail, detail.id == id { return detail }
        guard let item = try queueResult.get().first(where: { $0.id == id }) else {
            throw SpindleClientError.httpStatus(404)
        }
        return item
    }

    var eventScript: [Int64: ItemEventBatch] = [:]
    var eventError: Error?
    var eventRequests: [(Int64, Int64)] = []

    func itemEvents(id: Int64, since: Int64) async throws -> ItemEventBatch {
        eventRequests.append((id, since))
        if let eventError { throw eventError }
        return eventScript[since] ?? ItemEventBatch(events: [], next: since)
    }

    /// Scripted by the query's `since`; unscripted queries return nothing.
    var logScript: [UInt64?: LogsResponse] = [:]
    var logQueries: [LogQuery] = []

    func logs(_ query: LogQuery) async throws -> LogsResponse {
        logQueries.append(query)
        return logScript[query.since] ?? LogsResponse(events: [], next: query.since ?? 0)
    }
}

@MainActor
final class SpindleMonitorTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeMonitor(_ api: MockSpindleAPI?, clockBox: ClockBox? = nil) -> SpindleMonitor {
        let clockBox = clockBox ?? ClockBox(date: clock)
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
        XCTAssertFalse(monitor.recentlyCompleted.contains { $0.id == 19 }, "review items are attention, not recently completed")
        XCTAssertEqual(Array(monitor.progress.keys), [21])
        XCTAssertEqual(monitor.progress[21]?.stage, .encoding)
        XCTAssertNil(monitor.daemonIssue)
        XCTAssertEqual(monitor.driveState, .available)
        XCTAssertEqual(monitor.resources.map(\.name), ["drive", "encode", "gpu"])
        XCTAssertEqual(monitor.resources.first { $0.name == "encode" }?.status.used, 1)
    }

    func testReservedEncoderMovesBetweenWaitingAndWorkingAcrossPolls() async throws {
        var item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        var task = try XCTUnwrap(item.tasks?.first { $0.type == .encoding })
        task.activeAssetKey = ""
        item.tasks = [task]
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: [item])
        let monitor = makeMonitor(api)

        await monitor.refresh()
        XCTAssertTrue(monitor.activeItems.isEmpty)
        XCTAssertEqual(monitor.waitingItems.map(\.id), [21])
        XCTAssertNil(monitor.progress[21])
        XCTAssertNil(monitor.taskProgress[21])

        task.activeAssetKey = "main"
        item.tasks = [task]
        api.queueResult = .success([item])
        await monitor.refresh()
        XCTAssertEqual(monitor.activeItems.map(\.id), [21])
        XCTAssertTrue(monitor.waitingItems.isEmpty)
        XCTAssertEqual(monitor.progress[21]?.stage, .encoding)

        task.activeAssetKey = nil // between episodes, the worker remains scheduled
        item.tasks = [task]
        api.queueResult = .success([item])
        await monitor.refresh()
        XCTAssertTrue(monitor.activeItems.isEmpty)
        XCTAssertEqual(monitor.waitingItems.map(\.id), [21])
        XCTAssertNil(monitor.progress[21])
    }

    func testRipETAUsesSnapshotClockAndRefreshesOnPoll() async throws {
        var item = try Fixtures.failedItem()
        item.tasks = [PipelineTask(
            type: .ripping, state: .running, startedAt: "2027-01-15T08:00:00Z",
            progress: TaskProgress(percent: 25, message: "Copying", bytesCopied: 10_000_000_000, totalBytes: 40_000_000_000)
        )]
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: [item])
        let started = try XCTUnwrap(item.tasks?.first?.startedDate)
        let clockBox = ClockBox(date: started.addingTimeInterval(1_000))
        let monitor = makeMonitor(api, clockBox: clockBox)

        await monitor.refresh()
        XCTAssertEqual(monitor.taskProgress[item.id]?.first?.etaSeconds, 3_000)
        XCTAssertEqual(monitor.progress[item.id]?.shortText, "25% · 50m left")

        clockBox.date = started.addingTimeInterval(1_200)
        await monitor.refresh()
        XCTAssertEqual(monitor.progress[item.id]?.etaSeconds, 3_600)
        XCTAssertEqual(monitor.progress[item.id]?.shortText, "25% · 1h 0m left")
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

    func testStartupNetworkFailureStaysConnectingThenRecovers() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: [])
        api.statusResult = .failure(SpindleClientError.unreachable("offline"))
        let clockBox = ClockBox(date: clock)
        let monitor = makeMonitor(api, clockBox: clockBox)

        for second in 0..<5 {
            clockBox.date = clock.addingTimeInterval(Double(second))
            let succeeded = await monitor.refresh()
            XCTAssertFalse(succeeded)
            XCTAssertEqual(monitor.connection, .connecting)
            XCTAssertEqual(monitor.consecutiveFailures, 0, "startup retries must not consume the backoff")
        }

        api.statusResult = .success(try Fixtures.status())
        let recovered = await monitor.refresh()
        XCTAssertTrue(recovered)
        XCTAssertTrue(monitor.connection.isConnected)
        XCTAssertEqual(monitor.consecutiveFailures, 0)
    }

    func testPersistentStartupFailureShowsErrorAndBacksOff() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: [])
        api.statusResult = .failure(SpindleClientError.unreachable("refused"))
        let clockBox = ClockBox(date: clock)
        let monitor = makeMonitor(api, clockBox: clockBox)

        await monitor.refresh()
        clockBox.date = clock.addingTimeInterval(SpindleMonitor.startupGracePeriod)
        for _ in 0..<5 { await monitor.refresh() }

        XCTAssertEqual(monitor.consecutiveFailures, 5)
        guard case .disconnected(_, let since, let nextRetry) = monitor.connection else {
            return XCTFail("expected disconnected")
        }
        XCTAssertEqual(since, clockBox.date)
        XCTAssertEqual(nextRetry.timeIntervalSince(clockBox.date), 30, accuracy: 0.001, "capped at maxBackoff")

        api.statusResult = .success(try Fixtures.status())
        let recovered = await monitor.refresh()
        XCTAssertTrue(recovered)
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

    func testFirstLaunchStateExplainsPlaceholderBeforeConnectionError() {
        let outage = ConnectionState.disconnected(error: "Spindle rejected the API token.", since: clock, nextRetry: clock.addingTimeInterval(5))
        XCTAssertEqual(NotConnectedView.state(placeholder: true, connection: .connecting), .setAddress)
        XCTAssertEqual(NotConnectedView.state(placeholder: true, connection: outage), .setAddress, "placeholder is not a working daemon address")
        XCTAssertEqual(NotConnectedView.state(placeholder: false, connection: .connecting), .connecting)
        XCTAssertEqual(NotConnectedView.state(placeholder: false, connection: .connected(since: clock)), .connecting, "no snapshot yet")
        XCTAssertEqual(
            NotConnectedView.state(placeholder: false, connection: outage),
            .disconnected(error: "Spindle rejected the API token.", hint: SpindleMonitor.hint(for: "Spindle rejected the API token."))
        )
        let unknown = ConnectionState.disconnected(error: "HTTP 500", since: clock, nextRetry: clock)
        XCTAssertEqual(NotConnectedView.state(placeholder: false, connection: unknown), .disconnected(error: "HTTP 500", hint: nil))
    }

    func testUnauthorizedIsReportedDistinctly() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: [])
        api.statusResult = .failure(SpindleClientError.unauthorized)
        let monitor = makeMonitor(api)

        await monitor.refresh()

        XCTAssertEqual(monitor.connection.errorMessage, "Spindle rejected the API token.")
        XCTAssertEqual(monitor.consecutiveFailures, 1, "authentication errors should not get a startup grace period")
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

    func testDaemonIssueFromStatus() throws {
        var status = try Fixtures.status()
        XCTAssertNil(SpindleMonitor.daemonIssue(from: status))
        status.workflow.lastError = "  disc monitor crashed "
        XCTAssertEqual(SpindleMonitor.daemonIssue(from: status), "Workflow error: disc monitor crashed")
        status.running = false
        XCTAssertEqual(SpindleMonitor.daemonIssue(from: status), "The daemon reports it is not running.", "stopped outranks the error text")
    }

    func testConnectionEventsFireOnlyAroundAnOutage() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: try Fixtures.queue())
        let monitor = makeMonitor(api)
        var received: [MonitorEvent] = []
        monitor.onEvents = { received.append(contentsOf: $0) }

        api.statusResult = .failure(SpindleClientError.unreachable("refused"))
        await monitor.refresh()
        XCTAssertEqual(monitor.connection, .connecting)
        XCTAssertEqual(received, [], "never connected, so nothing was lost")

        api.statusResult = .success(try Fixtures.status())
        await monitor.refresh()
        XCTAssertEqual(received, [], "first successful poll seeds without a reconnect notice")

        api.statusResult = .failure(SpindleClientError.unreachable("refused"))
        await monitor.refresh()
        await monitor.refresh()
        XCTAssertEqual(received.map(\.kind), [.connection], "one notice per outage, not per failed poll")
        guard case .disconnected(let message)? = received.first else { return XCTFail("expected disconnected") }
        XCTAssertTrue(message.contains("unreachable"))

        api.statusResult = .success(try Fixtures.status())
        await monitor.refresh()
        XCTAssertEqual(received, [.disconnected(message), .reconnected])
        XCTAssertEqual(monitor.lastEvents, [.reconnected])
    }

    func testPollIntervalIsSettable() {
        let monitor = makeMonitor(nil)
        XCTAssertEqual(monitor.pollInterval, 2)
        monitor.pollInterval = 5
        XCTAssertEqual(monitor.pollInterval, 5)
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
        XCTAssertNotNil(monitor.connection.errorMessage, "an outage after a snapshot is reported immediately")
    }

    func testSelectionFetchesDetailAndRefreshesIt() async throws {
        struct Envelope: Decodable { var item: QueueItem }
        let detail = try Fixtures.decode(Envelope.self, from: "item").item
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: try Fixtures.queue())
        api.detail = detail
        let monitor = makeMonitor(api)
        await monitor.refresh()
        XCTAssertNil(monitor.selectedItemDetail)

        monitor.selectedItemID = 21
        await monitor.awaitPendingDetail()
        XCTAssertEqual(api.itemCalls, 1, "selecting fetches the detail once")
        XCTAssertEqual(monitor.selectedItemDetail?.id, 21)
        XCTAssertNotNil(monitor.selectedItemDetail?.ripSpec, "detail carries the rip spec the list omits")

        await monitor.refresh()
        XCTAssertEqual(api.itemCalls, 2, "each poll refreshes the selected detail")

        monitor.selectedItemID = nil
        XCTAssertNil(monitor.selectedItemDetail)
        await monitor.refresh()
        XCTAssertEqual(api.itemCalls, 2, "no detail fetch without a selection")
    }

    func testAppModelRoutesFocusAndDeepLinksToVisibleSections() async throws {
        let suite = "shuttle.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettingsStore(defaults: defaults)
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: try Fixtures.queue())
        let monitor = makeMonitor(api)
        let model = AppModel(settings: settings, monitor: monitor, defaults: defaults)
        XCTAssertEqual(model.section, .now)
        let connected = await monitor.refresh()
        XCTAssertTrue(connected)

        model.focus(itemID: 21)
        XCTAssertEqual(model.section, .now, "stay on Now when it already shows the item")
        XCTAssertEqual(monitor.selectedItemID, 21)
        model.section = .attention
        model.focus(itemID: 19)
        XCTAssertEqual(model.section, .attention, "stay on Attention for a review item")
        model.section = .queue
        model.focus(itemID: 19)
        XCTAssertEqual(model.section, .attention, "prefer the short attention list")
        model.focus(itemID: 20)
        XCTAssertEqual(model.section, .now, "recently completed items are on Now")
        model.focus(itemID: 1)
        XCTAssertEqual(model.section, .queue, "older completed items live only in Queue")

        model.handle(.main)
        XCTAssertEqual(model.section, .queue)
        model.handle(.section(.dependencies))
        XCTAssertEqual(model.section, .dependencies)
        model.handle(.item(21))
        XCTAssertEqual(model.section, .now)
        XCTAssertEqual(monitor.selectedItemID, 21)
        XCTAssertEqual(defaults.string(forKey: "sidebarSection"), SidebarSection.now.rawValue)
    }

    func testAppModelRestoresSectionAndResetsQueueOrder() throws {
        let suite = "shuttle.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(SidebarSection.log.rawValue, forKey: "sidebarSection")
        let model = AppModel(settings: AppSettingsStore(defaults: defaults), defaults: defaults)
        XCTAssertEqual(model.section, .log)
        model.queueSortOrder = [KeyPathComparator(\.id)]
        model.resetQueueSort()
        let items = try Fixtures.queue() + [Fixtures.failedItem()]
        XCTAssertEqual(items.sorted(using: model.queueSortOrder).first?.id, 99, "default sort puts failures first")
        model.section = .attention
        XCTAssertEqual(AppModel(settings: AppSettingsStore(defaults: defaults), defaults: defaults).section, .attention)
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
