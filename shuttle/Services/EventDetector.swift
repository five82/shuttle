import Foundation

/// Kinds of things shuttle can notify about. Each has a Settings toggle.
enum NotificationKind: String, CaseIterable, Identifiable, Sendable {
    case driveAvailable
    case needsReview
    case failed
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driveAvailable: return "Drive available"
        case .needsReview: return "Item needs review"
        case .failed: return "Item failed"
        case .completed: return "Item completed"
        }
    }

    var detail: String {
        switch self {
        case .driveAvailable: return "The drive went from busy to free. Time to insert the next disc."
        case .needsReview: return "An item finished but was routed to review."
        case .failed: return "An item stopped before completing."
        case .completed: return "An item reached the library."
        }
    }
}

/// A transition worth telling the operator about, derived by diffing two
/// consecutive snapshots.
enum MonitorEvent: Equatable, Sendable {
    case driveAvailable
    case needsReview(QueueItem)
    case failed(QueueItem)
    case completed(QueueItem)

    var kind: NotificationKind {
        switch self {
        case .driveAvailable: return .driveAvailable
        case .needsReview: return .needsReview
        case .failed: return .failed
        case .completed: return .completed
        }
    }

    var item: QueueItem? {
        switch self {
        case .driveAvailable: return nil
        case .needsReview(let item), .failed(let item), .completed(let item): return item
        }
    }
}

/// Pure snapshot diffing. Only transitions of items seen in the previous
/// snapshot count, so a daemon restart or queue clear never replays history,
/// and the caller seeds with the first poll before asking for events.
enum EventDetector {
    static func events(
        previousDrive: DriveState,
        previousItems: [QueueItem],
        drive: DriveState,
        items: [QueueItem]
    ) -> [MonitorEvent] {
        var events: [MonitorEvent] = []

        if drive == .available, previousDrive != .available, previousDrive != .unknown {
            events.append(.driveAvailable)
        }

        let previous = Dictionary(previousItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in items.sorted(by: { $0.id < $1.id }) {
            guard let old = previous[item.id] else { continue }
            if item.hasFailed, !old.hasFailed {
                events.append(.failed(item))
            } else if item.needsReview, !old.needsReview {
                events.append(.needsReview(item))
            } else if item.isCompleted, !old.isCompleted, !item.needsReview {
                events.append(.completed(item))
            }
        }

        return events
    }
}
