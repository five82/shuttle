# AGENTS.md

Guidance for coding agents working on shuttle.

## TL;DR

- Do not run `git commit` or `git push` unless explicitly instructed.
- Do not create git branches unless explicitly instructed.

## Project shape

shuttle is a native macOS SwiftUI app: a read-only monitor for a running [Spindle](https://github.com/five82/spindle) daemon.

Important paths:

- `shuttle.xcodeproj/` — Xcode project
- `shuttle/ContentView.swift` — main window layout (sidebar + sections, per-section toolbar search, ⌘1–5)
- `shuttle/shuttleApp.swift` — scenes (main window, menu bar extra, settings, help), app delegate
- `shuttle/Models/` — value types decoded from the Spindle API
- `shuttle/Services/AppModel.swift` — process-wide owner of settings, monitor, notifications; started from the app delegate so polling runs with no window open
- `shuttle/Services/SpindleClient.swift` — URLSession client, GET endpoints only
- `shuttle/Services/SpindleMonitor.swift` — poll loop, atomic snapshot, backoff, derived state, event emission
- `shuttle/Services/EventDetector.swift` — pure snapshot diff → `MonitorEvent`s
- `shuttle/Services/NotificationService.swift` — user notifications, Dock badge, `shuttle://` deep links
- `shuttle/Services/LogTailer.swift` — one per visible log view; tail window then `since` cursor catch-up
- `shuttle/Services/AppSettingsStore.swift` — UserDefaults-backed settings
- `shuttle/Models/EncodingDetails.swift` — typed view of the raw `encoding` blob, decoded on demand
- `shuttle/Models/ItemProgress.swift` — per-item live progress (fraction, ETA, speed, frames, elapsed), derived once per snapshot into `SpindleMonitor.progress`
- `shuttle/Views/` — SwiftUI subviews: `NowView`, `QueueTableView`, `AttentionView`, `ItemInspectorView` (Overview + Episodes), `PipelineStripView` (the per-stage list with durations), `EpisodesView`, `LogView` (daemon log and per-item tab), `DependenciesView` (the Health section: daemon state + dependency checks), `MenuBarView`, `StatusChips`, `ConnectionStatusBar`
- `shuttle/Info.plist` — merged into the generated Info.plist; holds the ATS exception and local-network usage string
- `shuttleTests/` — unit tests; `shuttleTests/Fixtures/*.json` are real responses captured from a live daemon
- `scripts/build` — debug build
- `scripts/test` — debug test run
- `scripts/run` — debug build and launch
- `scripts/install` — release build into `~/Applications`
- `scripts/package` — release build zipped into `build/dist`

## Build / validate

Use the scripts instead of invoking `xcodebuild` directly:

```sh
./scripts/build
./scripts/test
./scripts/run
```

The scripts set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and build/test for macOS arm64.

Run `./scripts/test` after Swift or project changes that affect app behavior; at minimum run `./scripts/build` for build-only changes.

## Runtime assumptions

shuttle assumes:

- Apple Silicon Mac running macOS 14 or newer
- a Spindle daemon reachable over its HTTP API, by default `http://127.0.0.1:7487`
- an optional bearer token matching the daemon's `[api] token` setting

Do not silently change these defaults without updating README/help text and migration behavior.

Spindle's API is plain HTTP on a LAN, so `Info.plist` sets `NSAllowsArbitraryLoads` and `NSLocalNetworkUsageDescription`. Without them URLSession fails with "App Transport Security" / "Internet connection appears to be offline" errors.

Never put a real daemon hostname or token in source, fixtures, tests, or docs. The repo is public. Use the defaults (`127.0.0.1:7487`, empty token) in code and pass real values through Settings or `defaults write local.shuttle.app spindleBaseURL ...` for local testing.

## Important behavior

shuttle is read-only. It observes Spindle; it never controls it.

- Only call read-only Spindle endpoints: `GET /api/health`, `GET /api/status`, `GET /api/queue`, `GET /api/queue/{id}`, `GET /api/logs`.
- Never call mutating endpoints (`POST /api/queue/*`, `DELETE /api/queue/*`, `POST /api/daemon/*`, `POST /api/disc/*`). Do not add UI for retrying, removing, clearing, stopping, pausing, or enqueuing.
- Never read or write Spindle's queue database, staging directory, or library directly. The HTTP API is the only integration point.
- Treat the daemon as possibly unreachable at any time. Show a clear disconnected state and keep polling; never block the UI on a request.

## Fixtures

`shuttleTests/Fixtures/{status,queue,item,logs}.json` are captured from a live daemon. Re-capture when Spindle's `internal/httpapi/response.go` changes, then check `grep -il "token\|internal" shuttleTests/Fixtures/*.json` comes back empty before committing:

```sh
curl -H "Authorization: Bearer $TOKEN" $SPINDLE/api/status | python3 -m json.tool > shuttleTests/Fixtures/status.json
curl -H "Authorization: Bearer $TOKEN" $SPINDLE/api/queue  | python3 -m json.tool > shuttleTests/Fixtures/queue.json
```

Decoding tests assert specific values from those captures (item IDs, counts); update the assertions alongside the fixtures.

## Surfaces and navigation

- The menu bar extra and notifications are primary; the main window is secondary. Anything that changes what a poll means (new derived state, new event) must show up in all three.
- Item and drive events come only from `EventDetector`, which diffs consecutive snapshots and ignores items it has not seen before, so a daemon restart or `spindle queue clear` never replays notifications. Keep it pure and keep its tests exhaustive. Connection lost/restored events come from the monitor's own poll outcome and are off by default in Settings.
- Daemon-level problems (`status.running == false`, `workflow.lastError`) are derived into `SpindleMonitor.daemonIssue` and shown in the toolbar chip, the Now banner, the menu bar, and Health.
- Opening the main window from outside a view (notification tap, menu bar row, Dock reopen) goes through the `shuttle://main` / `shuttle://item/<id>` URL scheme, because `openWindow` only exists inside views. `ContentView.onOpenURL` routes to `AppModel.handle`. `AppModel.focus` stays in the current section when it shows the inspector (Now, Queue, Attention) and otherwise switches to Queue.
- "Show in menu bar only" switches the activation policy to `.accessory`; the app keeps polling either way. The popover footer's ⋯ menu carries Refresh, Settings, and Quit so accessory mode is never a dead end.

## Inspector rules

- Overview is a fixed section skeleton — Attention, Pipeline, Media, Output, Episodes, Meta — in that order for every item. Rows appear or disappear by data presence, never by state branching, so positions stay learnable.
- The pipeline list is built from `status.pipeline` (the daemon's template) joined with the item's tasks; the item's own task order is only a fallback. Never hardcode the stage list. Each row shows the task's duration from `startedAt`/`finishedAt`; the stage that handed a completed item to review is tinted orange.
- The inspector reads `monitor.selectedItemDetail` (from `GET /api/queue/{id}`, which adds `ripSpec`) and falls back to the list item, so it renders instantly and refines on the next poll.
- Reveal in Finder appears only when the final path exists on this Mac; otherwise Copy Path. Neither touches the daemon.

## Log rules

- `GET /api/logs` cursor semantics: the first request uses `tail=1&limit=N`; every later request passes `since=<next>` (inclusive, `seq >= since`) and the daemon returns oldest-first, so the cursor never skips a burst larger than the limit. `LogTailer` owns this; never re-implement it in a view.
- Filters the daemon applies (`level` minimum, `item`, `daemon_only`) restart the tail from scratch. Text search is local and never hits the daemon.
- The tailer buffer is capped at `LogTailer.bufferLimit`; a `LogView` starts its tailer on appear and stops it on disappear, so closed views cost nothing.
- Default minimum level is Info; Debug is opt-in because reel's verbose lines dominate.

## Performance / UI rules

Keep SwiftUI `body` code cheap. Avoid synchronous network calls or JSON decoding from render paths. Live progress (ETA, speed, frames) is decoded once per snapshot into `SpindleMonitor.progress`; rows read that dictionary rather than `item.encodingDetails`.

Polling, decoding, and log tailing should be asynchronous and cancellable, and should back off when the daemon is unreachable.

Avoid blocking the main actor during network requests.

## Xcode project notes

When adding new Swift files, ensure they are included in the `shuttle` target (or `shuttleTests` for tests) in `shuttle.xcodeproj/project.pbxproj`.

Do not edit generated build products under `build/`.

## Signing

The project pins `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY = "Apple Development"` with automatic signing, like takeup-ios. Keep it that way. macOS grants Local Network access per code-signing identity; an ad-hoc signed build gets a new identity on every `scripts/install`, macOS silently drops the previous grant, and every request fails with "The Internet connection appears to be offline" even though the daemon is reachable. If that symptom appears anyway, toggle shuttle in System Settings > Privacy & Security > Local Network.

Never commit signing material: certificates, private keys, provisioning profiles, App Store Connect API keys, or export options are all in `.gitignore`. A team ID is not a secret and may live in the project file.
