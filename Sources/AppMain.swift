import SwiftUI

@main
struct ScreenshotRenamerApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Screenshot Renamer", systemImage: "camera.viewfinder") {
            MenuBarMenu()
                .environment(appState)
        }

        Window("Screenshot Renamer", id: "settings") {
            SettingsView()
                .environment(appState)
                .frame(minWidth: 520, minHeight: 480)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 520)
    }

    init() {
        // Resume monitoring immediately on app launch (not waiting for menu click)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [appState] in
            appState.resumeIfNeeded()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("AppDelegate: applicationDidFinishLaunching")
    }
}
