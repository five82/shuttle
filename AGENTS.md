# AGENTS.md

Guidance for coding agents working on shuttle.

## TL;DR

- Do not run `git commit` or `git push` unless explicitly instructed.
- Do not create git branches unless explicitly instructed.

## Project shape

shuttle is a native macOS SwiftUI app: a read-only monitor for a running [Spindle](https://github.com/five82/spindle) daemon. App code is in `shuttle/` (`Models/`, `Services/`, `Views/`), tests in `shuttleTests/`, build helpers in `scripts/`. Source files carry doc comments explaining their role; read those before asking.

Related repos:

| Repo | Path | Role |
|------|------|------|
| flyer | `~/projects/flyer/` | Read-only terminal UI for Spindle |
| reel | `~/projects/reel/` | AV1 encoder embedded by Spindle |
| spindle | `~/projects/spindle/` | Daemon + CLI; shuttle polls its HTTP API |

## Build / validate

Use `./scripts/build`, `./scripts/test`, `./scripts/run` instead of invoking `xcodebuild` directly (`install` and `package` do release builds). Run `./scripts/test` after Swift or project changes that affect app behavior; at minimum run `./scripts/build`.

When adding Swift files, add them to the `shuttle` (or `shuttleTests`) target in `shuttle.xcodeproj/project.pbxproj`; the project uses explicit file references, not synchronized groups.

## Runtime assumptions

Spindle runs on a Linux host on the LAN, never on this Mac; every real setup reaches it over the network with an optional bearer token (requirements are in README). The `http://127.0.0.1:7487` code default is a safe placeholder for a public repo, not a working configuration: `AppSettings.isPlaceholderAddress` drives the "set the daemon address" first-launch state, and the user always sets a real address in Settings. Do not silently change these defaults without updating README/help text and migration behavior.

Spindle's API is plain HTTP on a LAN, so `Info.plist` sets `NSAllowsArbitraryLoads` and `NSLocalNetworkUsageDescription`. Without them URLSession fails with "App Transport Security" / "Internet connection appears to be offline" errors.

Never put a real daemon hostname or token in source, fixtures, tests, or docs. The repo is public. Keep the placeholder default in code and pass real values through Settings for local testing.

## Important behavior

shuttle is read-only. It observes Spindle; it never controls it.

- Only call read-only Spindle endpoints: `GET /api/health`, `GET /api/status`, `GET /api/queue`, `GET /api/queue/{id}`, `GET /api/logs`.
- Never call mutating endpoints (`POST /api/queue/*`, `DELETE /api/queue/*`, `POST /api/daemon/*`, `POST /api/disc/*`). Do not add UI for retrying, removing, clearing, stopping, pausing, or enqueuing.
- Never read or write Spindle's queue database, staging directory, or library directly. The HTTP API is the only integration point.
- Treat the daemon as possibly unreachable at any time. Show a clear disconnected state and keep polling; never block the main actor on a request. Polling, decoding, and log tailing are asynchronous, cancellable, and back off when the daemon is unreachable.

## Fixtures

`shuttleTests/Fixtures/{status,queue,item,logs}.json` are captured from a live daemon. Re-capture when Spindle's `internal/httpapi/response.go` changes, then check `grep -il "token\|internal" shuttleTests/Fixtures/*.json` comes back empty before committing:

```sh
curl -H "Authorization: Bearer $TOKEN" $SPINDLE/api/status | python3 -m json.tool > shuttleTests/Fixtures/status.json
curl -H "Authorization: Bearer $TOKEN" $SPINDLE/api/queue  | python3 -m json.tool > shuttleTests/Fixtures/queue.json
```

Decoding tests assert specific values from those captures (item IDs, counts); update the assertions alongside the fixtures.

## Design intent

- The menu bar extra and notifications are primary; the main window is secondary. Anything that changes what a poll means (new derived state, new event) must show up in all three.
- Item and drive events come only from `EventDetector`, a pure snapshot diff. Keep it pure and keep its tests exhaustive. Connection lost/restored events come from the monitor's own poll outcome and are off by default.
- Opening the main window from outside a view (notification, menu bar row, Dock reopen) goes through the `shuttle://` URL scheme, because `openWindow` only exists inside views.
- "Show in menu bar only" switches the activation policy to `.accessory`; the app keeps polling either way, and the popover's ⋯ menu must always offer Settings and Quit so accessory mode is never a dead end.
- Inspector Overview is a fixed section skeleton — Attention, Pipeline, Media, Output, Episodes, Meta — in that order for every item. Rows appear or disappear by data presence, never by state branching, so positions stay learnable.
- The pipeline list comes from `status.pipeline` (the daemon's template); never hardcode the stage list.
- `GET /api/logs` cursor semantics: first request `tail=1&limit=N`, then `since=<next>` (inclusive) with oldest-first results, so a burst larger than the limit is never skipped. `LogTailer` owns this; never re-implement it in a view. Server-side filters (`level`, `item`, `daemon_only`) restart the tail; text search is local. Debug level is opt-in because reel's verbose lines dominate.
- Keep SwiftUI `body` cheap: no network or JSON decoding in render paths. Per-item progress is derived once per snapshot into `SpindleMonitor.progress` / `taskProgress`, and why each waiting item waits into `SpindleMonitor.waitReasons` (`WaitReason.derive`, from `status.pipeline` `dependsOn`/`claims` plus scheduler occupancy).
- Before the first snapshot every section renders `NotConnectedView`; a section's own empty state means "connected and empty". While disconnected with a snapshot, `StaleBanner` marks the data as history.
- Durations, ages, and percentages go through `Format` so every view agrees on "42m left" / "20s ago".
- The API token lives in the Keychain (`KeychainTokenStore`); tests inject `InMemoryTokenStore`. Never write it to UserDefaults.

## Signing

The project pins `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY = "Apple Development"` with automatic signing. Keep it that way: macOS grants Local Network access per code-signing identity, so an ad-hoc signed build gets a new identity on every `scripts/install`, silently loses the grant, and every request fails with "The Internet connection appears to be offline" even though the daemon is reachable. If that symptom appears anyway, toggle shuttle in System Settings > Privacy & Security > Local Network.

Never commit signing material (certificates, keys, profiles, API keys); `.gitignore` covers them. A team ID is not a secret and may live in the project file.
