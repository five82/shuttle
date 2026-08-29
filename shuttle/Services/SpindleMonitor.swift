import Foundation
import Observation

enum ConnectionState: Equatable, Sendable {
    case connecting
    case connected(since: Date)
    case disconnected(error: String, since: Date, nextRetry: Date)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .disconnected(let error, _, _) = self { return error }
        return nil
    }
}

enum DriveState: Equatable, Sendable {
    case unknown
    case available
    case busy([ResourceHolder])
    case paused

    var label: String {
        switch self {
        case .unknown: return "Drive"
        case .available: return "Drive available"
        case .busy: return "Drive busy"
        case .paused: return "Drive paused"
        }
    }
}

struct NamedResource: Identifiable, Equatable, Sendable {
    var name: String
    var status: ResourceStatus
    var id: String { name }
}

/// Single source of truth for everything the app shows. Polls status and
/// queue together, applies them atomically, and backs off while the daemon
/// is unreachable. Never issues a mutating request.
@Observable
@MainActor
final class SpindleMonitor {
    typealias ClientProvider = @MainActor () -> SpindleAPI?
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    static let defaultPollInterval: TimeInterval = 2
    static let defaultMaxBackoff: TimeInterval = 30

    private(set) var connection: ConnectionState = .connecting
    private(set) var status: StatusResponse?
    private(set) var items: [QueueItem] = []
    private(set) var lastRefresh: Date?
    private(set) var consecutiveFailures = 0

    /// Selection is item-ID-sticky across polls; cleared if the item disappears.
    var selectedItemID: Int64? {
        didSet {
            guard oldValue != selectedItemID else { return }
            selectedItemDetail = nil
            detailTask?.cancel()
            detailTask = nil
            if selectedItemID != nil {
                detailTask = Task { [weak self] in await self?.fetchSelectedItemDetail() }
            }
        }
    }

    /// The selected item from `GET /api/queue/{id}`, which adds the rip
    /// spec. Refreshed with every poll while the selection holds.
    private(set) var selectedItemDetail: QueueItem?
    private var detailTask: Task<Void, Never>?

    /// Transitions detected by the most recent successful poll.
    private(set) var lastEvents: [MonitorEvent] = []
    /// Called after a successful poll that produced events. Never on the first poll.
    var onEvents: (([MonitorEvent]) -> Void)?
    /// Called after every successful poll.
    var onSnapshot: (() -> Void)?

    // Derived once per snapshot, never in view bodies.
    private(set) var activeItems: [QueueItem] = []
    private(set) var attentionItems: [QueueItem] = []
    private(set) var waitingItems: [QueueItem] = []
    private(set) var recentlyCompleted: [QueueItem] = []
    private(set) var driveState: DriveState = .unknown
    private(set) var resources: [NamedResource] = []

    let pollInterval: TimeInterval
    let maxBackoff: TimeInterval

    private let clientProvider: ClientProvider
    private let sleeper: Sleeper
    private let now: @Sendable () -> Date
    private var pollTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?

    init(
        clientProvider: @escaping ClientProvider,
        pollInterval: TimeInterval = SpindleMonitor.defaultPollInterval,
        maxBackoff: TimeInterval = SpindleMonitor.defaultMaxBackoff,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientProvider = clientProvider
        self.pollInterval = pollInterval
        self.maxBackoff = maxBackoff
        self.sleeper = sleeper
        self.now = now
    }

    // MARK: - Lifecycle

