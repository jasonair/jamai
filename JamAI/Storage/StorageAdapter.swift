//
//  StorageAdapter.swift
//  JamAI
//
//  Platform-abstracted storage adapter to enable macOS/Windows/Web implementations
//

import Foundation

protocol StorageAdapter {
    // Returns a suggested default save location for a project (without the .jam extension applied by callers).
    func defaultSaveLocation(for project: Project) throws -> URL
    
    // Ensures a .jam directory exists at the provided baseURL (adds extension if missing) and returns the bundle URL.
    func ensureProjectBundle(at baseURL: URL) throws -> URL
    
    // Normalize any project URL to the .jam directory URL.
    func normalizeProjectURL(_ url: URL) -> URL
    
    // Platform-specific access hooks (e.g., macOS security-scoped URLs).
    @discardableResult
    func startAccessing(_ bundleURL: URL) -> Bool
    func stopAccessing(_ bundleURL: URL)
    
    // Open a writable Database connection for the given bundle.
    func openWritableDatabase(at bundleURL: URL) throws -> Database
    
    // Persist metadata.json atomically.
    func saveMetadata(_ project: Project, at bundleURL: URL) throws
}

struct DefaultStorageAdapter: StorageAdapter {
    func defaultSaveLocation(for project: Project) throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let projectsURL = documentsURL.appendingPathComponent("JamAI Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        let sanitizedName = project.name.replacingOccurrences(of: "/", with: "-")
        return projectsURL.appendingPathComponent(sanitizedName)
    }
    
    func ensureProjectBundle(at baseURL: URL) throws -> URL {
        let bundleURL = normalizeProjectURL(baseURL)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        return bundleURL
    }
    
    func normalizeProjectURL(_ url: URL) -> URL {
        if url.pathExtension == Config.jamFileExtension { return url }
        return url.appendingPathExtension(Config.jamFileExtension)
    }
    
    @discardableResult
    func startAccessing(_ bundleURL: URL) -> Bool { false }
    
    func stopAccessing(_ bundleURL: URL) { /* no-op */ }
    
    func openWritableDatabase(at bundleURL: URL) throws -> Database {
        let dbURL = bundleURL.appendingPathComponent("data.db")
        let db = Database()
        try db.setup(at: dbURL)
        return db
    }
    
    func saveMetadata(_ project: Project, at bundleURL: URL) throws {
        let formatter = ISO8601DateFormatter()
        let metadata: [String: Any] = [
            "version": "1.0",
            "projectId": project.id.uuidString,
            "projectName": project.name,
            "createdAt": formatter.string(from: project.createdAt),
            "updatedAt": formatter.string(from: project.updatedAt)
        ]
        let url = bundleURL.appendingPathComponent("metadata.json")
        let data = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try data.write(to: url, options: .atomic)
    }
}
