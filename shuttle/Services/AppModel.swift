import AppKit
import Foundation
import Observation

/// Owns the long-lived objects and wires them together. One instance for
/// the process, shared by the app, the delegate, and the menu bar extra.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(settings: AppSettingsStore())

    let settings: AppSettingsStore
    let monitor: SpindleMonitor
    let notifications: NotificationService

    var section: SidebarSection = .now

    init(settings: AppSettingsStore) {
        self.settings = settings
        self.notifications = NotificationService()
        self.monitor = SpindleMonitor(clientProvider: { settings.makeClient() })

        monitor.onEvents = { [weak self] events in
            self?.handle(events)
        }
        monitor.onSnapshot = { [weak self] in
            guard let self else { return }
            notifications.updateBadge(attentionCount: monitor.attentionCount)
        }
    }

    /// Called once from the app delegate. Polling runs for the life of the
    /// process, whether or not a window is open.
    func start() {
        notifications.activate()
        applyActivationPolicy()
        monitor.start()
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.settings.menuBarOnly ? .accessory : .regular)
    }

    func focus(itemID: Int64) {
        section = .queue
        monitor.selectedItemID = itemID
    }

    func handle(_ link: DeepLink) {
        switch link {
        case .main: break
        case .item(let id): focus(itemID: id)
        }
    }

    private func handle(_ events: [MonitorEvent]) {
        notifications.post(events, settings: settings.settings)
    }
}
