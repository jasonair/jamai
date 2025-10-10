//
//  DocumentManager.swift
//  JamAI
//
//  Manages .jam file operations and project bundles
//

import Foundation
import AppKit

class DocumentManager {
    static let shared = DocumentManager()
    
    private init() {}
    
    // MARK: - File Operations
    
    func createNewProject(name: String) throws -> (Project, URL) {
        let project = Project(name: name)
        let fileURL = try getDefaultSaveLocation(for: project)
        try saveProject(project, to: fileURL)
        return (project, fileURL)
    }
    
    func saveProject(_ project: Project, to url: URL, database: Database? = nil) throws {
        // Create bundle directory
        let bundleURL = url.appendingPathExtension(Config.jamFileExtension)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        
        // Database file inside bundle
        let dbURL = bundleURL.appendingPathComponent("data.db")
        
        // Use existing database or create new one
        let db: Database
        if let existingDB = database {
            db = existingDB
        } else {
            db = Database()
            try db.setup(at: dbURL)
        }
        
        // Save project metadata to database
        try db.saveProject(project)
        
        // Update metadata file
        let metadata: [String: Any] = [
            "version": "1.0",
            "projectId": project.id.uuidString,
            "projectName": project.name,
            "createdAt": ISO8601DateFormatter().string(from: project.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: project.updatedAt)
        ]
        
        let metadataURL = bundleURL.appendingPathComponent("metadata.json")
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try metadataData.write(to: metadataURL)
    }
    
    func openProject(from url: URL) throws -> (Project, Database) {
        let bundleURL = url.pathExtension == Config.jamFileExtension ? url : url.appendingPathExtension(Config.jamFileExtension)
        
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw DocumentError.fileNotFound
        }
        
        // Load database
        let dbURL = bundleURL.appendingPathComponent("data.db")
        let database = Database()
        try database.setup(at: dbURL)
        
        // Load metadata to get project ID
        let metadataURL = bundleURL.appendingPathComponent("metadata.json")
        let metadataData = try Data(contentsOf: metadataURL)
        guard let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
              let projectIdString = metadata["projectId"] as? String,
              let projectId = UUID(uuidString: projectIdString) else {
            throw DocumentError.invalidMetadata
        }
        
        // Load project from database
        guard let project = try database.loadProject(id: projectId) else {
            throw DocumentError.projectNotFound
        }
        
        return (project, database)
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
        }
    }
}
