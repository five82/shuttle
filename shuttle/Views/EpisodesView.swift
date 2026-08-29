import SwiftUI

/// Per-episode asset progress for TV box sets: R/E/S/F for ripped,
/// encoded, subtitled, final. This is spindle's per-episode asset
/// vocabulary, not the pipeline stage list.
enum EpisodeAsset: CaseIterable {
    case ripped, encoded, subtitled, final

    var letter: String {
        switch self {
        case .ripped: return "R"
        case .encoded: return "E"
        case .subtitled: return "S"
        case .final: return "F"
        }
    }

    var title: String {
        switch self {
        case .ripped: return "Ripped"
        case .encoded: return "Encoded"
        case .subtitled: return "Subtitled"
        case .final: return "Final"
        }
    }
}

enum EpisodeAssetState: Equatable {
    case pending, done, failed, active
}

extension Episode {
    var isFailed: Bool {
        status?.lowercased() == "failed" || stage.lowercased() == "failed"
    }

    /// "S02E04" or "S02E04–05".
    var label: String {
        guard season != 0 || episode != 0 else { return "S??E??" }
        var value = String(format: "S%02dE%02d", season, episode)
        if let end = episodeEnd, end > episode { value += String(format: "–%02d", end) }
        return value
    }

    /// A column is done when its path exists; the first empty column after
    /// the last done one is "next", which is failed or active depending on
    /// the episode; everything else is pending.
    func assetStates(active: Bool) -> [EpisodeAssetState] {
        let paths = [rippedPath, encodedPath, subtitledPath, finalPath]
            .map { ($0 ?? "").trimmingCharacters(in: .whitespaces) }
        var states = paths.map { $0.isEmpty ? EpisodeAssetState.pending : .done }
        let next = (states.lastIndex(of: .done) ?? -1) + 1
        if next < states.count {
            if isFailed {
                states[next] = .failed
            } else if active {
                states[next] = .active
            }
        }
        return states
    }

    /// Only when the match tells the operator something: it differs from
    /// the planned number, or confidence is below the review threshold.
    func mappingDescription(threshold: Double?) -> String? {
        guard let matched = matchedEpisode, matched > 0 else { return nil }
        let differs = matched != episode || (matchedEpisodeEnd ?? 0) != (episodeEnd ?? 0)
        let low = matchConfidence.map { $0 < (threshold ?? 0.8) } ?? false
        guard differs || low else { return nil }
        var value = "matched E\(String(format: "%02d", matched))"
        if let end = matchedEpisodeEnd, end > matched { value += String(format: "–%02d", end) }
        if let confidence = matchConfidence, confidence > 0 {
            value += String(format: " · %.0f%% confidence", confidence * 100)
        }
        return value
    }

    var mappingDescription: String? { mappingDescription(threshold: nil) }

    /// "en · opensubtitles" or "en · 2 issues".
    var subtitleDescription: String? {
        var parts: [String] = []
        if let language = subtitleLanguage, !language.isEmpty { parts.append(language) }
        let issues = (subtitleSevereIssues ?? []) + (subtitleReviewIssues ?? [])
        if !issues.isEmpty {
            parts.append(issues.count == 1 ? issues[0] : "\(issues.count) subtitle issues")
        } else if let source = subtitleSource, !source.isEmpty {
            parts.append(source.lowercased())
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct EpisodesView: View {
    let item: QueueItem

    /// What the four letters on every row mean, once, at the top.
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(EpisodeAsset.allCases, id: \.letter) { asset in
                HStack(spacing: 3) {
                    Text(asset.letter)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                    Text(asset.title.lowercased())
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: R ripped, E encoded, S subtitled, F final")
    }

    var body: some View {
        if item.episodeList.isEmpty {
            ContentUnavailableView("No Episodes", systemImage: "tv", description: Text("This item has no episode plan yet."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let totals = item.episodeTotals {
                        Text("\(totals.planned) planned · \(totals.ripped) ripped · \(totals.encoded) encoded · \(totals.final) final")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    legend
                        .padding(.bottom, 4)
                    ForEach(item.episodeList) { episode in
                        EpisodeRow(episode: episode, active: episode.active == true, threshold: item.contentId?.reviewThreshold)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let active: Bool
    var threshold: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(episode.label)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(episode.isFailed ? .red : (episode.needsReview == true ? .orange : .primary))
                    .frame(width: 84, alignment: .leading)
                Text(episode.title ?? episode.sourceTitle ?? episode.outputBasename ?? "")
                    .lineLimit(1)
                Spacer()
                if let runtime = episode.runtimeSeconds, runtime > 0 {
                    Text(Format.duration(Double(runtime)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                assetGrid
            }
            let details = [episode.mappingDescription(threshold: threshold), episode.subtitleDescription, episode.reviewReason, episode.errorMessage]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(episode.isFailed || episode.needsReview == true ? .orange : .secondary)
                    .padding(.leading, 92)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var assetGrid: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip(EpisodeAsset.allCases, episode.assetStates(active: active))), id: \.0) { asset, state in
                HStack(spacing: 1) {
                    Text(asset.letter)
                    Image(systemName: symbol(for: state))
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(tint(for: state))
                .help("\(asset.title): \(String(describing: state))")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(asset.title) \(String(describing: state))")
            }
        }
    }

    private func symbol(for state: EpisodeAssetState) -> String {
        switch state {
        case .done: return "checkmark"
        case .failed: return "xmark"
        case .active: return "circle.fill"
        case .pending: return "circle"
        }
    }

    private func tint(for state: EpisodeAssetState) -> Color {
        switch state {
        case .done: return .green
        case .failed: return .red
        case .active: return .accentColor
        case .pending: return .secondary
        }
    }
}
