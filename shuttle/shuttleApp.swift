import SwiftUI

@main
struct shuttleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var model: AppModel { AppModel.shared }
    private var settingsStore: AppSettingsStore { model.settings }
    private var monitor: SpindleMonitor { model.monitor }

    var body: some Scene {
        WindowGroup(id: MainWindow.id) {
            ContentView()
                .environment(model)
                .environment(settingsStore)
                .environment(monitor)
        }
        .handlesExternalEvents(matching: [DeepLink.scheme])
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

        MenuBarExtra {
            MenuBarView()
                .environment(monitor)
        } label: {
            MenuBarLabel()
                .environment(monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            ShuttleSettingsView()
                .environment(model)
                .environment(settingsStore)
                .environment(monitor)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSWorkspace.shared.open(DeepLink.main.url)
        }
        return true
    }
}

private struct MenuBarLabel: View {
    @Environment(SpindleMonitor.self) private var monitor

    var body: some View {
        let count = monitor.attentionCount
        Label {
            Text(count > 0 ? "\(count)" : "")
        } icon: {
            Image(systemName: symbol)
        }
        .labelStyle(.titleAndIcon)
    }

    private var symbol: String {
        guard monitor.connection.isConnected else { return "opticaldisc" }
        switch monitor.driveState {
        case .busy: return "opticaldisc.fill"
        case .paused: return "pause.circle"
        case .available, .unknown: return "opticaldisc"
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
    @Environment(AppModel.self) private var model
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

            Section("Notifications") {
                ForEach(NotificationKind.allCases) { kind in
                    Toggle(isOn: notificationBinding(kind)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                            Text(kind.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Menu Bar") {
                Toggle("Show in menu bar only", isOn: menuBarOnlyBinding)
                Text("Hides the Dock icon. shuttle keeps polling and notifying; open the window from the menu bar.")
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

    private func notificationBinding(_ kind: NotificationKind) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings.notifies(kind) },
            set: { settingsStore.setNotification(kind, enabled: $0) }
        )
    }

    private var menuBarOnlyBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.menuBarOnly },
            set: {
                settingsStore.setMenuBarOnly($0)
                model.applyActivationPolicy()
            }
        )
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
                    HelpBullet("Now shows what needs attention, what is running, and what the daemon is holding. Queue lists every item; click a column header to sort. Attention is the triage list.")
                    HelpBullet("Select an item to open the inspector (⌥⌘I): pipeline progress, media and encoder details, output, and per-episode progress for TV.")
                    HelpBullet("shuttle never changes anything. Use the spindle CLI to retry, remove, or stop items.")
                }

                HelpCard(title: "Menu Bar and Notifications", systemImage: "bell") {
                    HelpBullet("The menu bar icon shows the drive: outlined when available, filled when busy, paused, or plain when disconnected. A number beside it is how many items need attention.")
                    HelpBullet("Click it for what is running and what needs you. Click a row to open that item.")
                    HelpBullet("shuttle notifies when the drive becomes available, an item needs review, fails, or completes. Each can be turned off in Settings.")
                    HelpBullet("Turn on “Show in menu bar only” to hide the Dock icon; shuttle keeps polling in the background.")
                }

                HelpCard(title: "Shortcuts", systemImage: "keyboard") {
                    HelpBullet("⌘R refreshes immediately.")
                    HelpBullet("⌘F filters the queue.")
                    HelpBullet("⌥⌘I shows or hides the inspector.")
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
