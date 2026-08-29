import XCTest
@testable import shuttle

final class EventDetectorTests: XCTestCase {
    private func item(_ id: Int64, stage: Stage, review: Bool = false, running: Bool = false) throws -> QueueItem {
        var item = try Fixtures.failedItem()
        item.id = id
        item.displayTitle = "Item \(id)"
        item.stage = stage
        item.needsReview = review
        item.failedAtStage = nil
        item.errorMessage = nil
        item.tasks = running
            ? [PipelineTask(type: stage, state: .running, progress: TaskProgress(percent: 0, message: ""))]
            : nil
        return item
    }

    func testDriveTransitionToAvailable() {
        let holder = ResourceHolder(itemId: 1, task: .ripping)
        XCTAssertEqual(EventDetector.events(previousDrive: .busy([holder]), previousItems: [], drive: .available, items: []), [.driveAvailable])
        XCTAssertEqual(EventDetector.events(previousDrive: .paused, previousItems: [], drive: .available, items: []), [.driveAvailable])
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [], drive: .available, items: []), [])
        XCTAssertEqual(EventDetector.events(previousDrive: .unknown, previousItems: [], drive: .available, items: []), [], "first real status after unknown is not a transition")
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [], drive: .busy([holder]), items: []), [])
    }

    func testItemTransitions() throws {
        let encoding = try item(1, stage: .encoding, running: true)
        let completed = try item(1, stage: .completed)
        let reviewed = try item(1, stage: .completed, review: true)
        var failed = try item(1, stage: .failed)
        failed.failedAtStage = .encoding

        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [encoding], drive: .available, items: [completed]), [.completed(completed)])
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [encoding], drive: .available, items: [reviewed]), [.needsReview(reviewed)], "review outranks completed")
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [encoding], drive: .available, items: [failed]), [.failed(failed)])
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [completed], drive: .available, items: [completed]), [])
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [reviewed], drive: .available, items: [reviewed]), [])
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [failed], drive: .available, items: [failed]), [])
    }

    func testNotificationDefaults() {
        XCTAssertEqual(NotificationKind.allCases.filter { !$0.isOnByDefault }, [.connection])
        XCTAssertEqual(MonitorEvent.disconnected("x").kind, .connection)
        XCTAssertEqual(MonitorEvent.reconnected.kind, .connection)
        XCTAssertNil(MonitorEvent.reconnected.item)
        XCTAssertFalse(AppSettings.defaults.notifies(.connection))
        XCTAssertTrue(AppSettings.defaults.notifies(.completed))
    }

    func testNewAndRemovedItemsAreSilent() throws {
        let failed = try item(7, stage: .failed)
        let completed = try item(8, stage: .completed)
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [], drive: .available, items: [failed, completed]), [], "items never seen before don't replay history")
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [failed, completed], drive: .available, items: []), [])
    }

    func testEventsAreOrderedDriveFirstThenByID() throws {
        let a = try item(3, stage: .encoding, running: true)
        let b = try item(2, stage: .encoding, running: true)
        let aDone = try item(3, stage: .completed)
        var bFailed = try item(2, stage: .failed)
        bFailed.failedAtStage = .encoding
        let events = EventDetector.events(previousDrive: .busy([]), previousItems: [a, b], drive: .available, items: [aDone, bFailed])
        XCTAssertEqual(events, [.driveAvailable, .failed(bFailed), .completed(aDone)])
        XCTAssertEqual(events.map(\.kind), [.driveAvailable, .failed, .completed])
        XCTAssertEqual(events.compactMap { $0.item?.id }, [2, 3])
    }

    func testDeepLinkRoundTrip() {
        XCTAssertEqual(DeepLink(url: DeepLink.main.url), .main)
        XCTAssertEqual(DeepLink(url: DeepLink.item(21).url), .item(21))
        XCTAssertEqual(DeepLink.item(21).url.absoluteString, "shuttle://item/21")
        XCTAssertNil(DeepLink(url: URL(string: "shuttle://item/x")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/item/1")!))
    }

    @MainActor
    func testNotificationSettingsPersist() {
        let suite = "shuttle.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(store.settings.notifies(.completed))
        XCTAssertFalse(store.settings.menuBarOnly)

        store.setNotification(.completed, enabled: false)
        store.setMenuBarOnly(true)

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.settings.notifies(.completed))
        XCTAssertTrue(reloaded.settings.notifies(.failed))
        XCTAssertTrue(reloaded.settings.menuBarOnly)

        reloaded.resetToDefaults()
        XCTAssertTrue(reloaded.settings.notifies(.completed))
        XCTAssertFalse(reloaded.settings.menuBarOnly)
    }
}
