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
    @StateObject private var appState = AppState.shared
    @StateObject private var authService = FirebaseAuthService.shared
    @StateObject private var dataService = FirebaseDataService.shared
    @StateObject private var updateManager = SparkleUpdateManager()
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var showingMaintenanceAlert = false
    @State private var maintenanceMessage = ""
    @State private var isLoadingUserAccount = false
    @State private var isForceUpdateRequired = false
    @State private var updateURLString: String?
    
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    if isForceUpdateRequired {
                        UpdateRequiredView(
                            message: maintenanceMessage,
                            updateURLString: updateURLString,
                            updateManager: updateManager
                        )
                        .frame(width: 600, height: 400)
                    } else {
                        MaintenanceView(message: maintenanceMessage)
                            .frame(width: 600, height: 400)
                    }
                } else if appState.tabs.isEmpty {
                    // Show welcome view for signed-in users
                    WelcomeView(appState: appState)
                        .frame(width: 600, height: 400)
                } else if appState.activeTabId == nil {
                    // Show welcome view with tab bar when user clicks Home
                    ZStack {
                        // Center the welcome view in the window
                        WelcomeView(appState: appState)
                            .frame(width: 600, height: 400)
                        
                        // Tab bar overlay so user can navigate back to open projects
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                // Home button (highlighted when on home)
                                Button {
                                    // Already on home
                                } label: {
                                    Image(systemName: "house.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color(nsColor: .controlBackgroundColor))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Home")
                                
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
                                
                                Spacer()
                            }
                            .padding(.leading, 8)
                            .frame(height: 36)
                            .background(Color(nsColor: .windowBackgroundColor))
                            
                            Divider()
                            
                            Spacer()
                        }
                        .allowsHitTesting(true)
                    }
                    .frame(minWidth: 1200, minHeight: 800)
                } else {
                ZStack {
                    // Active project canvas (bottom layer)
                    if let viewModel = appState.viewModel {
                        CanvasView(
                            viewModel: viewModel,
                            onCommandClose: { appState.closeProject() },
                            onShowSettings: { appState.showSettings() }
                        )
                            .id(appState.activeTabId) // Force refresh when tab changes
                    }
                    
                    // Tab bar overlay (top layer with high z-index)
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            // Home button - navigate back to intro page
                            Button {
                                appState.goHome()
                            } label: {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Go to Home")
                            
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
                            
                            Spacer()
                            
                            if updateManager.updateReadyToInstall {
                                Button {
                                    // Sparkle will detect the already-downloaded update and run the installer / relaunch
                                    updateManager.checkForUpdates()
                                } label: {
                                    HStack(spacing: 8) {
                                        Text("Restart to Update")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("→")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(999)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 8)
                            }
                        }
                        .padding(.leading, 8)
                        .frame(height: 36)
                        .background(Color(nsColor: .windowBackgroundColor))
                        
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
                
                // Restore previously open tabs when authenticated
                if authService.isAuthenticated && appState.tabs.isEmpty {
                    appState.restoreOpenTabs()
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
                        
                        // Restore tabs after user account loads
                        if appState.tabs.isEmpty {
                            appState.restoreOpenTabs()
                        }
                    }
                } else {
                    // Clear user account when logged out
                    dataService.userAccount = nil
                    isLoadingUserAccount = false
                }
            }
            .sheet(isPresented: $appState.showingBackupList) {
                if let projectURL = appState.currentFileURL {
                    BackupListView(
                        projectURL: projectURL,
                        onRestore: {
                            appState.handleBackupRestored()
                        },
                        onDismiss: {
                            appState.showingBackupList = false
                        }
                    )
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
                
                Button("Save As...") {
                    appState.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appState.viewModel == nil)
                
                Divider()
                
                Button("Restore from Backup...") {
                    appState.showBackupList()
                }
                .disabled(appState.currentFileURL == nil)
                
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
                
                Button("Toggle Background Style") {
                    if let vm = appState.viewModel {
                        switch vm.backgroundStyle {
                        case .blank:
                            vm.backgroundStyle = .dots
                        case .dots:
                            vm.backgroundStyle = .grid
                        case .grid:
                            vm.backgroundStyle = .blank
                        case .color:
                            // When in colored mode, treat Cmd+G as returning to the
                            // normal cycle starting point (blank).
                            vm.backgroundStyle = .blank
                        }
                    }
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(appState.viewModel == nil)
            }
            
            CommandGroup(replacing: .appInfo) {
                Button("About Jam AI") {
                    showAboutPanel()
                }

                Button("Check for Updates...") {
                    updateManager.checkForUpdates()
                }
                
                Button("Account...") {
                    appState.showUserSettings()
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
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
        let (shouldBlock, isForceUpdate, message, updateURL) = dataService.shouldBlockApp(currentVersion: currentVersion)
        maintenanceMessage = message ?? ""
        isForceUpdateRequired = isForceUpdate
        updateURLString = updateURL
        return shouldBlock
    }

    private func showAboutPanel() {
        // Use the standard About panel, which already shows
        // "Version X (Y)" based on CFBundleShortVersionString and CFBundleVersion.
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // Multi-tab support
    @Published var tabs: [ProjectTab] = []
    @Published var activeTabId: UUID?
    @Published var recentProjects: [URL] = []
    @Published var showingBackupList = false
    
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
    
    // Keys for UserDefaults persistence
    private static let openTabsKey = "openTabURLs"
    private static let activeTabURLKey = "activeTabURL"
    
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
    
    /// Restore previously open tabs from UserDefaults
    func restoreOpenTabs() {
        let savedPaths = UserDefaults.standard.array(forKey: Self.openTabsKey) as? [String] ?? []
        print("🔄 Restoring tabs - found \(savedPaths.count) saved paths: \(savedPaths)")
        
        guard !savedPaths.isEmpty else {
            print("🔄 No saved tabs to restore")
            return
        }
        
        let activeTabPath = UserDefaults.standard.string(forKey: Self.activeTabURLKey)
        var restoredActiveTabId: UUID?
        
        for path in savedPaths {
            let url = URL(fileURLWithPath: path)
            
            // Only restore if file still exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("⚠️ Skipping missing file: \(path)")
                continue
            }
            
            print("📂 Restoring tab: \(url.lastPathComponent)")
            
            // Open the project (this will add it to tabs)
            openProjectInNewTab(url: url)
            
            // Track which tab should be active
            if path == activeTabPath, let lastTab = tabs.last {
                restoredActiveTabId = lastTab.id
            }
        }
        
        // Restore active tab selection, or go to home if none specified
        if let restoredId = restoredActiveTabId {
            activeTabId = restoredId
        } else if !tabs.isEmpty {
            // Default to first tab if active tab wasn't found
            activeTabId = tabs.first?.id
        }
        
        print("✅ Restored \(tabs.count) tabs")
    }
    
    /// Save current open tabs to UserDefaults
    private func saveOpenTabs() {
        // Only save non-temporary tabs (temporary = unsaved new projects)
        let tabPaths = tabs.compactMap { tab -> String? in
            guard !tab.isTemporary else { return nil }
            return tab.projectURL.path
        }
        
        print("💾 Saving \(tabPaths.count) open tabs: \(tabPaths)")
        
        UserDefaults.standard.set(tabPaths, forKey: Self.openTabsKey)
        
        // Save active tab URL
        if let activeTab = activeTab, !activeTab.isTemporary {
            UserDefaults.standard.set(activeTab.projectURL.path, forKey: Self.activeTabURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeTabURLKey)
        }
        
        // Force synchronize to ensure data is written immediately
        UserDefaults.standard.synchronize()
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
        saveOpenTabs()
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
        
        // Save open tabs state after closing
        saveOpenTabs()
    }
    
    func closeProject() {
        if let activeId = activeTabId {
            closeTab(activeId)
        }
    }
    
    /// Navigate to home/intro page by deselecting the active tab
    /// Keeps tabs open but shows the welcome view
    func goHome() {
        activeTabId = nil
    }
    
    func showBackupList() {
        guard currentFileURL != nil else { return }
        showingBackupList = true
    }
    
    /// Called after a backup is restored - closes and reopens the project to reload data
    func handleBackupRestored() {
        guard let url = currentFileURL,
              let tabId = activeTabId else { return }
        
        showingBackupList = false
        
        // Close the current tab (without saving - we just restored)
        if let tabIndex = tabs.firstIndex(where: { $0.id == tabId }) {
            performTabCleanup(id: tabId, tabIndex: tabIndex, tab: tabs[tabIndex])
        }
        
        // Reopen the project to load the restored data
        openProjectInNewTab(url: url)
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
            viewModel.projectURL = normalizedURL  // Set for backup service
            
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
            
            // Save open tabs state
            saveOpenTabs()
            
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
            
            // All plans now have unlimited saved Jams - no limit check needed
            
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
            // Mirror WelcomeView.openExistingProject() so .jam bundles are selectable
            if let jamType = UTType(Config.jamUTType) {
                panel.allowedContentTypes = [jamType]
                panel.allowsOtherFileTypes = false
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
            } else {
                panel.allowedContentTypes = []
                panel.allowsOtherFileTypes = true
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
            }
            panel.allowsMultipleSelection = false
            panel.message = "Select a Jam AI project (.jam)"
            
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
        guard
            let activeId = activeTabId,
            let tabIndex = tabs.firstIndex(where: { $0.id == activeId }),
            let viewModel = tabs[tabIndex].viewModel
        else { return }
        
        let tab = tabs[tabIndex]
        
        // For temporary/untitled projects, treat Save as Save As to let the user
        // pick a final name and location without requiring the tab to be closed.
        if tab.isTemporary {
            presentSavePanelForTab(at: tabIndex)
            return
        }
        
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

    func saveAs() {
        guard
            let activeId = activeTabId,
            let tabIndex = tabs.firstIndex(where: { $0.id == activeId })
        else { return }
        
        presentSavePanelForTab(at: tabIndex)
    }

    private func presentSavePanelForTab(at tabIndex: Int) {
        let tab = tabs[tabIndex]
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.item]
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = "\(tab.projectName).\(Config.jamFileExtension)"
        panel.message = "Save this Jam"
        
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else { return }
            
            let saveURL: URL
            if url.pathExtension == Config.jamFileExtension {
                saveURL = url
            } else {
                saveURL = url.appendingPathExtension(Config.jamFileExtension)
            }
            
            self.saveTab(at: tabIndex, to: saveURL)
        }
        
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private func saveTab(at tabIndex: Int, to saveURL: URL) {
        let tab = tabs[tabIndex]
        let originalURL = tab.projectURL
        
        guard let viewModel = tab.viewModel, let database = tab.database else {
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
                    
                    // Update security-scoped resource tracking
                    if self.accessingResources.contains(originalURL) {
                        originalURL.stopAccessingSecurityScopedResource()
                        self.accessingResources.remove(originalURL)
                    }
                    if saveURL.startAccessingSecurityScopedResource() {
                        self.accessingResources.insert(saveURL)
                    }
                    
                    // Update tab metadata for the active project
                    self.tabs[tabIndex].projectURL = saveURL
                    self.tabs[tabIndex].projectName = updatedProject.name
                } catch {
                    self.showError("Failed to save project: \(error.localizedDescription)")
                    return
                }
            } else {
                // Even if the URL didn't change, update the tab name
                self.tabs[tabIndex].projectName = updatedProject.name
            }
            
            // Once saved via an explicit Save / Save As, this is no longer temporary
            self.tabs[tabIndex].isTemporary = false
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
