# shuttle

shuttle is a small native macOS app for Apple Silicon that monitors a running [Spindle](https://github.com/five82/spindle) daemon. It is read-only: it shows daemon status, the queue, and logs, and never controls the daemon.

## Expectations

This repository is shared as is. shuttle is a personal tool. I've open sourced it because I believe in sharing but I'm not an active maintainer.

- Personal-first: Things will change and break as I iterate.
- Best-effort only: This is a part-time hobby project and I work on it when I'm able to. I may be slow to respond to questions or may not respond at all.
- PRs: Pull requests are welcome if they align with the project's goals but I may be slow to review them or may not accept changes that don't fit my own use case.
- “Vibe coded”: I’m not a Swift developer and this project started as (and remains) a vibe-coding experiment. Expect rough edges.

## User requirements

- Apple Silicon Mac running macOS 14 or newer
- A Spindle daemon with its HTTP API enabled, by default at `http://127.0.0.1:7487`
- The daemon's API bearer token, if one is configured

In Spindle's config, expose the API with:

```toml
[api]
bind = "127.0.0.1:7487"
token = "choose-a-token"
```

You can change the API address and token in **shuttle > Settings**.

## Installing a release

Release builds are currently unsigned and not notarized. macOS Gatekeeper will warn that it cannot verify the developer. Only open shuttle if you trust the downloaded release.

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
3. Open **Help > shuttle Help** (`⌘?`) for the current usage notes and troubleshooting.

shuttle only reads from Spindle's API. Use the `spindle` CLI to control the daemon or queue.
