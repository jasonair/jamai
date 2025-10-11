//
//  DatabaseActor.swift
//  JamAI
//
//  Serializes and executes all database I/O off the main actor to avoid UI blocking
//

import Foundation

actor DatabaseActor {
    private let db: Database
    
    init(db: Database) {
        self.db = db
    }
    
    // MARK: - Project
    func saveProject(_ project: Project) async throws {
        try db.saveProject(project)
    }
    
    // MARK: - Nodes
    func saveNode(_ node: Node) async throws {
        try db.saveNode(node)
    }
    
    func deleteNode(id: UUID) async throws {
        try db.deleteNode(id: id)
    }
    
    // MARK: - Edges
    func saveEdge(_ edge: Edge) async throws {
        try db.saveEdge(edge)
    }
    
    func deleteEdge(id: UUID) async throws {
        try db.deleteEdge(id: id)
    }
}
