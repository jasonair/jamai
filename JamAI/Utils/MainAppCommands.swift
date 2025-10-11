import SwiftUI
import AppKit

struct MainAppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appState: AppState

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
            
            Divider()
            
            // Recent Projects submenu
            Menu("Open Recent") {
                if appState.recentProjects.isEmpty {
                    Text("No Recent Projects")
                        .disabled(true)
                } else {
                    ForEach(Array(appState.recentProjects.enumerated()), id: \.element) { index, url in
                        Button(action: {
                            ensureWindow()
                            appState.openRecent(url: url)
                        }) {
                            Text(url.deletingPathExtension().lastPathComponent)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    }
                    
                    Divider()
                    
                    Button("Clear Recent Projects") {
                        appState.clearRecentProjects()
                    }
                }
            }
            .disabled(appState.recentProjects.isEmpty)
        }
    }

    private func ensureWindow() {
        if NSApp.keyWindow == nil && NSApp.mainWindow == nil {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
