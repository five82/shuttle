import XCTest
@testable import shuttle

final class WaitReasonTests: XCTestCase {
    private func resources(encodeUsed: Int = 0, gpuUsed: Int = 0) -> [String: ResourceStatus] {
        [
            "drive": ResourceStatus(capacity: 1, used: 0, holders: []),
            "encode": ResourceStatus(capacity: 1, used: encodeUsed, holders: encodeUsed > 0 ? [ResourceHolder(itemId: 21, task: .encoding)] : []),
            "gpu": ResourceStatus(capacity: 1, used: gpuUsed, holders: []),
        ]
    }

    func testWaitingForEncodeSlotBehindAnotherItem() throws {
        let status = try Fixtures.status()
        let item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 22 })
        XCTAssertTrue(item.isWaiting)
        let reason = WaitReason.derive(for: item, pipeline: status.pipelineStages, resources: resources(encodeUsed: 1))
        XCTAssertEqual(reason, .resource(next: .encoding, name: "encode", holders: [ResourceHolder(itemId: 21, task: .encoding)]))
        XCTAssertEqual(reason.short, "encode slot busy")
        XCTAssertEqual(reason.detail, "Encoding is ready but the encode slot is in use by #21.")
    }

    func testReadyWhenResourceIsFree() throws {
        let status = try Fixtures.status()
        let item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 22 })
        let reason = WaitReason.derive(for: item, pipeline: status.pipelineStages, resources: resources())
        XCTAssertEqual(reason, .ready(next: .encoding))
        XCTAssertEqual(reason.short, "next up")
    }

    func testDependencyWhenUpstreamStillRunning() throws {
        let status = try Fixtures.status()
        var item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 22 })
        // Pretend only apply and organizing remain, with encoding still running elsewhere in the DAG.
        item.tasks = item.tasks?.map { task in
            var task = task
            switch task.type {
            case .encoding: task.state = .running
            case .apply, .organizing: task.state = .pending
            default: task.state = .done
            }
            return task
        }
        item.stage = .apply
        let reason = WaitReason.derive(for: item, pipeline: status.pipelineStages, resources: resources(encodeUsed: 1))
        XCTAssertEqual(reason, .dependency(next: .apply, on: .encoding))
        XCTAssertEqual(reason.short, "after Encoding")
    }

    func testFallsBackToQueuedWithoutTasks() throws {
        var item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 22 })
        item.tasks = nil
        XCTAssertEqual(WaitReason.derive(for: item, pipeline: [], resources: [:]), .queued(.encoding))
    }

    func testMonitorDerivesWaitReasonsAndTaskProgress() async throws {
        let api = MockSpindleAPI(status: try Fixtures.status(), queue: try Fixtures.queue())
        let monitor = await SpindleMonitor(clientProvider: { api }, sleeper: { _ in })
        await monitor.refresh()
        let reasons = await monitor.waitReasons
        XCTAssertEqual(reasons[22]?.next, .encoding)
        XCTAssertEqual(reasons[22]?.short, "encode slot busy", "the fixture's encode slot is held by #21")
        let progress = await monitor.taskProgress[21]
        XCTAssertEqual(progress?.count, 1)
        XCTAssertEqual(progress?.first?.stage, .encoding)
        XCTAssertEqual(Stage.pipelineOrder.first, .identification, "the monitor publishes the template order")
        XCTAssertLessThan(Stage.ripping.rank, Stage.encoding.rank)
        XCTAssertLessThan(Stage.organizing.rank, Stage.completed.rank)
        XCTAssertLessThan(Stage.completed.rank, Stage.failed.rank)
    }

    func testBranchDepthsIndentTheForkedBranch() throws {
        let status = try Fixtures.status()
        let depths = PipelineCell.branchDepths(pipeline: status.pipelineStages)
        XCTAssertEqual(depths[.identification], 0)
        XCTAssertEqual(depths[.ripping], 0)
        XCTAssertEqual(depths[.episodeIdentification], 0)
        XCTAssertEqual(depths[.encoding], 1, "encoding forks off identification beside ripping")
        XCTAssertEqual(depths[.analysis], 0)
        XCTAssertEqual(depths[.subtitling], 0)
        XCTAssertEqual(depths[.apply], 0, "a join returns to the main chain")
        XCTAssertEqual(depths[.organizing], 0)
        let item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        let cells = PipelineCell.cells(for: item, pipeline: status.pipelineStages)
        XCTAssertEqual(cells.first { $0.stage == .encoding }?.claims, ["encode"])
        XCTAssertEqual(cells.first { $0.stage == .analysis }?.claims, ["gpu"])
    }

    func testProgressListOnePerRunningTask() throws {
        var item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        item.tasks = item.tasks?.map { task in
            var task = task
            if task.type == .subtitling { task.state = .running; task.progress.percent = 40 }
            return task
        }
        let list = item.progressList
        XCTAssertEqual(list.map(\.stage), [.encoding, .subtitling], "pipeline order, not task order")
        XCTAssertEqual(item.progress?.stage, .subtitling, "the furthest-along task is the single-bar summary")
    }
}

