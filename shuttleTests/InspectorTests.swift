import XCTest
@testable import shuttle

@MainActor
final class InspectorTests: XCTestCase {
    func testDependenciesSearchAndOrderBySeverity() {
        let available = DependencyStatus(name: "Encoder", command: "reel", description: "Video", optional: false, available: true, detail: nil)
        let optional = DependencyStatus(name: "Subtitles", command: "sub", description: "Optional tool", optional: true, available: false, detail: "not installed")
        let requiredA = DependencyStatus(name: "Disc", command: "discinfo", description: "Reads discs", optional: false, available: false, detail: "missing")
        let requiredB = DependencyStatus(name: "Probe", command: "ffprobe", description: "Checks files", optional: false, available: false, detail: nil)
        let dependencies = [available, optional, requiredA, requiredB]

        XCTAssertEqual(DependenciesView.visibleDependencies(dependencies, filter: "").map(\.name), ["Disc", "Probe", "Subtitles", "Encoder"])
        XCTAssertEqual(DependenciesView.visibleDependencies(dependencies, filter: "  MISSING  ").map(\.name), ["Disc"])
        XCTAssertEqual(DependenciesView.visibleDependencies(dependencies, filter: "DISCINFO").map(\.name), ["Disc"])
        XCTAssertEqual(DependenciesView.visibleDependencies(dependencies, filter: "video").map(\.name), ["Encoder"])
        XCTAssertEqual(DependenciesView.visibleDependencies(dependencies, filter: "not installed").map(\.name), ["Subtitles"])
        XCTAssertTrue(DependenciesView.visibleDependencies(dependencies, filter: "unrelated").isEmpty)
    }

    func testAttentionAndNowSearchVisibleItems() throws {
        let items = try Fixtures.queue()
        let review = try XCTUnwrap(items.first { $0.id == 19 })
        let running = try XCTUnwrap(items.first { $0.id == 21 })
        let selection = [review, running]

        XCTAssertEqual(AttentionView.matchingItems(selection, filter: " ").map(\.id), [19, 21])
        XCTAssertEqual(AttentionView.matchingItems(selection, filter: "  AUDIO STREAM ").map(\.id), [19])
        XCTAssertEqual(NowView.matchingItems(selection, filter: " #21 ").map(\.id), [21])
        XCTAssertTrue(NowView.matchingItems(selection, filter: "no matching title").isEmpty)
    }

    func testNowRowTextUsesElapsedTimeOnlyForSilentSingleTask() throws {
        let item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var progress = try XCTUnwrap(item.progress)
        progress.message = ""
        progress.startedAt = now.addingTimeInterval(-245)
        XCTAssertEqual(NowRowText.activeDetail(item: item, progress: [progress], at: now), "Encoding · started 4m ago")

        progress.startedAt = now.addingTimeInterval(-0.5)
        XCTAssertEqual(NowRowText.activeDetail(item: item, progress: [progress], at: now), item.activityDescription)
        progress.startedAt = nil
        XCTAssertEqual(NowRowText.activeDetail(item: item, progress: [progress], at: now), item.activityDescription)
        progress.message = "Working"
        XCTAssertEqual(NowRowText.activeDetail(item: item, progress: [progress], at: now), item.activityDescription)
        XCTAssertEqual(NowRowText.activeDetail(item: item, progress: [], at: now), item.activityDescription)
        XCTAssertEqual(NowRowText.activeDetail(item: item, progress: [progress, progress], at: now), item.activityDescription, "overlapping tasks keep the combined activity description")
    }

