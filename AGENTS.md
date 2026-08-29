# AGENTS.md

Guidance for coding agents working on shuttle.

## TL;DR

- Do not run `git commit` or `git push` unless explicitly instructed.
- Do not create git branches unless explicitly instructed.

## Project shape

shuttle is a native macOS SwiftUI app: a read-only monitor for a running [Spindle](https://github.com/five82/spindle) daemon.

Important paths:

- `shuttle.xcodeproj/` — Xcode project
- `shuttle/ContentView.swift` — main window layout (sidebar + Now / Queue)
- `shuttle/shuttleApp.swift` — scenes (main window, menu bar extra, settings, help), app delegate
- `shuttle/Models/` — value types decoded from the Spindle API
- `shuttle/Services/AppModel.swift` — process-wide owner of settings, monitor, notifications; started from the app delegate so polling runs with no window open
- `shuttle/Services/SpindleClient.swift` — URLSession client, GET endpoints only
- `shuttle/Services/SpindleMonitor.swift` — poll loop, atomic snapshot, backoff, derived state, event emission
- `shuttle/Services/EventDetector.swift` — pure snapshot diff → `MonitorEvent`s
- `shuttle/Services/NotificationService.swift` — user notifications, Dock badge, `shuttle://` deep links
- `shuttle/Services/AppSettingsStore.swift` — UserDefaults-backed settings
- `shuttle/Models/EncodingDetails.swift` — typed view of the raw `encoding` blob, decoded on demand
- `shuttle/Views/` — SwiftUI subviews: `NowView`, `QueueTableView`, `AttentionView`, `ItemInspectorView` (Overview + Episodes), `PipelineStripView`, `EpisodesView`, `MenuBarView`, `StatusChips`, `ConnectionStatusBar`
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
- Events come only from `EventDetector`, which diffs consecutive snapshots and ignores items it has not seen before, so a daemon restart or `spindle queue clear` never replays notifications. Keep it pure and keep its tests exhaustive.
- Opening the main window from outside a view (notification tap, menu bar row, Dock reopen) goes through the `shuttle://main` / `shuttle://item/<id>` URL scheme, because `openWindow` only exists inside views. `ContentView.onOpenURL` routes to `AppModel.handle`.
- "Show in menu bar only" switches the activation policy to `.accessory`; the app keeps polling either way.

## Inspector rules

- Overview is a fixed section skeleton — Attention, Pipeline, Media, Output, Episodes, Meta — in that order for every item. Rows appear or disappear by data presence, never by state branching, so positions stay learnable.
- The pipeline strip is built from `status.pipeline` (the daemon's template) joined with the item's tasks; the item's own task order is only a fallback. Never hardcode the stage list.
- The inspector reads `monitor.selectedItemDetail` (from `GET /api/queue/{id}`, which adds `ripSpec`) and falls back to the list item, so it renders instantly and refines on the next poll.
- Reveal in Finder appears only when the final path exists on this Mac; otherwise Copy Path. Neither touches the daemon.

## Performance / UI rules

Keep SwiftUI `body` code cheap. Avoid synchronous network calls or JSON decoding from render paths.

Polling, decoding, and log tailing should be asynchronous and cancellable, and should back off when the daemon is unreachable.

Avoid blocking the main actor during network requests.

## Xcode project notes

When adding new Swift files, ensure they are included in the `shuttle` target (or `shuttleTests` for tests) in `shuttle.xcodeproj/project.pbxproj`.

Do not edit generated build products under `build/`.
