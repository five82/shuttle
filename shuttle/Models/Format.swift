import Foundation

/// The one place durations, ages, and percentages are turned into text, so
/// "43m left", "2h 10m", and "20s ago" read the same in every view.
enum Format {
    /// "1h 12m", "43m", "12s". Seconds are dropped once a minute is reached:
    /// an ETA with seconds implies precision the encoder does not have, and
    /// it would tick on every poll.
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    /// "just now" under ten seconds, then ten-second steps under a minute,
    /// then the duration form: "20s ago", "5m ago", "2h 10m ago".
    static func ago(_ date: Date, from now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date).rounded()))
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds / 10 * 10)s ago" }
        return "\(duration(Double(seconds))) ago"
    }

    /// Whole percent, floored so a running task never reads "100%".
    static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return "\(Int((clamped * 100).rounded(.down)))%"
    }

    /// "GPU", "encode slot", "drive" — a scheduler resource name as prose.
    static func resource(_ name: String) -> String {
        switch name.lowercased() {
        case "gpu": return "GPU"
        case "encode": return "encode slot"
        default: return name
        }
    }
}