final class FormatTests: XCTestCase {
    func testDurationDropsSecondsPastAMinute() {
        XCTAssertEqual(Format.duration(12), "12s")
        XCTAssertEqual(Format.duration(59.6), "1m")
        XCTAssertEqual(Format.duration(2572), "42m")
        XCTAssertEqual(Format.duration(4320), "1h 12m")
        XCTAssertEqual(Format.duration(-5), "0s")
    }

    func testAgoIsCoarse() {
        let now = Date()
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-3), from: now), "just now")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-27), from: now), "20s ago")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-300), from: now), "5m ago")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-7800), from: now), "2h 10m ago")
    }

    func testPercentFloors() {
        XCTAssertEqual(Format.percent(0.996), "99%")
        XCTAssertEqual(Format.percent(1), "100%")
        XCTAssertEqual(Format.percent(0), "0%")
        XCTAssertEqual(Format.percent(1.4), "100%")
    }

    func testResourceProse() {
        XCTAssertEqual(Format.resource("gpu"), "GPU")
        XCTAssertEqual(Format.resource("encode"), "encode slot")
        XCTAssertEqual(Format.resource("drive"), "drive")
    }
}

final class LibraryMappingTests: XCTestCase {
    func testMapsRemotePrefixToLocalMount() {
        var settings = AppSettings.defaults
        XCTAssertNil(settings.localLibraryPath(for: "/mnt/media/Movies/A.mkv"), "no mapping, no path")
        settings.libraryRemotePrefix = "/mnt/media/"
        settings.libraryLocalPrefix = "/Volumes/media"
        XCTAssertEqual(settings.localLibraryPath(for: "/mnt/media/Movies/A.mkv"), "/Volumes/media/Movies/A.mkv")
        XCTAssertEqual(settings.localLibraryPath(for: "/mnt/media"), "/Volumes/media")
        XCTAssertNil(settings.localLibraryPath(for: "/mnt/mediaX/A.mkv"), "prefix must end at a path boundary")
        XCTAssertNil(settings.localLibraryPath(for: "/srv/other/A.mkv"))
    }

    @MainActor
    func testLibraryMappingAndTokenPersist() {
        let suite = "shuttle.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tokens = InMemoryTokenStore()

        let store = AppSettingsStore(defaults: defaults, tokenStore: tokens)
        store.updateLibraryMapping(remote: "/mnt/media", local: "/Volumes/media")
        store.updateToken("secret")
        XCTAssertEqual(tokens.read(), "secret")
        XCTAssertNil(defaults.string(forKey: "spindleAPIToken"), "the token never lands in defaults")

        let reloaded = AppSettingsStore(defaults: defaults, tokenStore: tokens)
        XCTAssertEqual(reloaded.settings.libraryRemotePrefix, "/mnt/media")
        XCTAssertEqual(reloaded.settings.libraryLocalPrefix, "/Volumes/media")
        XCTAssertEqual(reloaded.settings.token, "secret")

        reloaded.resetToDefaults()
        XCTAssertNil(tokens.read())
        XCTAssertEqual(reloaded.settings.libraryLocalPrefix, "")
    }

    @MainActor
    func testLegacyDefaultsTokenMigratesToTheStore() {
        let suite = "shuttle.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("old-token", forKey: "spindleAPIToken")
        let tokens = InMemoryTokenStore()

        let store = AppSettingsStore(defaults: defaults, tokenStore: tokens)
        XCTAssertEqual(store.settings.token, "old-token")
        XCTAssertEqual(tokens.read(), "old-token")
        XCTAssertNil(defaults.string(forKey: "spindleAPIToken"))
    }

    func testSectionDeepLinks() {
        XCTAssertEqual(DeepLink(url: URL(string: "shuttle://section/attention")!), .section(.attention))
        XCTAssertEqual(DeepLink.section(.dependencies).url.absoluteString, "shuttle://section/dependencies")
        XCTAssertNil(DeepLink(url: URL(string: "shuttle://section/nope")!))
    }

    func testConnectionHints() {
        XCTAssertNotNil(SpindleMonitor.hint(for: "Spindle rejected the API token."))
        XCTAssertNotNil(SpindleMonitor.hint(for: "Spindle is unreachable: The Internet connection appears to be offline."))
        XCTAssertNotNil(SpindleMonitor.hint(for: "Spindle is unreachable: Could not connect to the server."))
        XCTAssertNil(SpindleMonitor.hint(for: "Spindle returned HTTP 500."))
    }
}
