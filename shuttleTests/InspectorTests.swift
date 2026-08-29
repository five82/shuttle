import XCTest
@testable import shuttle

final class InspectorTests: XCTestCase {
    func testEncodingDetailsDecodeFromCapturedItem() throws {
        let item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        let encoding = try XCTUnwrap(item.encodingDetails)
        XCTAssertEqual(encoding.encoder, "SVT-AV1")
        XCTAssertEqual(encoding.preset, "6")
        XCTAssertEqual(encoding.cropRequired, true)
        XCTAssertEqual(encoding.originalSize, 85_082_276_600)
        XCTAssertEqual(encoding.substage, "chunking")
        XCTAssertEqual(encoding.videoSummary, "3840x1600 HDR", "crop equals resolution, so no arrow")
        XCTAssertEqual(encoding.configSummary, "SVT-AV1 · Preset 6 · Tune 0")
        XCTAssertEqual(encoding.qualitySummary, "CVVDP target 9.35-9.75 JOD")
        XCTAssertNil(encoding.sizeResult)
        XCTAssertNil(encoding.sizeEstimate, "no estimate before 10%")
        XCTAssertNil(encoding.encodeStats)
        XCTAssertEqual(item.mediaType, "movie")
        XCTAssertEqual(item.tmdbID, 106646)
        XCTAssertFalse(item.isEpisodic)
        XCTAssertEqual(item.source?.summary, "The Wolf of Wall Street (2h 59m)")
        XCTAssertEqual(item.fileStateSummary, "RIP")
    }

    func testEncodingSummaries() {
        var encoding = EncodingDetails()
        encoding.resolution = "1920x1080"
        encoding.cropRequired = true
        encoding.cropFilter = "crop=1920:800:0:140"
        encoding.dynamicRange = "sdr"
        XCTAssertEqual(encoding.videoSummary, "1920x1080 → 1920x800 SDR (cropped)")

        encoding.originalSize = 40_000_000_000
        encoding.encodedSize = 8_000_000_000
        encoding.sizeReductionPercent = 80
        XCTAssertEqual(encoding.sizeResult, "40 GB → 8 GB (80% reduction)")

        encoding.encodedSize = nil
        encoding.percent = 42
        encoding.estimatedTotalBytes = 9_000_000_000
        encoding.currentOutputBytes = 3_000_000_000
        XCTAssertEqual(encoding.sizeEstimate, "~9 GB (3 GB written)")

        encoding.encodeDurationSeconds = 8_100
        encoding.averageSpeed = 3.14
        XCTAssertEqual(encoding.encodeStats, "2h 15m @ 3.1x avg")

        XCTAssertEqual(EncodingDetails.summarizeQuality("CRF 26 (UHD)"), "CRF 26 (UHD)")
        XCTAssertEqual(EncodingDetails.summarizeQuality("target 9.5 (initial CRF 26, CRF search 4-63)"), "target 9.5")
        XCTAssertEqual(EncodingDetails.summarizeQuality("plain"), "plain")
    }

    func testPipelineCellsFollowDaemonTemplate() throws {
        let status = try Fixtures.status()
        let item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        let cells = PipelineCell.cells(for: item, pipeline: status.pipelineStages)
        XCTAssertEqual(cells.map(\.stage), status.pipelineStages.map(\.stage))
        XCTAssertEqual(cells.first { $0.stage == .encoding }?.state, .running)
        XCTAssertEqual(cells.first { $0.stage == .ripping }?.state, .done)
        XCTAssertEqual(cells.first { $0.stage == .apply }?.state, .pending)
        XCTAssertTrue(cells.first { $0.stage == .encoding }!.message.hasPrefix("Phase 1/1"))
    }

    func testPipelineCellsFallBackToTaskOrderAndUnknownStages() throws {
        var item = try Fixtures.failedItem()
        let cells = PipelineCell.cells(for: item, pipeline: [])
        XCTAssertEqual(cells.map(\.stage), [.identification, .ripping, .encoding])
        XCTAssertEqual(cells.last?.state, .failed)
        XCTAssertEqual(cells.last?.attempts, 2)

        item.tasks = nil
        item.stage = .completed
        let template = [PipelineStageInfo(stage: .identification), PipelineStageInfo(stage: .unknown("polish"))]
        let completed = PipelineCell.cells(for: item, pipeline: template)
        XCTAssertEqual(completed.map(\.state), [.done, .done], "completed items with no tasks render every stage done")
        XCTAssertEqual(completed.last?.stage.displayName, "polish")
    }

    func testAttentionReasonPrefersFailedTask() throws {
        var item = try Fixtures.failedItem()
        XCTAssertEqual(item.attentionReason, "Encoding failed: reel: exit status 3")
        XCTAssertEqual(item.failedTask?.type, .encoding)

        item.tasks = nil
        XCTAssertEqual(item.attentionReason, "Encoding failed: reel: exit status 3", "falls back to item error + failedAtStage")

        item.errorMessage = nil
        XCTAssertEqual(item.attentionReason, "Encoding failed")

        item.failedAtStage = nil
        XCTAssertEqual(item.attentionReason, "Failed")

        let review = try XCTUnwrap(try Fixtures.queue().first { $0.id == 19 })
        XCTAssertTrue(review.attentionReason!.hasPrefix("final_validation:"))
    }

    func testEpisodeAssetStates() throws {
        let json = """
        {"key": "s01e03", "season": 1, "episode": 3, "stage": "encoding", "rippedPath": "/x/rip.mkv",
         "matchedEpisode": 3, "matchConfidence": 0.91}
        """
        var episode = try JSONDecoder().decode(Episode.self, from: Data(json.utf8))
        XCTAssertEqual(episode.label, "S01E03")
        XCTAssertEqual(episode.assetStates(active: true), [.done, .active, .pending, .pending])
        XCTAssertEqual(episode.assetStates(active: false), [.done, .pending, .pending, .pending])
        XCTAssertEqual(episode.mappingDescription, "matched E03 · 91% confidence")

        episode.status = "failed"
        XCTAssertTrue(episode.isFailed)
        XCTAssertEqual(episode.assetStates(active: true), [.done, .failed, .pending, .pending])

        episode.status = nil
        episode.encodedPath = "/x/enc.mkv"
        episode.subtitledPath = "/x/sub.mkv"
        episode.finalPath = "/lib/show/S01E03.mkv"
        XCTAssertEqual(episode.assetStates(active: false), [.done, .done, .done, .done])

        episode.episodeEnd = 4
        XCTAssertEqual(episode.label, "S01E03–04")

        let unknown = try JSONDecoder().decode(Episode.self, from: Data(#"{"key": "x", "season": 0, "episode": 0, "stage": "pending"}"#.utf8))
        XCTAssertEqual(unknown.label, "S??E??")
    }

    func testFinalPathCollapsesBatchesToDirectory() throws {
        var item = try Fixtures.failedItem()
        XCTAssertNil(item.finalPath)
        let one = try JSONDecoder().decode(Episode.self, from: Data(#"{"key": "a", "season": 1, "episode": 1, "stage": "completed", "finalPath": "/lib/Show/S01E01.mkv"}"#.utf8))
        let two = try JSONDecoder().decode(Episode.self, from: Data(#"{"key": "b", "season": 1, "episode": 2, "stage": "completed", "finalPath": "/lib/Show/S01E02.mkv"}"#.utf8))
        item.episodes = [one]
        XCTAssertEqual(item.finalPath, "/lib/Show/S01E01.mkv")
        item.episodes = [one, two]
        XCTAssertEqual(item.finalPath, "/lib/Show/")
        XCTAssertTrue(item.isEpisodic)
    }
}
