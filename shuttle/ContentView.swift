import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Status", systemImage: "gauge.with.dots.needle.33percent")
                Label("Queue", systemImage: "list.bullet.rectangle")
                Label("Logs", systemImage: "doc.text.magnifyingglass")
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            ContentUnavailableView(
                "Not Connected",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                description: Text("shuttle is a read-only monitor for a Spindle daemon.")
            )
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
