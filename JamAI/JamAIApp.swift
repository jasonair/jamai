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
                CanvasView(viewModel: viewModel, onCommandClose: { appState.closeProject() })
                    .preferredColorScheme(viewModel.project.appearanceMode.colorScheme)
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
                
                Button("Open Project...") {
                    appState.openProjectDialog()
                }
                .keyboardShortcut("p", modifiers: .command)
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
                
                Button("Export Markdown...") {
                    appState.exportMarkdown()
                }
                .disabled(appState.viewModel == nil)
                // Close items
                Divider()
                Button("Close Project") { appState.closeProject() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(appState.viewModel == nil)
            }

            CommandGroup(replacing: .windowArrangement) {
                Button("Close Project") { appState.closeProject() }
                    .keyboardShortcut("w", modifiers: .command)
                Divider()
                Button("Minimize") { NSApp.keyWindow?.miniaturize(nil) }
                    .keyboardShortcut("m", modifiers: .command)
                Button("Zoom") { NSApp.keyWindow?.zoom(nil) }
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
    @Published var recentProjects: [URL] = []
    
    private var database: Database?
    private let recentKey = "recentProjectBookmarks"
    
    init() {
        loadRecents()
    }
    
    private func loadRecents() {
        let defaults = UserDefaults.standard
        guard let datas = defaults.array(forKey: recentKey) as? [Data] else { return }
        var urls: [URL] = []
        for data in datas {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                urls.append(url)
            }
        }
        self.recentProjects = urls
    }
    
    private func saveRecents() {
        let datas: [Data] = recentProjects.compactMap { url in
            return try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(datas, forKey: recentKey)
    }
    
    func recordRecent(url: URL) {
        var list = recentProjects.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        recentProjects = list
        saveRecents()
    }
    
    func openRecent(url: URL) {
        var accessed = false
        if url.startAccessingSecurityScopedResource() { accessed = true }
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        openProject(url: url)
    }
    
    func createNewProject() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let panel = NSSavePanel()
            // Allow any name; we'll ensure .jam is appended and create the package ourselves
            panel.allowedContentTypes = [.item]
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
                        // Normalize to a .jam URL for consistency
                        self.currentFileURL = (url.pathExtension == Config.jamFileExtension)
                            ? url
                            : url.appendingPathExtension(Config.jamFileExtension)
                        self.viewModel = CanvasViewModel(project: loadedProject, database: database)
                        self.recordRecent(url: self.currentFileURL!)
                    } catch {
                        self.showError("Failed to create project: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func openProjectDialog() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let panel = NSOpenPanel()
            panel.message = "Open a JamAI project (.jam)"
            panel.allowedContentTypes = [.item, .folder]
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.treatsFilePackagesAsDirectories = true
            
            panel.begin { [weak self] response in
                guard let self = self else { return }
                guard response == .OK, let url = panel.url else { return }
                
                DispatchQueue.main.async {
                    self.openProject(url: url)
                }
            }
        }
    }

    func closeProject() {
        // Save only if we have valid state
        if let project = project, let url = currentFileURL, let database = database {
            do {
                try DocumentManager.shared.saveProject(project, to: url.deletingPathExtension(), database: database)
                viewModel?.save()
            } catch {
                // Log but don't block close
                print("Warning: Failed to save on close: \(error.localizedDescription)")
            }
        }
        viewModel = nil
        project = nil
        currentFileURL = nil
        database = nil
    }
    
    func openProject(url: URL) {
        do {
            // If the user selected a file inside the package, or the base folder, resolve to nearest .jam
            var candidate = (url.pathExtension == Config.jamFileExtension) ? url : url
            let maxAscend = 5
            var steps = 0
            while candidate.pathExtension != Config.jamFileExtension && steps < maxAscend {
                let parent = candidate.deletingLastPathComponent()
                if parent == candidate { break }
                candidate = parent
                steps += 1
            }
            // If no .jam ancestor found, allow folder if it looks like a JamAI bundle (contains metadata.json & data.db)
            if candidate.pathExtension != Config.jamFileExtension {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    let meta = candidate.appendingPathComponent("metadata.json")
                    let db = candidate.appendingPathComponent("data.db")
                    if FileManager.default.fileExists(atPath: meta.path), FileManager.default.fileExists(atPath: db.path) {
                        // looks good; proceed
                    } else {
                        // try adding .jam next to it
                        let withExt = candidate.appendingPathExtension(Config.jamFileExtension)
                        if FileManager.default.fileExists(atPath: withExt.path) {
                            candidate = withExt
                        }
                    }
                }
            }
            let (project, database) = try DocumentManager.shared.openProject(from: candidate)
            self.project = project
            self.database = database
            self.currentFileURL = candidate
            self.viewModel = CanvasViewModel(project: project, database: database)
            self.recordRecent(url: candidate)
        } catch {
            self.showError("Failed to open project: \(error.localizedDescription)")
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
