//
//  RecentProjectsManager.swift
//  JamAI
//
//  Manages recent projects list with proper persistence and validation
//

import Foundation
import AppKit
import Combine

@MainActor
final class RecentProjectsManager: ObservableObject {
    @Published private(set) var recentProjects: [URL] = []
    
    private let userDefaultsKey = "recentProjectBookmarks"
    private let maxRecentProjects = 15  // Standard for professional macOS apps
    private let queue = DispatchQueue(label: "com.jamai.recentprojects", qos: .userInitiated)
    
    static let shared = RecentProjectsManager()
    
    private init() {
        // Load recents synchronously during init to ensure data is available immediately
        loadRecentsSync()
    }
    
    // MARK: - Public Interface
    
    /// Add a project to the recent list
    func recordRecent(url: URL) {
        // Normalize the URL
        let normalizedURL = normalizeProjectURL(url)
        
        // Update the list
        var list = recentProjects.filter { $0.standardizedFileURL != normalizedURL.standardizedFileURL }
        list.insert(normalizedURL, at: 0)
        if list.count > maxRecentProjects {
            list = Array(list.prefix(maxRecentProjects))
        }
        
        recentProjects = list
        
        // Save asynchronously to avoid blocking UI
        Task.detached(priority: .utility) { [weak self] in
            await self?.saveRecents()
        }
        
        // Also add to system recent documents for OS integration
        NSDocumentController.shared.noteNewRecentDocumentURL(normalizedURL)
    }
    
    /// Clear all recent projects
    func clearRecentProjects() {
        recentProjects = []
        queue.async { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: self.userDefaultsKey)
            UserDefaults.standard.synchronize()
        }
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
    
    /// Refresh the recent projects list, removing invalid entries
    func refreshRecentProjects() {
        loadRecents()
    }
    
    /// Remove a specific project from the recent list
    func removeRecent(url: URL) {
        let normalizedURL = normalizeProjectURL(url)
        recentProjects.removeAll { $0.standardizedFileURL == normalizedURL.standardizedFileURL }
        Task.detached(priority: .utility) { [weak self] in
            await self?.saveRecents()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadRecentsSync() {
        // Synchronous load during initialization
        let defaults = UserDefaults.standard
        guard let datas = defaults.array(forKey: userDefaultsKey) as? [Data], !datas.isEmpty else {
            print("📋 RecentProjectsManager: No saved bookmarks found")
            recentProjects = []
            return
        }
        
        print("📋 RecentProjectsManager: Loading \(datas.count) bookmarks...")
        
        // Process bookmarks synchronously
        let results = datas.compactMap { data -> (url: URL, needsRefresh: Bool)? in
            var stale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                
                if isValidProjectURLSync(url) {
                    print("✅ Loaded: \(url.lastPathComponent)")
                    return (url, stale)
                } else {
                    print("❌ Invalid: \(url.lastPathComponent)")
                }
            } catch {
                print("⚠️ Failed to resolve bookmark: \(error.localizedDescription)")
            }
            return nil
        }
        
        let validURLs = results.map { $0.url }
        recentProjects = validURLs
        print("📋 RecentProjectsManager: Loaded \(validURLs.count) valid projects")
        
        // Clean up stale bookmarks asynchronously if needed
        let needsCleanup = results.contains { $0.needsRefresh } || validURLs.count != datas.count
        if needsCleanup && !validURLs.isEmpty {
            Task.detached(priority: .utility) { [weak self] in
                await self?.saveRecents()
            }
        }
    }
    
    private func loadRecents() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let defaults = UserDefaults.standard
            guard let datas = defaults.array(forKey: self.userDefaultsKey) as? [Data] else {
                Task { @MainActor in
                    self.recentProjects = []
                }
                return
            }
            
            // Process bookmarks and collect results
            let results = datas.compactMap { data -> (url: URL, needsRefresh: Bool)? in
                var stale = false
                do {
                    let url = try URL(
                        resolvingBookmarkData: data,
                        options: [.withSecurityScope, .withoutUI],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale
                    )
                    
                    // Check validity without actor isolation
                    if self.isValidProjectURLSync(url) {
                        return (url, stale)
                    }
                } catch {
                    print("⚠️ Failed to resolve bookmark: \(error.localizedDescription)")
                }
                return nil
            }
            
            let validURLs = results.map { $0.url }
            let needsCleanup = results.contains { $0.needsRefresh } || validURLs.count != datas.count
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.recentProjects = validURLs
                
                // Save cleaned list if needed
                if needsCleanup && !validURLs.isEmpty {
                    Task.detached(priority: .utility) { [weak self] in
                        await self?.saveRecents()
                    }
                }
            }
        }
    }
    
    private func saveRecents() async {
        let urls = recentProjects
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var bookmarks: [Data] = []
            
            for url in urls {
                do {
                    // Create security-scoped bookmark
                    let bookmarkData = try url.bookmarkData(
                        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    bookmarks.append(bookmarkData)
                } catch {
                    print("⚠️ Failed to create bookmark for \(url.lastPathComponent): \(error.localizedDescription)")
                    // Continue processing other URLs instead of failing completely
                }
            }
            
            if !bookmarks.isEmpty {
                UserDefaults.standard.set(bookmarks, forKey: self.userDefaultsKey)
                UserDefaults.standard.synchronize()
            }
        }
    }
    
    nonisolated private func isValidProjectURLSync(_ url: URL) -> Bool {
        // Quick existence check first
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        
        // For .jam packages/directories, check for required files
        let jamExtension = "jam"
        if isDirectory.boolValue || url.pathExtension == jamExtension {
            let baseURL = normalizeProjectURLSync(url)
            let metadataPath = baseURL.appendingPathComponent("metadata.json").path
            let databasePath = baseURL.appendingPathComponent("data.db").path
            
            // Don't start security-scoped access here - just check existence
            // This prevents interfering with currently open projects
            return FileManager.default.fileExists(atPath: metadataPath) &&
                   FileManager.default.fileExists(atPath: databasePath)
        }
        
        return false
    }
    
    nonisolated private func normalizeProjectURLSync(_ url: URL) -> URL {
        // Ensure .jam extension
        let jamExtension = "jam"
        if url.pathExtension == jamExtension {
            return url
        }
        return url.appendingPathExtension(jamExtension)
    }
    
    private func normalizeProjectURL(_ url: URL) -> URL {
        // Ensure .jam extension
        if url.pathExtension == Config.jamFileExtension {
            return url
        }
        return url.appendingPathExtension(Config.jamFileExtension)
    }
}
