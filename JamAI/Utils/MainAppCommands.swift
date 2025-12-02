import SwiftUI
import AppKit

struct MainAppCommands: Commands {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    @FocusedValue(\.canvasViewModel) private var focusedVM: CanvasViewModel?

    var body: some Commands {
        // Replace system Undo/Redo so they always appear and work
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                let vm = focusedVM ?? appState.viewModel
                vm?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            // Do NOT disable to avoid SwiftUI command reactivity issues
            
            Button("Redo") {
                let vm = focusedVM ?? appState.viewModel
                vm?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        
        // Add Paste Image command - replaces default paste to intercept Cmd+V for images
        CommandGroup(replacing: .pasteboard) {
            Button("Paste") {
                // Check if clipboard has an image
                let pasteboard = NSPasteboard.general
                let hasImage = pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
                
                if hasImage {
                    // Handle image paste
                    if let vm = focusedVM ?? appState.viewModel {
                        vm.pasteImageFromClipboard()
                    }
                } else {
                    // Let system handle text paste
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            
            // Standard Copy/Cut commands
            Button("Copy") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: .command)
            
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)
            
            Divider()
            
            // Delete command
            Button("Delete") {
                if let vm = focusedVM ?? appState.viewModel,
                   let selectedId = vm.selectedNodeId {
                    vm.deleteNode(selectedId)
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
        
        // Search command
        CommandGroup(after: .textEditing) {
            Button("Search Conversations...") {
                if let vm = focusedVM ?? appState.viewModel {
                    vm.showSearchModal()
                }
            }
            .keyboardShortcut("f", modifiers: .command)
        }

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
                        recentProjectButton(url: url, index: index)
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

    @ViewBuilder
    private func recentProjectButton(url: URL, index: Int) -> some View {
        // Only add keyboard shortcuts for first 9 items (Cmd+1 through Cmd+9)
        if index < 9 {
            Button(action: {
                ensureWindow()
                appState.openRecent(url: url)
            }) {
                Text(url.deletingPathExtension().lastPathComponent)
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        } else {
            Button(action: {
                ensureWindow()
                appState.openRecent(url: url)
            }) {
                Text(url.deletingPathExtension().lastPathComponent)
            }
        }
    }
    
    private func ensureWindow() {
        if NSApp.keyWindow == nil && NSApp.mainWindow == nil {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
