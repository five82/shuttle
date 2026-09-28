import Foundation
import Observation
import SwiftUI

/// Spindle's durable, queue-backed transitions for one item. Unlike the log
/// tail, the cursor is exclusive and the first request starts at zero so old
/// transitions remain visible after the daemon restarts or rotates its logs.
struct ItemEvent: Decodable, Identifiable, Sendable {
    let id: Int64
    let itemID: Int64
    let time: String
    let type: String
    let stage: Stage
    let taskId: Int64?
    let attempt: Int?
    let episodeKey: String?
    let substage: String?
    let message: String?
    let percent: Double?
    let durationSeconds: Double?

    private enum CodingKeys: String, CodingKey {
        case id, time, type, stage, taskId, attempt, episodeKey, substage, message, percent, durationSeconds
        case itemID = "itemId"
    }

    var timestamp: Date? { SpindleDate.parse(time) }

    var label: String {
        switch type {
        case "stage_start": return stage == .encoding ? "Worker reserved (may wait for input)" : "Started"
        case "stage_complete": return "Completed"
        case "stage_failed": return "Failed"
        case "stage_canceled": return "Canceled"
        case "stage_stopped": return "Stopped"
        case "stage_degraded": return "Degraded"
        case "encoding_substage": return substage?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Encoding"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct ItemEventBatch: Decodable, Sendable {
    let events: [ItemEvent]
    let next: Int64
}

/// Tails the item's journal only while its inspector tab is visible. Failed
/// requests retain the cursor and rows so reconnecting can catch up in order.
@Observable
@MainActor
final class ItemEventTailer {
    static let bufferLimit = 2000
    private(set) var events: [ItemEvent] = []
    private(set) var next: Int64 = 0
    private(set) var lastError: String?
    private(set) var isLoading = true

    let itemID: Int64
    private let clientProvider: SpindleMonitor.ClientProvider
    private let sleeper: SpindleMonitor.Sleeper
    private let pollInterval: TimeInterval
    private var task: Task<Void, Never>?
    private var generation = 0

    init(itemID: Int64, clientProvider: @escaping SpindleMonitor.ClientProvider,
         pollInterval: TimeInterval = 2,
         sleeper: @escaping SpindleMonitor.Sleeper = { try await Task.sleep(for: .seconds($0)) }) {
        self.itemID = itemID
        self.clientProvider = clientProvider
        self.pollInterval = pollInterval
        self.sleeper = sleeper
    }

    func start() {
        guard task == nil else { return }
        let generation = self.generation
        task = Task { [weak self] in
            while let self, !Task.isCancelled, self.generation == generation {
                await self.poll()
                do { try await self.sleeper(self.pollInterval) } catch { break }
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
    }

    func poll() async {
        let generation = self.generation
        guard let client = clientProvider() else {
            lastError = "Spindle address is not a valid URL."
            isLoading = false
            return
        }
        do {
            let batch = try await client.itemEvents(id: itemID, since: next)
            guard generation == self.generation else { return }
            let fresh = batch.events.filter { $0.itemID == itemID && $0.id > next }
            events.append(contentsOf: fresh)
            if events.count > Self.bufferLimit { events.removeFirst(events.count - Self.bufferLimit) }
            next = max(next, batch.next, fresh.last?.id ?? 0)
            lastError = nil
            isLoading = false
        } catch {
            guard generation == self.generation else { return }
            lastError = SpindleMonitor.describe(error)
            isLoading = false
        }
    }
}

/// A separate inspector tab, not an Overview section: event history is
/// independent of the fixed Overview skeleton and of volatile log entries.
struct ItemEventsView: View {
    @Environment(AppSettingsStore.self) private var settingsStore
    let itemID: Int64
    @State private var tailer: ItemEventTailer?

    var body: some View {
        Group {
            if let tailer, tailer.itemID == itemID {
                content(tailer)
            } else {
                ProgressView("Loading events…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: itemID) {
            tailer?.stop()
            let newTailer = ItemEventTailer(itemID: itemID, clientProvider: { settingsStore.makeClient() })
            tailer = newTailer
            newTailer.start()
        }
        .onDisappear {
            tailer?.stop()
            tailer = nil
        }
    }

    /// Preserve worker reservations in history, but label them honestly.
    static func visibleEvents(_ events: [ItemEvent]) -> [ItemEvent] { events }

    @ViewBuilder
    private func content(_ tailer: ItemEventTailer) -> some View {
        let visible = Self.visibleEvents(tailer.events)
        if let error = tailer.lastError, visible.isEmpty {
            ContentUnavailableView("Events Unavailable", systemImage: "clock.arrow.circlepath",
                                   description: Text(error))
        } else if tailer.isLoading {
            ProgressView("Loading events…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visible.isEmpty {
            ContentUnavailableView("No Stage Events", systemImage: "clock.arrow.circlepath",
                                   description: Text("No transitions have been recorded for this item yet."))
        } else {
            VStack(spacing: 0) {
                List(visible) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(event.stage.displayName).fontWeight(.medium)
                            Text(event.label)
                            Spacer()
                            if let date = event.timestamp {
                                Text(date, format: .dateTime.month().day().hour().minute().second())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(event.time).foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        if let detail = Self.detail(event) {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
                if let error = tailer.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).lineLimit(2)
                        .padding(8)
                }
            }
        }
    }

    static func detail(_ event: ItemEvent) -> String? {
        var parts: [String] = []
        if let task = event.taskId, task > 0 {
            parts.append("task \(task)" + (event.attempt.map { "/run \($0)" } ?? ""))
        }
        if let substage = event.substage, !substage.isEmpty { parts.append(substage) }
        if let key = event.episodeKey, !key.isEmpty { parts.append(key) }
        if let message = event.message, !message.isEmpty { parts.append(message) }
        if let percent = event.percent, percent > 0 { parts.append(String(format: "%.1f%%", percent)) }
        if let seconds = event.durationSeconds, seconds > 0 { parts.append(Format.duration(seconds)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
