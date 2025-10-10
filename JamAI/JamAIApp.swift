//
//  JamAIApp.swift
//  JamAI
//
//  Main application entry point
//

import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@main
struct JamAIApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            if let viewModel = appState.viewModel {
                CanvasView(viewModel: viewModel)
                    .preferredColorScheme(appState.project?.appearanceMode.colorScheme)
                    .frame(minWidth: 1200, minHeight: 800)
            } else {
                WelcomeView(appState: appState)
                    .frame(width: 600, height: 400)
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project...") {
                    appState.createNewProject()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.viewModel == nil)
                
                Button("Export JSON...") {
                    appState.exportJSON()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.viewModel == nil)
                
                Button("Export Markdown...") {
                    appState.exportMarkdown()
                }
                .disabled(appState.viewModel == nil)
            }
            
            CommandGroup(after: .pasteboard) {
                Button("Copy Node") {
                    appState.viewModel?.copyNode(appState.viewModel?.selectedNodeId ?? UUID())
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(appState.viewModel?.selectedNodeId == nil)
                
                Button("Paste Node") {
                    appState.viewModel?.pasteNode(at: .zero)
                }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(appState.viewModel == nil)
            }
            
            CommandGroup(after: .undoRedo) {
                Button("Undo") {
                    appState.viewModel?.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(appState.viewModel?.undoManager.canUndo ?? false))
                
                Button("Redo") {
                    appState.viewModel?.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(appState.viewModel?.undoManager.canRedo ?? false))
            }
            
            CommandGroup(after: .toolbar) {
                Button("Settings...") {
                    appState.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(appState.viewModel == nil)
            }
        }
        
        Settings {
            if let viewModel = appState.viewModel {
                SettingsView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var viewModel: CanvasViewModel?
    @Published var project: Project?
    @Published var currentFileURL: URL?
    
    private var database: Database?
    
    func createNewProject() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let panel = NSSavePanel()
            panel.allowedContentTypes = []
            panel.allowsOtherFileTypes = true
            panel.nameFieldStringValue = "Untitled Project.\(Config.jamFileExtension)"
            panel.message = "Create a new JamAI project"
            
            panel.begin { [weak self] response in
                guard let self = self else { return }
                guard response == .OK, let url = panel.url else { return }
                
                DispatchQueue.main.async {
                    do {
                        let project = Project(name: url.deletingPathExtension().lastPathComponent)
                        try DocumentManager.shared.saveProject(project, to: url.deletingPathExtension())
                        
                        let (loadedProject, database) = try DocumentManager.shared.openProject(from: url.deletingPathExtension())
                        self.project = loadedProject
                        self.database = database
                        self.currentFileURL = url
                        self.viewModel = CanvasViewModel(project: loadedProject, database: database)
                    } catch {
                        self.showError("Failed to create project: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func openProject(url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            do {
                let (project, database) = try DocumentManager.shared.openProject(from: url)
                self.project = project
                self.database = database
                self.currentFileURL = url
                self.viewModel = CanvasViewModel(project: project, database: database)
            } catch {
                self.showError("Failed to open project: \(error.localizedDescription)")
            }
        }
    }
    
    func save() {
        guard let project = project, let url = currentFileURL, let database = database else { return }
        
        do {
            // Save using the existing database instance to preserve nodes/edges
            try DocumentManager.shared.saveProject(project, to: url.deletingPathExtension(), database: database)
            viewModel?.save()
        } catch {
            showError("Failed to save project: \(error.localizedDescription)")
        }
    }
    
    func exportJSON() {
        guard let viewModel = viewModel else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.project.name).json"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            do {
                try DocumentManager.shared.exportJSON(
                    project: viewModel.project,
                    nodes: Array(viewModel.nodes.values),
                    edges: Array(viewModel.edges.values),
                    to: url
                )
            } catch {
                self.showError("Failed to export JSON: \(error.localizedDescription)")
            }
        }
    }
    
    func exportMarkdown() {
        guard let viewModel = viewModel else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = "\(viewModel.project.name).md"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            do {
                try DocumentManager.shared.exportMarkdown(
                    project: viewModel.project,
                    nodes: Array(viewModel.nodes.values),
                    edges: Array(viewModel.edges.values),
                    to: url
                )
            } catch {
                self.showError("Failed to export Markdown: \(error.localizedDescription)")
            }
        }
    }
    
    func showSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}
