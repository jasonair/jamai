//
//  DocumentManager.swift
//  JamAI
//
//  Manages .jam file operations and project bundles
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

class DocumentManager {
#if canImport(AppKit)
    static let shared = DocumentManager(adapter: MacStorageAdapter())
#else
    static let shared = DocumentManager(adapter: DefaultStorageAdapter())
#endif
    
    private let adapter: StorageAdapter
    
    private init(adapter: StorageAdapter) {
        self.adapter = adapter
    }
    
    // MARK: - File Operations
    
    func createNewProject(name: String) throws -> (Project, URL) {
        let project = Project(name: name)
        let fileURL = try adapter.defaultSaveLocation(for: project)
        try saveProject(project, to: fileURL)
        return (project, fileURL)
    }
    
    func saveProject(_ project: Project, to url: URL, database: Database? = nil) throws {
        // Ensure bundle exists (.jam directory)
        let bundleURL = try adapter.ensureProjectBundle(at: url)
        // Acquire temporary access only if caller didn't supply an open database (e.g., first save or external flows)
        let manageSecurity = (database == nil)
        let started = manageSecurity ? adapter.startAccessing(bundleURL) : false
        defer { if manageSecurity && started { adapter.stopAccessing(bundleURL) } }
        
        // Use existing database connection if provided; otherwise open a write-capable one
        let db: Database = try database ?? adapter.openWritableDatabase(at: bundleURL)
        
        // Save project metadata to database
        try db.saveProject(project)
        
        // Update metadata.json atomically via adapter
        try adapter.saveMetadata(project, at: bundleURL)
    }
    
    func openProject(from url: URL) throws -> (Project, Database) {
        // Normalize URL to .jam directory for file operations; security scope handled by caller
        let bundleURL = adapter.normalizeProjectURL(url)
        
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw DocumentError.fileNotFound
        }
        
        // Check if it's a directory (bundle)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DocumentError.invalidProjectStructure
        }
        
        let dbURL = bundleURL.appendingPathComponent("data.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw DocumentError.databaseNotFound
        }
        let database = try adapter.openWritableDatabase(at: bundleURL)
        let metadataURL = bundleURL.appendingPathComponent("metadata.json")
        var loadedProject: Project?
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let idString = (dict["projectId"] as? String) ?? (dict["id"] as? String)
                if let idString, let pid = UUID(uuidString: idString) {
                    loadedProject = try database.loadProject(id: pid)
                }
            }
        }
        if loadedProject == nil {
            if let anyProject = try database.loadAnyProject() {
                loadedProject = anyProject
                let formatter = ISO8601DateFormatter()
                let metadata: [String: Any] = [
                    "version": "1.0",
                    "projectId": anyProject.id.uuidString,
                    "projectName": anyProject.name,
                    "createdAt": formatter.string(from: anyProject.createdAt),
                    "updatedAt": formatter.string(from: anyProject.updatedAt)
                ]
                let data = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
                try data.write(to: metadataURL, options: .atomic)
            } else {
                throw DocumentError.projectNotFound
            }
        }
        return (loadedProject!, database)
    }

    func repairMetadata(at url: URL) throws {
        let bundleURL = adapter.normalizeProjectURL(url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let dbURL = bundleURL.appendingPathComponent("data.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return }
        let database = Database()
        try database.setup(at: dbURL)
        guard let project = try database.loadAnyProject() else { return }
        let formatter = ISO8601DateFormatter()
        let metadata: [String: Any] = [
            "version": "1.0",
            "projectId": project.id.uuidString,
            "projectName": project.name,
            "createdAt": formatter.string(from: project.createdAt),
            "updatedAt": formatter.string(from: project.updatedAt)
        ]
        let metadataURL = bundleURL.appendingPathComponent("metadata.json")
        let data = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try data.write(to: metadataURL, options: .atomic)
    }
    
    func exportJSON(project: Project, nodes: [Node], edges: [Edge], to url: URL) throws {
        let exportData: [String: Any] = [
            "project": try encodable(project),
            "nodes": nodes.map { try? encodable($0) }.compactMap { $0 },
            "edges": edges.map { try? encodable($0) }.compactMap { $0 }
        ]
        
        let data = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        try data.write(to: url)
    }
    
    func exportMarkdown(project: Project, nodes: [Node], edges: [Edge], to url: URL) throws {
        var markdown = "# \(project.name)\n\n"
        markdown += "**Created:** \(formatDate(project.createdAt))\n\n"
        markdown += "## System Prompt\n\n\(project.systemPrompt)\n\n"
        markdown += "## Nodes\n\n"
        
        for node in nodes.sorted(by: { $0.createdAt < $1.createdAt }) {
            markdown += "### \(node.title.isEmpty ? "Untitled" : node.title)\n\n"
            
            if !node.description.isEmpty {
                markdown += "*\(node.description)*\n\n"
            }
            
            if !node.prompt.isEmpty {
                markdown += "**Prompt:**\n\n\(node.prompt)\n\n"
            }
            
            if !node.response.isEmpty {
                markdown += "**Response:**\n\n\(node.response)\n\n"
            }
            
            markdown += "---\n\n"
        }
        
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Helper Methods
    
    private func getDefaultSaveLocation(for project: Project) throws -> URL {
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
    
    private func encodable<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DocumentError.encodingFailed
        }
        return dict
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Errors

enum DocumentError: LocalizedError {
    case fileNotFound
    case invalidMetadata
    case projectNotFound
    case encodingFailed
    case invalidProjectStructure
    case databaseNotFound
    case metadataNotFound
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Project file not found"
        case .invalidMetadata:
            return "Invalid project metadata"
        case .projectNotFound:
            return "Project data not found in database"
        case .encodingFailed:
            return "Failed to encode project data"
        case .invalidProjectStructure:
            return "Invalid project structure - expected a .jam directory"
        case .databaseNotFound:
            return "Database file not found in project bundle"
        case .metadataNotFound:
            return "Metadata file not found in project bundle"
        }
    }
}
