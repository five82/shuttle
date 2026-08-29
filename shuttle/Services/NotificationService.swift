import AppKit
import Foundation
import UserNotifications

/// Turns monitor events into user notifications. Tapping one opens the item
/// through the app's `shuttle://item/<id>` URL scheme.
@MainActor
final class NotificationService: NSObject {
    private let center = UNUserNotificationCenter.current()
    private var activated = false

    func activate() {
        guard !activated else { return }
        activated = true
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Whether macOS will actually show anything; Settings shows the answer.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func post(_ events: [MonitorEvent], settings: AppSettings) {
        for event in events where settings.notifies(event.kind) {
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.threadIdentifier = event.kind.rawValue
            if let item = event.item {
                content.subtitle = "#\(item.id)"
            }

            switch event {
            case .driveAvailable:
                content.title = "Drive available"
                content.body = "Insert the next disc."
            case .needsReview(let item):
                content.title = "Needs review · \(item.displayTitle)"
                content.body = item.attentionReason ?? "Routed to review."
                content.userInfo = ["itemID": item.id]
            case .failed(let item):
                content.title = "Failed · \(item.displayTitle)"
                content.body = item.attentionReason ?? "Stopped before completing."
                content.userInfo = ["itemID": item.id]
                content.interruptionLevel = .timeSensitive
            case .completed(let item):
                content.title = "Completed · \(item.displayTitle)"
                content.body = "Ready in the library."
                content.userInfo = ["itemID": item.id]
                // A box set completes twenty times in a row; the banner is enough.
                content.sound = nil
            case .disconnected(let error):
                content.title = "Lost connection to Spindle"
                content.body = error
                content.sound = nil
            case .reconnected:
                content.title = "Reconnected to Spindle"
                content.body = "Polling resumed."
                content.sound = nil
            }

            let identifier = "\(event.kind.rawValue)-\(event.item?.id ?? 0)-\(Date().timeIntervalSince1970)"
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    func updateBadge(attentionCount: Int) {
        NSApp.dockTile.badgeLabel = attentionCount > 0 ? String(attentionCount) : nil
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banners even while shuttle is frontmost; the window may be behind others.
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let itemID = (userInfo["itemID"] as? NSNumber)?.int64Value
        Task { @MainActor in
            DeepLink.open(itemID.map { .item($0) } ?? .main)
        }
        completionHandler()
    }
}

/// `shuttle://main`, `shuttle://item/<id>`, and `shuttle://section/<name>`.
/// Opening one through NSWorkspace makes SwiftUI create the main window if
/// it is closed, which is the one thing `openWindow` cannot do from outside
/// a view.
enum DeepLink: Equatable {
    static let scheme = "shuttle"

    case main
    case item(Int64)
    case section(SidebarSection)

    var url: URL {
        switch self {
        case .main: return URL(string: "\(Self.scheme)://main")!
        case .item(let id): return URL(string: "\(Self.scheme)://item/\(id)")!
        case .section(let section): return URL(string: "\(Self.scheme)://section/\(section.rawValue)")!
        }
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "main":
            self = .main
        case "item":
            guard let id = Int64(url.lastPathComponent) else { return nil }
            self = .item(id)
        case "section":
            guard let section = SidebarSection(rawValue: url.lastPathComponent) else { return nil }
            self = .section(section)
        default:
            return nil
        }
    }

    @MainActor
    static func open(_ link: DeepLink) {
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.open(link.url)
    }
}
