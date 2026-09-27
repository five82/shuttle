import XCTest
import UserNotifications
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

    func testOverlappingItemTransitionsAndReviewClearing() throws {
        let running = try item(7, stage: .encoding, running: true)
        let completed = try item(7, stage: .completed)
        let review = try item(7, stage: .completed, review: true)
        let failedReview = try item(7, stage: .failed, review: true)

        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [running], drive: .available, items: [failedReview]), [.failed(failedReview)], "failure outranks review")
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [completed], drive: .available, items: [review]), [.needsReview(review)], "late review after completion still needs attention")
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [review], drive: .available, items: [completed]), [], "clearing review does not replay completion")
        XCTAssertEqual(EventDetector.events(previousDrive: .available, previousItems: [running], drive: .available, items: [running]), [], "progress updates are silent")
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

    @MainActor
    func testNotificationPayloadsForEveryEvent() throws {
        let item = try item(21, stage: .encoding)
        let review = NotificationService.content(for: .needsReview(item))
        XCTAssertEqual(review.title, "Needs review · Item 21")
        XCTAssertEqual(review.body, "Routed to review.")
        XCTAssertEqual(review.subtitle, "#21")
        XCTAssertEqual((review.userInfo["itemID"] as? NSNumber)?.int64Value, 21)
        XCTAssertEqual(review.threadIdentifier, NotificationKind.needsReview.rawValue)
        XCTAssertNotNil(review.sound)

        let failed = NotificationService.content(for: .failed(item))
        XCTAssertEqual(failed.title, "Failed · Item 21")
        XCTAssertEqual(failed.body, "Stopped before completing.")
        XCTAssertEqual((failed.userInfo["itemID"] as? NSNumber)?.int64Value, 21)
        XCTAssertEqual(failed.interruptionLevel, .timeSensitive)

        let completed = NotificationService.content(for: .completed(item))
        XCTAssertEqual(completed.title, "Completed · Item 21")
        XCTAssertEqual(completed.body, "Ready in the library.")
        XCTAssertNil(completed.sound)
        XCTAssertEqual((completed.userInfo["itemID"] as? NSNumber)?.int64Value, 21)

        let drive = NotificationService.content(for: .driveAvailable)
        XCTAssertEqual(drive.title, "Drive available")
        XCTAssertEqual(drive.body, "Insert the next disc.")
        XCTAssertTrue(drive.userInfo.isEmpty)
        XCTAssertNotNil(drive.sound)

        let lost = NotificationService.content(for: .disconnected("Timed out"))
        XCTAssertEqual(lost.title, "Lost connection to Spindle")
        XCTAssertEqual(lost.body, "Timed out")
        XCTAssertNil(lost.sound)
        XCTAssertTrue(lost.userInfo.isEmpty)

        let restored = NotificationService.content(for: .reconnected)
        XCTAssertEqual(restored.title, "Reconnected to Spindle")
        XCTAssertEqual(restored.body, "Polling resumed.")
        XCTAssertNil(restored.sound)
        XCTAssertTrue(restored.userInfo.isEmpty)
    }

    @MainActor
    func testNotificationDeliveryRespectsSettingsAndUsesUniqueRequests() throws {
        let item = try item(21, stage: .completed)
        var requests: [UNNotificationRequest] = []
        let service = NotificationService(addRequest: { requests.append($0) })
        var settings = AppSettings.defaults
        let events: [MonitorEvent] = [.completed(item), .disconnected("offline"), .reconnected, .driveAvailable]

        service.post(events, settings: settings)
        XCTAssertEqual(requests.map { $0.content.title }, ["Completed · Item 21", "Drive available"], "connection notices are off by default")
        XCTAssertTrue(requests.allSatisfy { $0.trigger == nil })
        XCTAssertEqual(Set(requests.map(\.identifier)).count, 2)

        requests = []
        settings.notifications = [.connection]
        service.post(events, settings: settings)
        XCTAssertEqual(requests.map { $0.content.title }, ["Lost connection to Spindle", "Reconnected to Spindle"])
        XCTAssertEqual(requests.map { $0.content.threadIdentifier }, ["connection", "connection"])
        XCTAssertEqual(Set(requests.map(\.identifier)).count, 2, "two connection events on one poll must stay distinct")
    }

    @MainActor
    func testNotificationPayloadUsesItemAttentionReasons() throws {
        let items = try Fixtures.queue()
        let review = try XCTUnwrap(items.first { $0.id == 19 })
        let failure = try Fixtures.failedItem()
        XCTAssertEqual(NotificationService.content(for: .needsReview(review)).body, review.attentionReason)
        XCTAssertEqual(NotificationService.content(for: .failed(failure)).body, failure.attentionReason)
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
