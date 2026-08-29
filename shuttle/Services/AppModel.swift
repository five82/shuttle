import AppKit
import Foundation
import Observation
import SwiftUI

/// Owns the long-lived objects and wires them together. One instance for
/// the process, shared by the app, the delegate, and the menu bar extra.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(settings: AppSettingsStore())

    let settings: AppSettingsStore
    let monitor: SpindleMonitor
    let notifications: NotificationService

    private static let sectionKey = "sidebarSection"

    /// Restored across launches so the window reopens where it was.
    var section: SidebarSection {
        didSet { UserDefaults.standard.set(section.rawValue, forKey: Self.sectionKey) }
    }

    /// Queue table order; lives here so a menu command can reset it.
    var queueSortOrder: [KeyPathComparator<QueueItem>] = AppModel.defaultQueueSortOrder

    static let defaultQueueSortOrder: [KeyPathComparator<QueueItem>] = [
        KeyPathComparator(\.priorityRank),
        KeyPathComparator(\.id, order: .reverse),
    ]

    init(settings: AppSettingsStore) {
        self.settings = settings
        self.notifications = NotificationService()
        self.monitor = SpindleMonitor(clientProvider: { settings.makeClient() }, pollInterval: settings.settings.pollInterval)
        self.section = UserDefaults.standard.string(forKey: Self.sectionKey).flatMap(SidebarSection.init(rawValue:)) ?? .now

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

    /// Selects an item in a section that shows the inspector. Stays put when
    /// the current section already does (Now, Queue, Attention), so a click
    /// on a Now row doesn't yank the operator over to the Queue.
    func focus(itemID: Int64) {
        if !section.showsInspector { section = .queue }
        monitor.selectedItemID = itemID
    }

    func resetQueueSort() {
        queueSortOrder = Self.defaultQueueSortOrder
    }

    func applyPollInterval() {
        monitor.pollInterval = settings.settings.pollInterval
        monitor.refreshNow()
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