    var isRunning: Bool { pollTask != nil }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let succeeded = await self.refresh()
                let delay = succeeded
                    ? self.pollInterval
                    : Self.backoff(failures: self.consecutiveFailures, base: self.pollInterval, max: self.maxBackoff)
                await self.pause(delay)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        sleepTask?.cancel()
        sleepTask = nil
    }

    /// Cuts the current wait short so the next poll happens immediately.
    func refreshNow() {
        sleepTask?.cancel()
    }

    private func pause(_ delay: TimeInterval) async {
        let sleeper = self.sleeper
        let task = Task<Void, Never> { _ = try? await sleeper(delay) }
        sleepTask = task
        await task.value
        if sleepTask == task { sleepTask = nil }
    }

    // MARK: - Polling

    /// Fetches status and queue together. The snapshot updates only when both
    /// succeed, so the UI never mixes two generations of data.
    @discardableResult
    func refresh() async -> Bool {
        guard let client = clientProvider() else {
            recordFailure("Spindle address is not a valid URL. Check Settings.")
            return false
        }
        do {
            async let status = client.status()
            async let queue = client.queue()
            let snapshot = try await (status, queue)
            apply(status: snapshot.0, items: snapshot.1)
            await fetchSelectedItemDetail(using: client)
            return true
        } catch {
            recordFailure(Self.describe(error))
            return false
        }
    }

    /// Waits for the detail fetch started by a selection change, if any.
    func awaitPendingDetail() async {
        await detailTask?.value
    }

    /// Non-fatal: a failed detail fetch leaves the list item on screen.
    func fetchSelectedItemDetail(using client: SpindleAPI? = nil) async {
        guard let id = selectedItemID, let client = client ?? clientProvider() else { return }
        guard let detail = try? await client.item(id: id) else { return }
        if selectedItemID == id {
            selectedItemDetail = detail
        }
    }

    static func backoff(failures: Int, base: TimeInterval, max: TimeInterval) -> TimeInterval {
        guard failures > 0 else { return base }
        let exponent = min(failures, 16)
        return min(base * pow(2, Double(exponent)), max)
    }

    static func describe(_ error: Error) -> String {
        if let clientError = error as? SpindleClientError {
            return clientError.errorDescription ?? String(describing: clientError)
        }
        return error.localizedDescription
    }

    private func recordFailure(_ message: String) {
        consecutiveFailures += 1
        let current = now()
        let since: Date
        if case .disconnected(_, let previous, _) = connection {
            since = previous
        } else {
            since = current
        }
        let retry = current.addingTimeInterval(Self.backoff(failures: consecutiveFailures, base: pollInterval, max: maxBackoff))
        connection = .disconnected(error: message, since: since, nextRetry: retry)
    }

    private func apply(status newStatus: StatusResponse, items newItems: [QueueItem]) {
        let hadSnapshot = status != nil
        let previousItems = items
        let previousDrive = driveState

        consecutiveFailures = 0
        let current = now()
        status = newStatus
        items = newItems
        lastRefresh = current
        if case .connected = connection {
            // keep the original connect time
        } else {
            connection = .connected(since: current)
        }

        if let selected = selectedItemID, !newItems.contains(where: { $0.id == selected }) {
            selectedItemID = nil
        }

        activeItems = newItems.filter(\.isActive).sorted { $0.id < $1.id }
        attentionItems = newItems.filter(\.needsAttention).sorted {
            $0.priorityRank == $1.priorityRank ? $0.id > $1.id : $0.priorityRank < $1.priorityRank
        }
        waitingItems = newItems.filter(\.isWaiting).sorted { $0.id < $1.id }
        recentlyCompleted = Array(
            newItems.filter(\.isCompleted).sorted { $0.updatedDate > $1.updatedDate }.prefix(5)
        )
        resources = (newStatus.scheduler?.resources ?? [:])
            .map { NamedResource(name: $0.key, status: $0.value) }
            .sorted { $0.name < $1.name }
        driveState = Self.driveState(from: newStatus)

        if hadSnapshot {
            let events = EventDetector.events(
                previousDrive: previousDrive,
                previousItems: previousItems,
                drive: driveState,
                items: newItems
            )
            lastEvents = events
            if !events.isEmpty {
                onEvents?(events)
            }
        }
        onSnapshot?()
    }

    static func driveState(from status: StatusResponse) -> DriveState {
        guard let drive = status.scheduler?.resources["drive"] else { return .unknown }
        if drive.used > 0 { return .busy(drive.holders) }
        if status.disc?.paused == true { return .paused }
        return .available
    }

    var attentionCount: Int { attentionItems.count }
}
