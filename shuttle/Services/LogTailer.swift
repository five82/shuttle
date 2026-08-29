import Foundation
import Observation

/// Tails `GET /api/logs` for one view: an initial tail window, then
/// cursor-driven catch-up on a fixed cadence. One instance per visible log
/// view; stopped when the view disappears. Filters that the daemon applies
/// (level, item, daemon-only) restart the tail; text search is local.
@Observable
@MainActor
final class LogTailer {
    static let initialWindow = 200
    static let catchUpLimit = 500
    static let bufferLimit = 2000

    private(set) var entries: [LogEntry] = []
    private(set) var next: UInt64 = 0
    private(set) var lastError: String?
    private(set) var isRunning = false

    var itemID: Int64? { didSet { if oldValue != itemID { restart() } } }
    var minimumLevel: LogLevel = .info { didSet { if oldValue != minimumLevel { restart() } } }
    var daemonOnly = false { didSet { if oldValue != daemonOnly { restart() } } }

    let pollInterval: TimeInterval
    private let clientProvider: SpindleMonitor.ClientProvider
    private let sleeper: SpindleMonitor.Sleeper
    private var task: Task<Void, Never>?
    private var generation = 0

    init(
        clientProvider: @escaping SpindleMonitor.ClientProvider,
        itemID: Int64? = nil,
        pollInterval: TimeInterval = 2,
        sleeper: @escaping SpindleMonitor.Sleeper = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.clientProvider = clientProvider
        self.itemID = itemID
        self.pollInterval = pollInterval
        self.sleeper = sleeper
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        let generation = self.generation
        task = Task { [weak self] in
            while let self, !Task.isCancelled, self.generation == generation {
                await self.poll()
                try? await self.sleeper(self.pollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Clears the buffer and re-fetches the tail window with current filters.
    func restart() {
        let wasRunning = task != nil
        stop()
        generation += 1
        entries = []
        next = 0
        lastError = nil
        if wasRunning { start() }
    }

    var query: LogQuery {
        var query = LogQuery(itemID: itemID, minimumLevel: minimumLevel, daemonOnly: daemonOnly)
        if next == 0 {
            query.limit = Self.initialWindow
            query.tail = true
        } else {
            query.since = next
            query.limit = Self.catchUpLimit
        }
        return query
    }

    /// One fetch. Public so tests and the item tab can drive it directly.
    func poll() async {
        guard let client = clientProvider() else {
            lastError = "Spindle address is not a valid URL."
            return
        }
        let request = query
        let generation = self.generation
        do {
            let response = try await client.logs(request)
            guard generation == self.generation else { return }
            apply(response)
        } catch {
            guard generation == self.generation else { return }
            lastError = SpindleMonitor.describe(error)
        }
    }

    private func apply(_ response: LogsResponse) {
        lastError = nil
        if !response.events.isEmpty {
            let known = next
            entries.append(contentsOf: response.events.filter { $0.seq >= known })
            if entries.count > Self.bufferLimit {
                entries.removeFirst(entries.count - Self.bufferLimit)
            }
        }
        next = max(next, response.next)
    }
}
