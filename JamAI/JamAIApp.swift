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
import FirebaseCore
import FirebaseAuth

// Helper view to observe undo manager state
struct UndoStateObserver: View {
    let viewModel: CanvasViewModel?
    @Binding var canUndo: Bool
    @Binding var canRedo: Bool
    
    var body: some View {
        Color.clear
            .onAppear {
                updateState()
            }
            .onChange(of: viewModel?.canUndo) { _, newValue in
                canUndo = newValue ?? false
                if Config.enableVerboseLogging { print("🔔 canUndo changed to: \(canUndo)") }
            }
            .onChange(of: viewModel?.canRedo) { _, newValue in
                canRedo = newValue ?? false
                if Config.enableVerboseLogging { print("🔔 canRedo changed to: \(canRedo)") }
            }
    }
    
    private func updateState() {
        canUndo = viewModel?.canUndo ?? false
        canRedo = viewModel?.canRedo ?? false
        if Config.enableVerboseLogging { print("📍 Initial state - canUndo: \(canUndo), canRedo: \(canRedo)") }
    }
}

@main
struct JamAIApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authService = FirebaseAuthService.shared
    @StateObject private var dataService = FirebaseDataService.shared
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var showingMaintenanceAlert = false
    @State private var maintenanceMessage = ""
    
    init() {
        // Configure Firebase on app launch
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if !authService.isAuthenticated {
                    // Show authentication view if not signed in
                    AuthenticationView()
                        .frame(width: 800, height: 600)
                } else if shouldBlockApp() {
                    // Show maintenance/update screen
                    MaintenanceView(message: maintenanceMessage)
                        .frame(width: 600, height: 400)
                } else if appState.tabs.isEmpty {
                    // Show welcome view for signed-in users
                    WelcomeView(appState: appState)
                        .frame(width: 600, height: 400)
                } else {
                ZStack {
                    // Active project canvas (bottom layer)
                    if let viewModel = appState.viewModel {
                        CanvasView(viewModel: viewModel, onCommandClose: { appState.closeProject() })
                            .preferredColorScheme(viewModel.project.appearanceMode.colorScheme)
                            .id(appState.activeTabId) // Force refresh when tab changes
                    }
                    
                    // Tab bar overlay (top layer with high z-index)
                    VStack(spacing: 0) {
                        TabBarView(
                            tabs: appState.tabs,
                            activeTabId: appState.activeTabId,
                            onTabSelect: { tabId in
                                appState.selectTab(tabId)
                            },
                            onTabClose: { tabId in
                                appState.closeTab(tabId)
                            }
                        )
                        
                        Divider()
                        
                        Spacer()
                    }
                    .allowsHitTesting(true)
                }
                .focusedSceneValue(\.canvasViewModel, appState.viewModel)
                .frame(minWidth: 1200, minHeight: 800)
                .background(
                    UndoStateObserver(viewModel: appState.viewModel, canUndo: $canUndo, canRedo: $canRedo)
                )
                }
            }
            .onAppear {
                // Load user account when authenticated
                if let userId = authService.currentUser?.uid {
                    Task {
                        await dataService.loadUserAccount(userId: userId)
                    }
                }
                
                // Clear tabs on sign-in to show welcome screen
                if authService.isAuthenticated && appState.tabs.isEmpty {
                    // User just signed in, ensure we show welcome screen
                    appState.tabs = []
                    appState.activeTabId = nil
                }
            }
        }
        .commands {
            MainAppCommands(appState: appState)
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
                Button("Zoom In") {
                    appState.viewModel?.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(appState.viewModel == nil)
                
                Button("Zoom Out") {
                    appState.viewModel?.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(appState.viewModel == nil)
                
                Button("Reset Zoom") {
                    appState.viewModel?.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(appState.viewModel == nil)
                
                Divider()
                
                Button("Toggle Grid") {
                    if let vm = appState.viewModel {
                        vm.showDots.toggle()
                    }
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(appState.viewModel == nil)
            }
            
            CommandGroup(after: .appInfo) {
                Button("Account...") {
                    appState.showUserSettings()
                }
                .disabled(!authService.isAuthenticated)
                
                Divider()
                
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
    
    // MARK: - Helpers
    
    private func shouldBlockApp() -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let (shouldBlock, message) = dataService.shouldBlockApp(currentVersion: currentVersion)
        maintenanceMessage = message ?? ""
        return shouldBlock
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    // Multi-tab support
    @Published var tabs: [ProjectTab] = []
    @Published var activeTabId: UUID?
    @Published var recentProjects: [URL] = []
    
    // Convenience computed properties for backward compatibility
    var viewModel: CanvasViewModel? {
        activeTab?.viewModel
    }
    
    var project: Project? {
        activeTab?.viewModel?.project
    }
    
    var currentFileURL: URL? {
        activeTab?.projectURL
    }
    
    private var activeTab: ProjectTab? {
        tabs.first { $0.id == activeTabId }
    }
    
    // Delegate recent projects management to dedicated manager
    private let recentProjectsManager = RecentProjectsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Track security-scoped resources per tab
    private var accessingResources: Set<URL> = []
    
    init() {
        // Sync published property with manager to ensure SwiftUI reactivity
        recentProjectsManager.$recentProjects
            .sink { [weak self] projects in
                self?.recentProjects = projects
            }
            .store(in: &cancellables)
    }
    
    func recordRecent(url: URL) {
        recentProjectsManager.recordRecent(url: url)
    }
    
    func clearRecentProjects() {
        recentProjectsManager.clearRecentProjects()
    }
    
    func refreshRecentProjects() {
        recentProjectsManager.refreshRecentProjects()
    }
    
    func openRecent(url: URL) {
        openProjectInNewTab(url: url)
    }
    
    // MARK: - Tab Management
    
    func selectTab(_ id: UUID) {
        activeTabId = id
    }
    
    func closeTab(_ id: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[tabIndex]
        
        // Save project before closing
        if let viewModel = tab.viewModel, let database = tab.database {
            Task {
                try? DocumentManager.shared.saveProject(
                    viewModel.project,
                    to: tab.projectURL.deletingPathExtension(),
                    database: database
                )
                await viewModel.saveAndWait()
            }
        }
        
        // Stop security-scoped access
        if accessingResources.contains(tab.projectURL) {
            tab.projectURL.stopAccessingSecurityScopedResource()
            accessingResources.remove(tab.projectURL)
        }
        
        // Remove tab
        tabs.remove(at: tabIndex)
        
        // Update active tab
        if activeTabId == id {
            if !tabs.isEmpty {
                activeTabId = tabs.first?.id
            } else {
                activeTabId = nil
            }
        }
    }
    
    func closeProject() {
        if let activeId = activeTabId {
            closeTab(activeId)
        }
    }
    
    func openProjectInNewTab(url: URL) {
        // Normalize to the .jam directory URL we will operate on
        let normalizedURL = (url.pathExtension == Config.jamFileExtension) ? url : url.appendingPathExtension(Config.jamFileExtension)
        
        // Check if project is already open in a tab
        if let existingTab = tabs.first(where: { $0.projectURL == normalizedURL }) {
            activeTabId = existingTab.id
            return
        }
        
        do {
            // Start security-scoped access on the actual bundle URL we will use for file access
            if normalizedURL.startAccessingSecurityScopedResource() {
                accessingResources.insert(normalizedURL)
            }
            
            let (project, database) = try DocumentManager.shared.openProject(from: normalizedURL)
            let viewModel = CanvasViewModel(project: project, database: database)
            
            let newTab = ProjectTab(
                projectURL: normalizedURL,
                projectName: normalizedURL.deletingPathExtension().lastPathComponent,
                viewModel: viewModel,
                database: database
            )
            
            tabs.append(newTab)
            activeTabId = newTab.id
            recordRecent(url: normalizedURL)
        } catch {
            showError("Failed to open project: \(error.localizedDescription)")
        }
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
            
            let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self = self else { return }
                guard response == .OK, let url = panel.url else { return }
                DispatchQueue.main.async {
                    do {
                        let project = Project(name: url.deletingPathExtension().lastPathComponent)
                        try DocumentManager.shared.saveProject(project, to: url.deletingPathExtension())
                        
                        // Open in new tab
                        let finalURL = (url.pathExtension == Config.jamFileExtension)
                            ? url
                            : url.appendingPathExtension(Config.jamFileExtension)
                        self.openProjectInNewTab(url: finalURL)
                    } catch {
                        self.showError("Failed to create project: \(error.localizedDescription)")
                    }
                }
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                panel.beginSheetModal(for: window, completionHandler: handler)
            } else {
                handler(panel.runModal())
            }
        }
    }
    
    func openProjectDialog() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let panel = NSOpenPanel()
            // Use the exact same configuration and presentation as WelcomeView.openExistingProject()
            panel.allowedContentTypes = []
            panel.allowsOtherFileTypes = true
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = "Select a JamAI project folder (.jam)"
            
            let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self = self else { return }
                guard response == .OK, let url = panel.url else { return }
                DispatchQueue.main.async {
                    self.openProjectInNewTab(url: url)
                }
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                panel.beginSheetModal(for: window, completionHandler: handler)
            } else {
                handler(panel.runModal())
            }
        }
    }

    
    func save() {
        guard let tab = activeTab,
              let viewModel = tab.viewModel else { return }
        
        do {
            // Security-scoped access is already active from openProjectInNewTab.
            // Reuse the existing database connection to maintain read-write access.
            try DocumentManager.shared.saveProject(
                viewModel.project,
                to: tab.projectURL.deletingPathExtension(),
                database: tab.database
            )
            viewModel.save()
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
    
    private var userSettingsWindow: NSWindow?
    
    func showUserSettings() {
        // Reuse existing window if already open
        if let existingWindow = userSettingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let settingsView = UserSettingsView(onDismiss: { [weak self] in
            self?.userSettingsWindow?.close()
        })
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Account Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 700))
        
        // Center on main window or screen
        if let mainWindow = NSApp.mainWindow {
            window.center()
            window.setFrameOrigin(NSPoint(
                x: mainWindow.frame.midX - window.frame.width / 2,
                y: mainWindow.frame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        
        // Keep reference to prevent deallocation
        self.userSettingsWindow = window
        
        // Clear reference when closed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.userSettingsWindow = nil
        }
        
        window.makeKeyAndOrderFront(nil)
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}
