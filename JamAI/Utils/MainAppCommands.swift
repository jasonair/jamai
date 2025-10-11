import SwiftUI
import AppKit

struct MainAppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project...") {
                ensureWindow()
                appState.createNewProject()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Project...") {
                ensureWindow()
                appState.openProjectDialog()
            }
            .keyboardShortcut("p", modifiers: .command)
        }
    }

    private func ensureWindow() {
        if NSApp.keyWindow == nil && NSApp.mainWindow == nil {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
