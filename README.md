# shuttle

shuttle is a small native macOS app for Apple Silicon that monitors a running [Spindle](https://github.com/five82/spindle) daemon. It is read-only: it shows daemon status, the queue, and logs, tells you when the drive is free or something needs you, and never controls the daemon.

- **Menu bar** — the drive state at a glance, an attention count, and a popover with what is running and what needs review.
- **Notifications** — drive available, item needs review, item failed, item completed, and (off by default) connection lost or restored. Each can be turned off.
- **Now** — what needs attention, what is running with live progress and time left, what is waiting, what the daemon is holding, what just finished.
- **Queue** — every item in a sortable, filterable table with progress, ETA, and a context menu for copy and Reveal in Finder.
- **Attention** — failed and review items with the reason, one click from the details.
- **Inspector** — per-item pipeline stages with durations, media and encoder details, output size and validation, per-episode progress for TV, the item's log, and Reveal in Finder when the library is mounted.
- **Log** — the daemon log, tailed live, with a minimum level, daemon-only switch, text filter, follow, and clickable item numbers.
- **Health** — the daemon's state and last error, its process facts, and the tool checks it ran at startup.

## Expectations

This repository is shared as is. shuttle is a personal tool. I've open sourced it because I believe in sharing but I'm not an active maintainer.

- Personal-first: Things will change and break as I iterate.
- Best-effort only: Part time hobby project. I may be slow to respond to questions or may not respond at all.
- This project started as and remains an experiment. Expect rough edges.

## User requirements

- Apple Silicon Mac running macOS 14 or newer
- A Spindle daemon on a Linux host on your LAN, with its HTTP API bound to a reachable interface (Spindle does not run on macOS)
- The daemon's API bearer token, if one is configured

In Spindle's config, expose the API on the network:

```toml
[api]
bind = "0.0.0.0:7487"
token = "choose-a-token"
```

On first launch shuttle asks for the daemon's address; enter `http://<linux-host>:7487` and the token in **shuttle > Settings**. The first time shuttle reaches the daemon, macOS asks to allow local network access; shuttle does not work without it.

## Installing a release

Release builds are signed with an Apple Development certificate but are not notarized, so macOS Gatekeeper will warn that it cannot verify the developer. Only open shuttle if you trust the downloaded release.

After downloading and unzipping `shuttle.app`, you can open it with one of these methods:

### GUI

1. Move `shuttle.app` to `/Applications` or `~/Applications`.
2. Control-click `shuttle.app` and choose **Open**.
3. Click **Open** again in the warning dialog.

If macOS still blocks it, try opening it once, then go to **System Settings > Privacy & Security**, scroll to the security warning for shuttle, and click **Open Anyway**.

### Command line

Remove the download quarantine attribute, then open the app:

```sh
xattr -dr com.apple.quarantine /Applications/shuttle.app
open /Applications/shuttle.app
```

Adjust the path if you installed shuttle somewhere else, for example `~/Applications/shuttle.app`.

## Developer requirements

- Apple Silicon Mac
- Xcode at `/Applications/Xcode.app`
- An Apple Development signing certificate for the team pinned in the project (`DEVELOPMENT_TEAM`); to build under your own team, change it in Xcode under Signing & Capabilities. Do not leave it empty — an ad-hoc signed app loses its Local Network permission every time it is rebuilt.
- A running Spindle daemon if you want to run shuttle against real data

## Build and run from source

```sh
./scripts/run      # debug build and launch
./scripts/build    # debug build only
./scripts/test     # debug test run
./scripts/install  # release build installed to ~/Applications/shuttle.app
./scripts/package  # release build packaged as build/dist/shuttle-<version>-macos-arm64.zip
```

Or open the project in Xcode:

```sh
open shuttle.xcodeproj
```

## Getting started

1. Start Spindle with its HTTP API enabled.
2. Launch shuttle and point it at the daemon in **shuttle > Settings** if it is not on the default address.
3. Allow notifications when macOS asks, if you want to be told when the drive is free.
4. Optional: turn on **Show in menu bar only** and **Launch at login** in Settings. In menu-bar-only mode the popover's ⋯ menu has Settings and Quit.
5. Open **Help > shuttle Help** (`⌘?`) for the current usage notes and troubleshooting.

shuttle only reads from Spindle's API. Use the `spindle` CLI to control the daemon or queue.
