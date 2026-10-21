import SwiftUI
import AppKit

struct MenuBarMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status display
        if appState.watchedFolderPath.isEmpty {
            Text("No folder selected")
                .font(.caption)
        } else {
            Text("📂 \(abbreviatePath(appState.watchedFolderPath))")
                .font(.caption)
            Text(appState.isActive ? "✅ Monitoring active" : "⏸ Paused")
                .font(.caption)
        }

        if appState.geminiAPIKey.isEmpty {
            Text("⚠️ No API key set")
                .font(.caption)
        }

        Divider()

        // Select folder
        Button("Select Folder to Watch…") {
            selectFolder()
        }

        // Toggle monitoring
        if !appState.watchedFolderPath.isEmpty {
            Button(appState.isActive ? "⏸ Pause Monitoring" : "▶️ Start Monitoring") {
                appState.toggleMonitoring()
            }
        }

        Divider()

        // Show recent renames
        if !appState.renameHistory.isEmpty {
            Text("Recent Renames")
                .font(.caption)
            ForEach(appState.renameHistory.prefix(5)) { record in
                Button(action: {}) {
                    Text("✅ \(record.newName)")
                }
                .disabled(true)
            }
            Divider()
        }

        // Open settings window
        Button("Open Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Screenshot Renamer") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Actions

    private func selectFolder() {
        // Must activate the app and run panel on main thread
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select the folder to watch for new screenshots"
            panel.prompt = "Watch This Folder"
            panel.level = .floating

            if panel.runModal() == .OK, let url = panel.url {
                appState.watchedFolderPath = url.path
                appState.startMonitoring()
            }
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
