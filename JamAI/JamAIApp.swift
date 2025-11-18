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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var authService = FirebaseAuthService.shared
    @StateObject private var dataService = FirebaseDataService.shared
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var showingMaintenanceAlert = false
    @State private var maintenanceMessage = ""
    @State private var isLoadingUserAccount = false
    
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
                } else if isLoadingUserAccount {
                    // Show loading indicator while user account is loading
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading account...")
                            .foregroundColor(.secondary)
                        
                        // Emergency logout button
                        Button("Sign Out") {
                            do {
                                try authService.signOut()
                                dataService.userAccount = nil
                                isLoadingUserAccount = false
                            } catch {
                                print("Failed to sign out: \(error)")
                            }
                        }
                        .buttonStyle(.link)
                        .padding(.top, 20)
                    }
                    .frame(width: 400, height: 300)
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
            .preferredColorScheme(appState.appearanceMode.colorScheme)
            .onAppear {
                // Load user account when authenticated
                if let userId = authService.currentUser?.uid {
                    Task {
                        isLoadingUserAccount = true
                        
                        // Add timeout to prevent infinite loading
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask {
                                await dataService.loadUserAccount(userId: userId)
                            }
                            group.addTask {
                                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                            }
                            
                            // Wait for first to complete
                            await group.next()
                            group.cancelAll()
                        }
                        
                        isLoadingUserAccount = false
                    }
                }
                
                // Clear tabs on sign-in to show welcome screen
                if authService.isAuthenticated && appState.tabs.isEmpty {
                    // User just signed in, ensure we show welcome screen
                    appState.tabs = []
                    appState.activeTabId = nil
                }
            }
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated, let userId = authService.currentUser?.uid {
                    // Load user account when auth state changes to authenticated
                    Task {
                        isLoadingUserAccount = true
                        
                        // Add timeout to prevent infinite loading
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask {
                                await dataService.loadUserAccount(userId: userId)
                            }
                            group.addTask {
                                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                            }
                            
                            // Wait for first to complete
                            await group.next()
                            group.cancelAll()
                        }
                        
                        isLoadingUserAccount = false
                    }
                } else {
                    // Clear user account when logged out
                    dataService.userAccount = nil
                    isLoadingUserAccount = false
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
            }
            
            // Replace Settings menu to allow disabling when no project is loaded
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(appState.viewModel == nil)
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
    
    // App-level appearance mode (persisted in UserDefaults)
    @Published var appearanceMode: AppearanceMode {
        didSet {
            print("🎨 AppState appearance mode changed to: \(appearanceMode.rawValue)")
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appAppearanceMode")
        }
    }
    
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
        // Load appearance mode from UserDefaults
        if let savedMode = UserDefaults.standard.string(forKey: "appAppearanceMode"),
           let mode = AppearanceMode(rawValue: savedMode) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }
        
        // Sync published property with manager to ensure SwiftUI reactivity
        recentProjectsManager.$recentProjects
            .sink { [weak self] projects in
                self?.recentProjects = projects
            }
            .store(in: &cancellables)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
        
        // If this is a temporary/untitled project, prompt the user to choose a final save location.
        if tab.isTemporary {
            promptSaveAndCloseTemporaryTab(tab: tab, tabIndex: tabIndex)
            return
        }
        
        // Save project before closing - MUST complete before tab removal
        if let viewModel = tab.viewModel, let database = tab.database {
            // Capture references to prevent deallocation during save
            let capturedViewModel = viewModel
            let capturedDatabase = database
            let capturedURL = tab.projectURL
            
            Task { @MainActor in
                // Save project metadata
                try? DocumentManager.shared.saveProject(
                    capturedViewModel.project,
                    to: capturedURL.deletingPathExtension(),
                    database: capturedDatabase
                )
                
                // CRITICAL: Wait for all pending writes to complete
                // This ensures edges in the debounce queue are flushed to disk
                await capturedViewModel.saveAndWait()
                
                if Config.enableVerboseLogging {
                    print("✅ Tab saved successfully before close: \(capturedURL.lastPathComponent)")
                }
                
                // Now safe to cleanup resources
                await MainActor.run {
                    self.performTabCleanup(id: id, tabIndex: tabIndex, tab: tab)
                }
            }
        } else {
            // No save needed, cleanup immediately
            performTabCleanup(id: id, tabIndex: tabIndex, tab: tab)
        }
    }
    
    private func promptSaveAndCloseTemporaryTab(tab: ProjectTab, tabIndex: Int) {
        // First show a standard Save / Don't Save / Cancel alert
        let alert = NSAlert()
        alert.messageText = "Do you want to save this Jam before closing?"
        alert.informativeText = "Your changes will be lost if you don't save."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")        // .alertFirstButtonReturn
        alert.addButton(withTitle: "Don't Save") // .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")     // .alertThirdButtonReturn

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Save - show NSSavePanel to choose final location/name
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.item]
            panel.allowsOtherFileTypes = true
            panel.nameFieldStringValue = "\(tab.projectName).\(Config.jamFileExtension)"
            panel.message = "Save this Jam"

            let handler: (NSApplication.ModalResponse) -> Void = { [weak self] panelResponse in
                guard let self = self else { return }
                guard panelResponse == .OK, let url = panel.url else { return }

                let saveURL: URL
                if url.pathExtension == Config.jamFileExtension {
                    saveURL = url
                } else {
                    saveURL = url.appendingPathExtension(Config.jamFileExtension)
                }

                let originalURL = tab.projectURL

                guard let viewModel = tab.viewModel, let database = tab.database else {
                    // No backing project; just close
                    self.performTabCleanup(id: tab.id, tabIndex: tabIndex, tab: tab)
                    return
                }

                let capturedViewModel = viewModel
                let capturedDatabase = database

                Task { @MainActor in
                    // Update project name to match chosen file name
                    var updatedProject = capturedViewModel.project
                    updatedProject.name = saveURL.deletingPathExtension().lastPathComponent
                    capturedViewModel.project = updatedProject

                    // Save project metadata to the current location
                    try? DocumentManager.shared.saveProject(
                        capturedViewModel.project,
                        to: originalURL.deletingPathExtension(),
                        database: capturedDatabase
                    )

                    // Ensure all pending writes are flushed
                    await capturedViewModel.saveAndWait()

                    // Move bundle if user chose a different location/name
                    if saveURL != originalURL {
                        do {
                            try FileManager.default.moveItem(at: originalURL, to: saveURL)

                            // Update recent projects to point to the new location
                            self.recentProjectsManager.removeRecent(url: originalURL)
                            self.recordRecent(url: saveURL)
                        } catch {
                            self.showError("Failed to save project: \(error.localizedDescription)")
                            return
                        }
                    }

                    if Config.enableVerboseLogging {
                        print("✅ Temporary tab saved successfully before close: \(saveURL.lastPathComponent)")
                    }

                    self.performTabCleanup(id: tab.id, tabIndex: tabIndex, tab: tab)
                }
            }

            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                panel.beginSheetModal(for: window, completionHandler: handler)
            } else {
                handler(panel.runModal())
            }

        case .alertSecondButtonReturn:
            // Don't Save - delete the temporary bundle and close the tab
            let originalURL = tab.projectURL

            // Remove from recents first
            recentProjectsManager.removeRecent(url: originalURL)

            do {
                if FileManager.default.fileExists(atPath: originalURL.path) {
                    try FileManager.default.removeItem(at: originalURL)
                }
            } catch {
                if Config.enableVerboseLogging {
                    print("⚠️ Failed to delete temporary Jam at close: \(error.localizedDescription)")
                }
            }

            performTabCleanup(id: tab.id, tabIndex: tabIndex, tab: tab)

        default:
            // Cancel - do nothing, keep tab open
            return
        }
    }

    private func performTabCleanup(id: UUID, tabIndex: Int, tab: ProjectTab) {
        // Stop security-scoped access
        if accessingResources.contains(tab.projectURL) {
            tab.projectURL.stopAccessingSecurityScopedResource()
            accessingResources.remove(tab.projectURL)
        }
        
        // Remove tab - now safe because save completed
        if tabIndex < tabs.count && tabs[tabIndex].id == id {
            tabs.remove(at: tabIndex)
        }
        
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
    
    func openProjectInNewTab(url: URL, isTemporary: Bool = false) {
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
                isTemporary: isTemporary,
                viewModel: viewModel,
                database: database
            )
            
            tabs.append(newTab)
            activeTabId = newTab.id
            recordRecent(url: normalizedURL)
            
            // Track project opened analytics
            if let userId = FirebaseAuthService.shared.currentUser?.uid {
                Task {
                    await AnalyticsService.shared.trackProjectActivity(
                        userId: userId,
                        projectId: project.id,
                        projectName: project.name,
                        activityType: .opened
                    )
                }
            }
        } catch {
            showError("Failed to open project: \(error.localizedDescription)")
        }
    }
    
    func createNewProject() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check saved Jams limit for Free plan
            if let account = FirebaseDataService.shared.userAccount {
                let maxJams = account.plan.maxSavedJams
                let currentJamCount = self.recentProjects.count
                
                if maxJams != -1 && currentJamCount >= maxJams {
                    let alert = NSAlert()
                    alert.messageText = "Project Limit Reached"
                    alert.informativeText = "Your \(account.plan.displayName) plan allows up to \(maxJams) saved Jams. You currently have \(currentJamCount) projects. Please delete an old project or upgrade to Pro for unlimited projects."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "View Plans")
                    alert.addButton(withTitle: "Cancel")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        // Show user settings to view plans
                        self.showUserSettings()
                    }
                    return
                }
            }
            
            // Create a new project immediately with an auto-generated name,
            // without prompting the user for a save location.
            do {
                let projectName = self.generateUntitledProjectName()
                let (project, fileURL) = try DocumentManager.shared.createNewProject(name: projectName)
                
                // Open in new tab
                self.openProjectInNewTab(url: fileURL, isTemporary: true)
                
                // Track project created analytics
                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                    Task {
                        await AnalyticsService.shared.trackProjectActivity(
                            userId: userId,
                            projectId: project.id,
                            projectName: project.name,
                            activityType: .created
                        )
                    }
                }
            } catch {
                self.showError("Failed to create project: \(error.localizedDescription)")
            }
        }
    }
    
    private func generateUntitledProjectName() -> String {
        var projectName = "Untitled Jam"
        var counter = 1
        
        while recentProjects.contains(where: { $0.lastPathComponent == "\(projectName)\(Config.jamFileExtension)" }) {
            projectName = "Untitled Jam \(counter)"
            counter += 1
        }
        
        return projectName
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
            panel.message = "Select a Jam AI project folder (.jam)"
            
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
        // Use ModalCoordinator to show Settings modal (matching TeamMember pattern)
        guard let viewModel = self.viewModel else { return }
        ModalCoordinator.shared.showSettingsModal(viewModel: viewModel, appState: self)
    }
    
    func showUserSettings() {
        // Use ModalCoordinator to show User Settings modal (matching TeamMember pattern)
        ModalCoordinator.shared.showUserSettingsModal()
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

// MARK: - Appearance Helpers

extension AppearanceMode {
    @MainActor var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
