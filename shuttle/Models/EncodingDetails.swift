import Foundation

/// Typed view of the item's `encoding` blob (spindle's encodingstate
/// snapshot, flat snake_case). Decoded on demand from `QueueItem.encoding`.
struct EncodingDetails: Codable, Hashable, Sendable {
    var percent: Double?
    var etaSeconds: Double?
    var fps: Double?
    var currentFrame: Int64?
    var totalFrames: Int64?
    var currentOutputBytes: Int64?
    var estimatedTotalBytes: Int64?
    var substage: String?
    var inputFile: String?
    var resolution: String?
    var dynamicRange: String?
    var encoder: String?
    var preset: String?
    var quality: String?
    var tune: String?
    var audioCodec: String?
    var cropFilter: String?
    var cropRequired: Bool?
    var cropMessage: String?
    var originalSize: Int64?
    var encodedSize: Int64?
    var sizeReductionPercent: Double?
    var averageSpeed: Double?
    var encodeDurationSeconds: Double?
    var warning: String?
    var error: EncodingIssue?
    var validation: EncodingValidation?

    /// "3840x1600 -> 3840x1500 HDR (cropped)" or "3840x1600 HDR".
    var videoSummary: String? {
        guard let resolution, !resolution.isEmpty else { return nil }
        var cropped: String?
        if cropRequired == true, let filter = cropFilter, filter.hasPrefix("crop=") {
            let dims = filter.dropFirst("crop=".count).split(separator: ":", maxSplits: 2)
            if dims.count >= 2 { cropped = "\(dims[0])x\(dims[1])" }
        }
        var parts: [String] = []
        if let cropped, cropped != resolution {
            parts.append("\(resolution) → \(cropped)")
        } else {
            parts.append(resolution)
        }
        if let range = dynamicRange, !range.isEmpty { parts.append(range.uppercased()) }
        if let cropped, cropped != resolution { parts.append("(cropped)") }
        return parts.joined(separator: " ")
    }

    /// "SVT-AV1 · Preset 6 · Tune 0"
    var configSummary: String? {
        guard let preset, !preset.isEmpty else { return nil }
        var parts: [String] = []
        if let encoder, !encoder.isEmpty { parts.append(encoder) }
        parts.append("Preset \(preset)")
        if let tune, !tune.isEmpty { parts.append("Tune \(tune)") }
        return parts.joined(separator: " · ")
    }

    /// Reel's quality string without the CRF-search machinery parenthetical.
    var qualitySummary: String? {
        guard let quality = quality?.trimmingCharacters(in: .whitespaces), !quality.isEmpty else { return nil }
        return Self.summarizeQuality(quality)
    }

    static func summarizeQuality(_ quality: String) -> String {
        let trimmed = quality.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "("), open != trimmed.startIndex else {
            return trimmed
        }
        let parenthetical = trimmed[open...]
        for marker in ["initial CRF", "CRF search", "metric workers"] where parenthetical.contains(marker) {
            return trimmed[..<open].trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    /// "79.2 GB → 12.1 GB (85% reduction)" once the encode finished.
    var sizeResult: String? {
        guard let originalSize, originalSize > 0, let encodedSize, encodedSize > 0 else { return nil }
        var value = "\(Self.bytes(originalSize)) → \(Self.bytes(encodedSize))"
        if let reduction = sizeReductionPercent, reduction > 0 {
            value += " (\(Int(reduction.rounded()))% reduction)"
        }
        return value
    }

    /// "~12.1 GB (3.2 GB written)" while encoding, after 10% for accuracy.
    var sizeEstimate: String? {
        guard (percent ?? 0) >= 10, let estimate = estimatedTotalBytes, estimate > 0, (encodedSize ?? 0) <= 0 else { return nil }
        var value = "~\(Self.bytes(estimate))"
        if let written = currentOutputBytes, written > 0 {
            value += " (\(Self.bytes(written)) written)"
        }
        return value
    }

    /// "2h 14m @ 3.1x avg"
    var encodeStats: String? {
        var parts: [String] = []
        if let seconds = encodeDurationSeconds, seconds > 0 {
            parts.append(Self.duration(seconds))
        }
        if let speed = averageSpeed, speed > 0 {
            parts.append(String(format: "%.1fx avg", speed))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " @ ")
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(total % 60)s" }
        return "\(total)s"
    }
}

struct EncodingIssue: Codable, Hashable, Sendable {
    var title: String?
    var message: String?
    var context: String?
    var suggestion: String?
}

struct EncodingValidation: Codable, Hashable, Sendable {
    var passed: Bool?
    var steps: [EncodingValidationStep]?

    var stepList: [EncodingValidationStep] { steps ?? [] }
    var passedCount: Int { stepList.filter { $0.passed == true }.count }
}

struct EncodingValidationStep: Codable, Hashable, Sendable, Identifiable {
    var name: String?
    var passed: Bool?
    var details: String?

    var id: String { (name ?? "") + (details ?? "") }
}

extension QueueItem {
    /// Decodes the raw `encoding` blob. Small enough to do on demand.
    var encodingDetails: EncodingDetails? {
        guard let encoding, encoding != .null else { return nil }
        guard let data = try? JSONEncoder().encode(encoding) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(EncodingDetails.self, from: data)
    }

    var mediaType: String? {
        metadata?["media_type"]?.stringValue
    }

    var tmdbID: Int? {
        metadata?["id"]?.intValue
    }

    var episodeList: [Episode] { episodes ?? [] }

    /// TV or a multi-episode batch. Movies carry a single internal "main"
    /// episode that has no list value of its own.
    var isEpisodic: Bool {
        episodeList.count > 1 || mediaType == "tv"
    }

    var failedTask: PipelineTask? {
        taskList.first { $0.state == .failed }
    }

    /// Where finished files landed: the file for single-file items, the
    /// shared directory once a batch has several.
    var finalPath: String? {
        let paths = episodeList.compactMap { $0.finalPath?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = paths.first else { return nil }
        return paths.count > 1 ? (first as NSString).deletingLastPathComponent + "/" : first
    }

    /// "RIP ENC FIN" — which artifacts exist, from the episode totals.
    var fileStateSummary: String? {
        guard let totals = episodeTotals else { return nil }
        var parts: [String] = []
        if totals.ripped > 0 { parts.append("RIP") }
        if totals.encoded > 0 { parts.append("ENC") }
        if totals.final > 0 { parts.append("FIN") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

extension SourceTitle {
    /// "The Wolf of Wall Street (2h 59m)" or "Title 02 (1h 58m)".
    var summary: String? {
        var value = name?.trimmingCharacters(in: .whitespaces) ?? ""
        if value.isEmpty, titleId > 0 { value = String(format: "Title %02d", titleId) }
        guard !value.isEmpty else { return nil }
        if let seconds = durationSeconds, seconds > 0 {
            value += " (\(EncodingDetails.duration(Double(seconds))))"
        }
        return value
    }
}
