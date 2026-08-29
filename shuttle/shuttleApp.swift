import SwiftUI

@main
struct shuttleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            ShuttleHelpCommands()
        }

        Window("shuttle Help", id: ShuttleHelp.id) {
            ShuttleHelpView()
        }
        .defaultSize(width: 620, height: 640)
        .windowResizability(.contentSize)

        Settings {
            ShuttleSettingsView()
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
    var body: some View {
        Form {
            Section("Spindle API") {
                Text("No settings yet. Defaults: http://127.0.0.1:7487, no token.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 680)
    }
}

private struct ShuttleHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("shuttle Help", systemImage: "questionmark.circle.fill")
                    .font(.largeTitle.bold())

                Text("A read-only macOS monitor for a running Spindle daemon.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
