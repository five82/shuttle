import ServiceManagement
import SwiftUI

@main
struct shuttleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var model: AppModel { AppModel.shared }
    private var settingsStore: AppSettingsStore { model.settings }
    private var monitor: SpindleMonitor { model.monitor }

    var body: some Scene {
        Window("shuttle", id: MainWindow.id) {
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
                Button("Reset Queue Sort") {
                    model.resetQueueSort()
                }
                Divider()
                ForEach(SidebarSection.allCases) { section in
                    Button(section.title) {
                        model.section = section
                    }
                    .keyboardShortcut(section.shortcutKey, modifiers: .command)
                }
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
                .environment(settingsStore)
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

    /// Outlined disc when the drive is free, filled while it is busy, pause
    /// while the disc monitor is paused, and a struck antenna when shuttle
    /// cannot reach the daemon at all.
    private var symbol: String {
        guard monitor.connection.isConnected else { return "antenna.radiowaves.left.and.right.slash" }
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
    @State private var revealToken = false
    @State private var testResult: String?
    @State private var testing = false
    @State private var confirmingReset = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Spindle API") {
                TextField("Address", text: $baseURLString, prompt: Text(AppSettings.defaultBaseURLString))
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(commit)

                HStack(spacing: 6) {
                    Group {
                        if revealToken {
                            TextField("Token", text: $token, prompt: Text("Optional bearer token"))
                        } else {
                            SecureField("Token", text: $token, prompt: Text("Optional bearer token"))
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(commit)
                    Toggle(isOn: $revealToken) {
                        Image(systemName: revealToken ? "eye.slash" : "eye")
                    }
                    .toggleStyle(.button)
                    .labelsHidden()
                    .help(revealToken ? "Hide the token" : "Show the token")
                }

                if baseURLString.isEmpty || baseURLString == AppSettings.defaultBaseURLString {
                    Label("Spindle runs on a Linux host, not this Mac. Enter its network address, such as http://spindle.local:7487.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if AppSettings(baseURLString: baseURLString, token: "").baseURL == nil {
                    Label("Enter an http:// or https:// address with a host.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker("Poll every", selection: pollIntervalBinding) {
                    ForEach(AppSettings.pollIntervalChoices, id: \.self) { interval in
                        Text(interval == 1 ? "1 second" : "\(Int(interval)) seconds").tag(interval)
                    }
                }
                .help("How often shuttle asks the daemon for status and queue while connected")

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
                Text("Hides the Dock icon. shuttle keeps polling and notifying; open the window from the menu bar, where Settings and Quit also live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
                    Button("Reset to Defaults…") {
                        confirmingReset = true
                    }
                    .confirmationDialog("Reset all settings to defaults?", isPresented: $confirmingReset) {
                        Button("Reset", role: .destructive) {
                            settingsStore.resetToDefaults()
                            load()
                            model.applyPollInterval()
                            monitor.refreshNow()
                        }
                    } message: {
                        Text("The address goes back to \(AppSettings.defaultBaseURLString), the token is cleared, and notification choices are reset.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: load)
        .onDisappear(perform: commit)
        .onChange(of: baseURLString) { _, _ in testResult = nil }
        .onChange(of: token) { _, _ in testResult = nil }
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

    private var pollIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { settingsStore.settings.pollInterval },
            set: {
                settingsStore.setPollInterval($0)
                model.applyPollInterval()
            }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        guard enabled != (service.status == .enabled) else { return }
        do {
            if enabled { try service.register() } else { try service.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = service.status == .enabled
        }
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
                    HelpBullet("Spindle runs on a Linux host. Enable its HTTP API with [api] bind = \"0.0.0.0:7487\" and a token in its config, then enter http://<host>:7487 and the token in shuttle > Settings.")
                    HelpBullet("Now shows what needs attention, what is running with progress and time left, what is waiting, and what just finished. Queue lists every item; click a column header to sort, right-click a row for Copy and Reveal. Attention is the triage list.")
                    HelpBullet("Select an item to open the inspector (⌥⌘I): each pipeline stage with how long it took, media and encoder details, output, per-episode progress for TV, and the item's log.")
                    HelpBullet("Log tails the daemon log; click an item number to jump to that item. Health shows the daemon's state, its last error, and the tool checks it ran at startup.")
                    HelpBullet("The status chips in the toolbar are buttons: click one to go where that state is explained.")
                    HelpBullet("shuttle never changes anything. Use the spindle CLI to retry, remove, or stop items.")
                }

                HelpCard(title: "Menu Bar and Notifications", systemImage: "bell") {
                    HelpBullet("The menu bar icon shows the drive: outlined when available, filled when busy, paused, or a struck antenna when shuttle cannot reach the daemon. A number beside it is how many items need attention.")
                    HelpBullet("Click it for what is running and what needs you. Click a row to open that item. The ⋯ menu has Refresh, Settings, and Quit — handy in menu-bar-only mode.")
                    HelpBullet("shuttle notifies when the drive becomes available, an item needs review, fails, or completes. Connection lost/restored is off by default. Each can be changed in Settings.")
                    HelpBullet("Turn on “Show in menu bar only” to hide the Dock icon; shuttle keeps polling in the background. “Launch at login” starts it with your Mac.")
                }

                HelpCard(title: "Shortcuts", systemImage: "keyboard") {
                    HelpBullet("⌘1 Now · ⌘2 Queue · ⌘3 Attention · ⌘4 Log · ⌘5 Health.")
                    HelpBullet("⌘R refreshes immediately.")
                    HelpBullet("⌘F filters the current section: now, queue, attention, log, or dependencies.")
                    HelpBullet("⌥⌘I shows or hides the inspector. Return or double-click on a queue row does the same.")
                    HelpBullet("⌘, opens Settings.")
                }

                HelpCard(title: "Troubleshooting", systemImage: "wrench.and.screwdriver") {
                    HelpBullet("“Unreachable” means nothing answered at the address. Check the daemon is running and [api] bind is set.")
                    HelpBullet("“Rejected the API token” means the daemon answered but the token does not match its [api] token.")
                    HelpBullet("While disconnected, the last good snapshot stays on screen and shuttle retries with increasing delays up to 30 seconds. Retry in the status bar polls immediately.")
                    HelpBullet("A red daemon chip means the daemon answered but reports it is stopped or has a workflow error; Health shows the message.")
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
