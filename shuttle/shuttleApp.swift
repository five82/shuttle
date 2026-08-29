import SwiftUI

@main
struct shuttleApp: App {
    @State private var settingsStore: AppSettingsStore
    @State private var monitor: SpindleMonitor

    init() {
        let store = AppSettingsStore()
        _settingsStore = State(initialValue: store)
        _monitor = State(initialValue: SpindleMonitor(clientProvider: { store.makeClient() }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settingsStore)
                .environment(monitor)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    monitor.refreshNow()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            ShuttleHelpCommands()
        }

        Window("shuttle Help", id: ShuttleHelp.id) {
            ShuttleHelpView()
        }
        .defaultSize(width: 620, height: 640)
        .windowResizability(.contentSize)

        Settings {
            ShuttleSettingsView()
                .environment(settingsStore)
                .environment(monitor)
        }
    }
}

private enum ShuttleHelp {
    static let id = "shuttle-help"
}

private struct ShuttleHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("shuttle Help") {
                openWindow(id: ShuttleHelp.id)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

private struct ShuttleSettingsView: View {
    @Environment(AppSettingsStore.self) private var settingsStore
    @Environment(SpindleMonitor.self) private var monitor

    @State private var baseURLString = ""
    @State private var token = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section("Spindle API") {
                TextField("Address", text: $baseURLString, prompt: Text(AppSettings.defaultBaseURLString))
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(commit)

                TextField("Token", text: $token, prompt: Text("Optional bearer token"))
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(commit)

                if !baseURLString.isEmpty, AppSettings(baseURLString: baseURLString, token: "").baseURL == nil {
                    Label("Enter an http:// or https:// address with a host.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Matches the daemon's [api] bind and token settings. shuttle only reads from this API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Test Connection", action: testConnection)
                        .disabled(testing)
                    if testing {
                        ProgressView().controlSize(.small)
                    } else if let testResult {
                        Text(testResult)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Reset to Defaults") {
                        settingsStore.resetToDefaults()
                        load()
                        monitor.refreshNow()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: load)
        .onDisappear(perform: commit)
    }

    private func load() {
        baseURLString = settingsStore.settings.baseURLString
        token = settingsStore.settings.token
    }

    private func commit() {
        var changed = false
        if baseURLString != settingsStore.settings.baseURLString {
            settingsStore.updateBaseURLString(baseURLString.isEmpty ? AppSettings.defaultBaseURLString : baseURLString)
            changed = true
        }
        if token != settingsStore.settings.token {
            settingsStore.updateToken(token)
            changed = true
        }
        if changed {
            load()
            monitor.refreshNow()
        }
    }

    private func testConnection() {
        commit()
        guard let client = settingsStore.makeClient() else {
            testResult = "Address is not a valid URL."
            return
        }
        testing = true
        testResult = nil
        Task {
            do {
                try await client.health()
                _ = try await client.status()
                testResult = "Connected."
            } catch {
                testResult = SpindleMonitor.describe(error)
            }
            testing = false
        }
    }
}

private struct ShuttleHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("shuttle Help", systemImage: "questionmark.circle.fill")
                    .font(.largeTitle.bold())

                Text("A read-only monitor for a running Spindle daemon.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HelpCard(title: "Quick Start", systemImage: "play.circle") {
                    HelpBullet("Enable Spindle's HTTP API with [api] bind and token in its config, then enter the same address and token in shuttle > Settings.")
                    HelpBullet("Now shows what needs attention, what is running, and what the daemon is holding. Queue lists every item; click a column header to sort.")
                    HelpBullet("shuttle never changes anything. Use the spindle CLI to retry, remove, or stop items.")
                }

                HelpCard(title: "Shortcuts", systemImage: "keyboard") {
                    HelpBullet("⌘R refreshes immediately.")
                    HelpBullet("⌘F filters the queue.")
                    HelpBullet("⌘, opens Settings.")
                }

                HelpCard(title: "Troubleshooting", systemImage: "wrench.and.screwdriver") {
                    HelpBullet("“Unreachable” means nothing answered at the address. Check the daemon is running and [api] bind is set.")
                    HelpBullet("“Rejected the API token” means the daemon answered but the token does not match its [api] token.")
                    HelpBullet("While disconnected, the last good snapshot stays on screen and shuttle retries with increasing delays up to 30 seconds.")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HelpCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .font(.callout)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct HelpBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