    func testNowWaitingTextNamesNextTaskRatherThanCoarseItemStage() throws {
        var item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 22 })
        item.stage = .ripping
        XCTAssertEqual(NowRowText.waitingText(item: item, reason: nil), "queued for ripping")
        XCTAssertEqual(NowRowText.waitingText(item: item, reason: .resource(next: .encoding, name: "gpu", holders: [])), "Encoding · GPU busy")
        XCTAssertEqual(NowRowText.waitingText(item: item, reason: .dependency(next: .analysis, on: .encoding)), "Analysis · after Encoding")
        XCTAssertEqual(NowRowText.waitingText(item: item, reason: .ready(next: .subtitling)), "Subtitling · next up")
    }

    func testNowIdleExplanationUsesDriveAndDrainingState() {
        XCTAssertEqual(NowView.idleMessage(drive: .available, draining: false).symbol, "opticaldisc")
        XCTAssertTrue(NowView.idleMessage(drive: .available, draining: false).text.contains("insert a disc"))
        XCTAssertTrue(NowView.idleMessage(drive: .paused, draining: false).text.contains("paused"))
        XCTAssertEqual(NowView.idleMessage(drive: .busy([]), draining: false).text, "Nothing running.")
        XCTAssertEqual(NowView.idleMessage(drive: .unknown, draining: false).text, "Nothing running.")
        XCTAssertTrue(NowView.idleMessage(drive: .available, draining: true).text.contains("draining"), "draining outranks drive availability")
    }

    func testMenuBarHealthPriorityAndFirstLaunchState() throws {
        let connected = ConnectionState.connected(since: .distantPast)
        let disconnected = ConnectionState.disconnected(error: "offline", since: .distantPast, nextRetry: .distantFuture)
        var status = try Fixtures.status()
        XCTAssertEqual(MenuBarView.healthState(connection: connected, status: status, issue: nil, placeholder: false), .normal)
        status.draining = true
        XCTAssertEqual(MenuBarView.healthState(connection: connected, status: status, issue: nil, placeholder: false), .draining)
        XCTAssertEqual(MenuBarView.healthState(connection: connected, status: status, issue: "error", placeholder: false), .error)
        status.running = false
        XCTAssertEqual(MenuBarView.healthState(connection: connected, status: status, issue: "error", placeholder: false), .stopped)
        XCTAssertEqual(MenuBarView.healthState(connection: .connecting, status: status, issue: "error", placeholder: true), .connecting)
        XCTAssertEqual(MenuBarView.healthState(connection: disconnected, status: status, issue: "error", placeholder: true), .setAddress)
        XCTAssertEqual(MenuBarView.healthState(connection: disconnected, status: status, issue: "error", placeholder: false), .disconnected)
    }

    func testMenuBarIdleExplanation() {
        XCTAssertEqual(MenuBarView.idleText(drive: .available, draining: false), "Nothing running.")
        XCTAssertEqual(MenuBarView.idleText(drive: .busy([]), draining: false), "Nothing running.")
        XCTAssertEqual(MenuBarView.idleText(drive: .paused, draining: false), "Nothing running — disc monitor paused.")
        XCTAssertEqual(MenuBarView.idleText(drive: .paused, draining: true), "Nothing running — daemon draining.")
    }

    func testInspectorStatusWordingForEveryItemState() throws {
        let items = try Fixtures.queue()
        let failed = try Fixtures.failedItem()
        let review = try XCTUnwrap(items.first { $0.id == 19 })
        let active = try XCTUnwrap(items.first { $0.id == 21 })
        let waiting = try XCTUnwrap(items.first { $0.id == 22 })
        let completed = try XCTUnwrap(items.first { $0.id == 1 })
        let blocked = WaitReason.resource(next: .encoding, name: "gpu", holders: [ResourceHolder(itemId: 21, task: .encoding)])

        XCTAssertEqual(ItemInspectorView.stageLabel(failed, reason: blocked), "Failed")
        XCTAssertEqual(ItemInspectorView.stageHelp(failed, reason: blocked), failed.attentionReason)
        XCTAssertEqual(ItemInspectorView.stageLabel(review, reason: blocked), "Review")
        XCTAssertEqual(ItemInspectorView.stageHelp(review, reason: blocked), review.attentionReason)
        XCTAssertEqual(ItemInspectorView.stageLabel(active, reason: blocked), "Encoding", "running task wins over a stale wait reason")
        XCTAssertEqual(ItemInspectorView.stageHelp(active, reason: blocked), active.activityDescription)
        XCTAssertEqual(ItemInspectorView.stageLabel(waiting, reason: blocked), "Queued · GPU busy")
        XCTAssertEqual(ItemInspectorView.stageHelp(waiting, reason: blocked), blocked.detail)
        XCTAssertEqual(ItemInspectorView.stageLabel(waiting, reason: nil), "Queued · \(waiting.stage.displayName)")
        XCTAssertEqual(ItemInspectorView.stageHelp(waiting, reason: nil), waiting.stage.displayName)
        XCTAssertEqual(ItemInspectorView.stageLabel(completed, reason: nil), "Completed")
        XCTAssertEqual(ItemInspectorView.stageHelp(completed, reason: nil), completed.stage.displayName)
    }

    func testQueueStageColumnUsesTasksAndWaitingReasons() throws {
        let items = try Fixtures.queue()
        let failed = try Fixtures.failedItem()
        let review = try XCTUnwrap(items.first { $0.id == 19 })
        let running = try XCTUnwrap(items.first { $0.id == 21 })
        let waiting = try XCTUnwrap(items.first { $0.id == 22 })
        let completed = try XCTUnwrap(items.first { $0.id == 1 })
        let reason = WaitReason.resource(next: .encoding, name: "gpu", holders: [ResourceHolder(itemId: 21, task: .encoding)])

        let failureLabel = QueueStagePresentation(item: failed, reason: nil)
        XCTAssertEqual(failureLabel.text, "Failed")
        XCTAssertEqual(failureLabel.help, failed.attentionReason)
        let reviewLabel = QueueStagePresentation(item: review, reason: nil)
        XCTAssertEqual(reviewLabel.text, "Review")
        XCTAssertEqual(reviewLabel.help, review.attentionReason)
        let waitingLabel = QueueStagePresentation(item: waiting, reason: reason)
        XCTAssertEqual(waitingLabel.text, "Queued · \(reason.short)")
        XCTAssertEqual(waitingLabel.help, reason.detail)
        let unblocked = QueueStagePresentation(item: waiting, reason: nil)
        XCTAssertEqual(unblocked.text, "Queued · \(waiting.stage.displayName)")
        XCTAssertEqual(unblocked.help, "Queued for \(waiting.stage.displayName)")
        let doneLabel = QueueStagePresentation(item: completed, reason: nil)
        XCTAssertEqual(doneLabel.text, "Completed")
        XCTAssertEqual(doneLabel.help, completed.stage.displayName)

        var overlapping = running
        overlapping.stage = .ripping // scheduler lags behind the live encoding task
        let activeLabel = QueueStagePresentation(item: overlapping, reason: reason)
        XCTAssertEqual(activeLabel.text, "Encoding")
        XCTAssertEqual(activeLabel.help, overlapping.activityDescription)
        overlapping.tasks = [
            PipelineTask(type: .encoding, state: .running, progress: TaskProgress(percent: 25, message: "")),
            PipelineTask(type: .subtitling, state: .running, progress: TaskProgress(percent: 10, message: "")),
        ]
        XCTAssertEqual(QueueStagePresentation(item: overlapping, reason: nil).text, "Encoding + Subtitling")
    }

    func testInspectorReasonPrefixSplit() {
        let split = ReasonRow.split("final_validation: main: audio stream 0 duration mismatch")
        XCTAssertEqual(split.0, "final_validation · main")
        XCTAssertEqual(split.1, "audio stream 0 duration mismatch")
        for reason in ["Read failed: try again", "prefix: ", "plain text", "too_long_to_be_a_reason_prefix_token_here: explanation"] {
            let value = ReasonRow.split(reason)
            XCTAssertNil(value.0)
            XCTAssertEqual(value.1, reason)
        }
    }

    func testMenuBarIconReflectsConnectionAndDrive() {
        let connected = ConnectionState.connected(since: .distantPast)
        let disconnected = ConnectionState.disconnected(error: "offline", since: .distantPast, nextRetry: .distantFuture)
        XCTAssertEqual(MenuBarLabel.symbol(connection: .connecting, hasSnapshot: false, drive: .available), "circle.dotted")
        XCTAssertEqual(MenuBarLabel.symbol(connection: disconnected, hasSnapshot: false, drive: .available), "circle.dotted")
        XCTAssertEqual(MenuBarLabel.symbol(connection: disconnected, hasSnapshot: true, drive: .busy([])), "antenna.radiowaves.left.and.right.slash")
        XCTAssertEqual(MenuBarLabel.symbol(connection: connected, hasSnapshot: true, drive: .unknown), "circle.dotted")
        XCTAssertEqual(MenuBarLabel.symbol(connection: connected, hasSnapshot: true, drive: .available), "opticaldisc")
        XCTAssertEqual(MenuBarLabel.symbol(connection: connected, hasSnapshot: true, drive: .busy([])), "opticaldisc.fill")
        XCTAssertEqual(MenuBarLabel.symbol(connection: connected, hasSnapshot: true, drive: .paused), "pause.circle")
    }

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
        XCTAssertEqual(item.fileStateSummary, "Ripped")
    }

    func testFileStateSummaryWording() throws {
        var item = try Fixtures.failedItem()
        item.episodeTotals = EpisodeTotals(planned: 1, ripped: 1, encoded: 1, final: 1)
        XCTAssertEqual(item.fileStateSummary, "Ripped · Encoded · Final")
        item.episodeTotals = EpisodeTotals(planned: 8, ripped: 8, encoded: 3, final: 0)
        XCTAssertEqual(item.fileStateSummary, "Ripped 8 · Encoded 3")
        item.episodeTotals = EpisodeTotals(planned: 2, ripped: 0, encoded: 0, final: 0)
        XCTAssertNil(item.fileStateSummary)
    }

    func testItemProgressFromRunningEncode() throws {
        var item = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        var progress = try XCTUnwrap(item.progress)
        XCTAssertEqual(progress.stage, .encoding)
        XCTAssertFalse(progress.hasStarted, "the capture had no percent yet")
        XCTAssertEqual(progress.shortText, "Starting…")
        XCTAssertEqual(progress.detailText, "Starting…")
        XCTAssertNil(progress.etaText)

        item.encoding = .object([
            "percent": .number(66.4), "eta_seconds": .number(2572), "average_speed": .number(1.3177),
            "current_frame": .number(177_507), "total_frames": .number(258_775),
        ])
        progress = try XCTUnwrap(item.progress)
        XCTAssertEqual(progress.fraction, 0.664, accuracy: 0.001, "falls back to the encoder's percent when the task reports 0")
        XCTAssertEqual(progress.shortText, "66% · 42m left")
        XCTAssertEqual(progress.detailText, "66% · 1.3x · 177,507 / 258,775 frames · 42m left")
        XCTAssertEqual(progress.accessibilityText, "Encoding, 66 percent, 42m left")

        let started = try XCTUnwrap(item.tasks?.first { $0.type == .encoding }?.startedDate)
        XCTAssertEqual(progress.elapsedText(at: started.addingTimeInterval(125)), "2m")

        item.tasks = nil
        XCTAssertNil(item.progress, "no running task, no progress")
    }

    func testItemProgressPrefersByteCountsForRips() throws {
        var item = try Fixtures.failedItem()
        item.tasks = [PipelineTask(type: .ripping, state: .running, progress: TaskProgress(percent: 25, message: "Copying", bytesCopied: 10_000_000_000, totalBytes: 40_000_000_000))]
        let progress = try XCTUnwrap(item.progress)
        XCTAssertEqual(progress.shortText, "10 GB / 40 GB")
        XCTAssertEqual(progress.detailText, "25% · 10 GB / 40 GB")
    }

    func testPipelineRowProgressDurationAndNotePriorities() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var cell = PipelineCell(stage: .encoding, state: .running, percent: 0, message: "", error: nil, attempts: 0, startedAt: nil, finishedAt: nil)
        XCTAssertEqual(cell.trailing(progress: nil, at: now), "running")
        cell.percent = 49.6
        XCTAssertEqual(cell.trailing(progress: nil, at: now), "50%")
        let active = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        let progress = try XCTUnwrap(active.progress)
        XCTAssertEqual(cell.trailing(progress: progress, at: now), progress.shortText, "task progress takes precedence over raw percent")
        cell.percent = 0
        cell.startedAt = now.addingTimeInterval(-90)
        XCTAssertEqual(cell.trailing(progress: nil, at: now), "1m")
        cell.message = "Encoding frame 42"
        cell.attempts = 3
        XCTAssertEqual(cell.note, "Encoding frame 42")

        cell.state = .failed
        cell.error = "reel exited"
        XCTAssertEqual(cell.note, "reel exited")
        cell.state = .done
        cell.finishedAt = now.addingTimeInterval(-30)
        cell.flagged = true
        XCTAssertEqual(cell.trailing(progress: nil, at: now), "1m")
        XCTAssertEqual(cell.note, "Routed to review")
        cell.flagged = false
        XCTAssertEqual(cell.note, "3 attempts")
        cell.attempts = 1
        XCTAssertNil(cell.note)
        cell.startedAt = nil
        XCTAssertEqual(cell.trailing(progress: nil, at: now), "")
    }

    func testPipelineCellsCarryTimingAndReviewFlag() throws {
        let status = try Fixtures.status()
        let review = try XCTUnwrap(try Fixtures.queue().first { $0.id == 19 })
        let cells = PipelineCell.cells(for: review, pipeline: status.pipelineStages)
        XCTAssertEqual(cells.filter(\.flagged).map(\.stage), [.organizing], "the stage that routed to review is flagged")

        let running = try XCTUnwrap(try Fixtures.queue().first { $0.id == 21 })
        let ripping = try XCTUnwrap(PipelineCell.cells(for: running, pipeline: status.pipelineStages).first { $0.stage == .ripping })
        XCTAssertNotNil(ripping.startedAt)
        XCTAssertNotNil(ripping.finishedAt)
        XCTAssertEqual(ripping.duration(at: .distantFuture), ripping.finishedAt!.timeIntervalSince(ripping.startedAt!))
        let encoding = try XCTUnwrap(PipelineCell.cells(for: running, pipeline: status.pipelineStages).first { $0.stage == .encoding })
        XCTAssertEqual(encoding.duration(at: encoding.startedAt!.addingTimeInterval(90)), 90, "running stages measure to now")
        XCTAssertFalse(PipelineCell.cells(for: running, pipeline: status.pipelineStages).contains(where: \.flagged))
    }

    func testSearchableTextIncludesAttentionReason() throws {
        let review = try XCTUnwrap(try Fixtures.queue().first { $0.id == 19 })
        XCTAssertTrue(review.searchableText.contains("audio stream"))
        XCTAssertTrue(review.searchableText.contains("#19"))
        XCTAssertEqual(review.mediaTypeLabel, "Movie")
    }

    func testInspectorContentIdentificationSummary() throws {
        var content = try JSONDecoder().decode(ContentIdentification.self, from: Data("{}".utf8))
        XCTAssertEqual(content.inspectorSummary, "")
        content.method = "audio fingerprint"
        XCTAssertEqual(content.inspectorSummary, "audio fingerprint")
        content.transcribedEpisodes = 2
        content.matchedEpisodes = 1
        content.unresolvedEpisodes = 1
        content.lowConfidenceCount = 1
        content.referenceSource = "TMDB"
        content.referenceEpisodes = 8
        XCTAssertEqual(content.inspectorSummary, "audio fingerprint · 1 matched · 1 unresolved · 1 low confidence · ref TMDB (8 episodes)")
        content.referenceEpisodes = 0
        XCTAssertTrue(content.inspectorSummary.hasSuffix("· ref TMDB"))
        content.method = ""
        XCTAssertEqual(content.inspectorSummary, "", "a source alone is not an identification method")
    }

    func testInspectorSubtitleSummaryCountsSourcesInStableOrder() throws {
        var item = try Fixtures.failedItem()
        XCTAssertEqual(item.inspectorSubtitleSummary, "")
        var first = try JSONDecoder().decode(Episode.self, from: Data(#"{"key":"a", "season":1, "episode":1, "stage":"pending"}"#.utf8))
        first.subtitleSource = "OpenSubtitles"
        item.episodes = [first]
        XCTAssertEqual(item.inspectorSubtitleSummary, "opensubtitles")
        var second = first
        second.key = "b"
        second.subtitleSource = "LOCAL"
        var third = first
        third.key = "c"
        third.subtitleSource = "opensubtitles"
        item.episodes = [first, second, third]
        XCTAssertEqual(item.inspectorSubtitleSummary, "1 local · 2 opensubtitles")
        third.subtitleSource = nil
        item.episodes = [first, second, third]
        XCTAssertEqual(item.inspectorSubtitleSummary, "1 local · 1 opensubtitles", "counts are per source, not total episode count")
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
        XCTAssertNil(episode.mappingDescription, "a confident match to the planned number says nothing new")
        XCTAssertEqual(episode.mappingDescription(threshold: 0.95), "matched E03 · 91% confidence", "below the daemon's review threshold it is worth showing")
        episode.matchedEpisode = 4
        XCTAssertEqual(episode.mappingDescription, "matched E04 · 91% confidence", "a different number always shows")
        episode.matchedEpisode = 3

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

    func testEpisodeMappingRangesAndReviewThreshold() throws {
        let json = #"{"key":"a", "season":2, "episode":4, "episodeEnd":5, "stage":"pending", "matchedEpisode":4, "matchedEpisodeEnd":5, "matchConfidence":0.8}"#
        var episode = try JSONDecoder().decode(Episode.self, from: Data(json.utf8))
        XCTAssertNil(episode.mappingDescription, "matching range at the default threshold is not noteworthy")
        XCTAssertEqual(episode.mappingDescription(threshold: 0.81), "matched E04–05 · 80% confidence")
        episode.matchedEpisodeEnd = 6
        XCTAssertEqual(episode.mappingDescription, "matched E04–06 · 80% confidence")
        episode.matchedEpisode = 0
        XCTAssertNil(episode.mappingDescription, "unmatched episodes cannot show a mapping")
    }

    func testEpisodeSubtitleSummaryPrefersIssuesToSource() throws {
        var episode = try JSONDecoder().decode(Episode.self, from: Data(#"{"key":"a", "season":1, "episode":1, "stage":"pending"}"#.utf8))
        XCTAssertNil(episode.subtitleDescription)
        episode.subtitleLanguage = "en"
        episode.subtitleSource = "OpenSubtitles"
        XCTAssertEqual(episode.subtitleDescription, "en · opensubtitles")
        episode.subtitleReviewIssues = ["timing needs review"]
        XCTAssertEqual(episode.subtitleDescription, "en · timing needs review")
        episode.subtitleSevereIssues = ["missing cues"]
        XCTAssertEqual(episode.subtitleDescription, "en · 2 subtitle issues")
        episode.subtitleLanguage = nil
        XCTAssertEqual(episode.subtitleDescription, "2 subtitle issues")
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
