//
//  Database.swift
//  JamAI
//
//  SQLite database layer using GRDB
//

import Foundation
import GRDB

class Database {
    private var dbQueue: DatabaseQueue?
    
    init() {}
    
    // MARK: - Setup
    
    func setup(at url: URL) throws {
        dbQueue = try DatabaseQueue(path: url.path)
        try migrate()
    }
    
    private func migrate() throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            // Projects table
            try db.create(table: "projects", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("system_prompt", .text).notNull()
                t.column("k_turns", .integer).notNull().defaults(to: Config.defaultKTurns)
                t.column("include_summaries", .boolean).notNull().defaults(to: true)
                t.column("include_rag", .boolean).notNull().defaults(to: false)
                t.column("rag_k", .integer).notNull().defaults(to: Config.defaultRAGK)
                t.column("rag_max_chars", .integer).notNull().defaults(to: Config.defaultRAGMaxChars)
                t.column("appearance_mode", .text).notNull().defaults(to: "system")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            
            // Nodes table
            try db.create(table: "nodes", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
                t.column("parent_id", .text)
                t.column("x", .double).notNull()
                t.column("y", .double).notNull()
                t.column("title", .text).notNull()
                t.column("title_source", .text).notNull()
                t.column("description", .text).notNull()
                t.column("description_source", .text).notNull()
                t.column("conversation_json", .text).notNull().defaults(to: "[]")
                t.column("prompt", .text).notNull()
                t.column("response", .text).notNull()
                t.column("ancestry_json", .text).notNull()
                t.column("summary", .text)
                t.column("system_prompt_snapshot", .text)
                t.column("is_expanded", .boolean).notNull().defaults(to: false)
                t.column("is_frozen_context", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            
            // Add conversation_json column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "conversation_json" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "conversation_json", .text).notNull().defaults(to: "[]")
                }
            }
            
            // Edges table
            try db.create(table: "edges", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
                t.column("source_id", .text).notNull().references("nodes", onDelete: .cascade)
                t.column("target_id", .text).notNull().references("nodes", onDelete: .cascade)
                t.column("created_at", .datetime).notNull()
            }
            
            // RAG Documents table
            try db.create(table: "rag_documents", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
                t.column("filename", .text).notNull()
                t.column("content", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
            
            // RAG Chunks table
            try db.create(table: "rag_chunks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("document_id", .text).notNull().references("rag_documents", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("embedding_json", .text).notNull()
                t.column("chunk_index", .integer).notNull()
            }
            
            // Indexes
            try db.create(index: "idx_nodes_project", on: "nodes", columns: ["project_id"], ifNotExists: true)
            try db.create(index: "idx_edges_project", on: "edges", columns: ["project_id"], ifNotExists: true)
            try db.create(index: "idx_edges_source", on: "edges", columns: ["source_id"], ifNotExists: true)
            try db.create(index: "idx_edges_target", on: "edges", columns: ["target_id"], ifNotExists: true)
            try db.create(index: "idx_rag_chunks_document", on: "rag_chunks", columns: ["document_id"], ifNotExists: true)
        }
    }
    
    // MARK: - Projects
    
    func saveProject(_ project: Project) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO projects 
                (id, name, system_prompt, k_turns, include_summaries, include_rag, rag_k, rag_max_chars, appearance_mode, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    project.id.uuidString,
                    project.name,
                    project.systemPrompt,
                    project.kTurns,
                    project.includeSummaries,
                    project.includeRAG,
                    project.ragK,
                    project.ragMaxChars,
                    project.appearanceMode.rawValue,
                    project.createdAt,
                    project.updatedAt
                ]
            )
        }
    }
    
    func loadProject(id: UUID) throws -> Project? {
        guard let dbQueue = dbQueue else { return nil }
        
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM projects WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            
            return Project(
                id: UUID(uuidString: row["id"])!,
                name: row["name"],
                systemPrompt: row["system_prompt"],
                kTurns: row["k_turns"],
                includeSummaries: row["include_summaries"],
                includeRAG: row["include_rag"],
                ragK: row["rag_k"],
                ragMaxChars: row["rag_max_chars"],
                appearanceMode: AppearanceMode(rawValue: row["appearance_mode"]) ?? .system
            )
        }
    }
    
    // MARK: - Nodes
    
    func saveNode(_ node: Node) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO nodes 
                (id, project_id, parent_id, x, y, title, title_source, description, description_source, 
                 conversation_json, prompt, response, ancestry_json, summary, system_prompt_snapshot, is_expanded, is_frozen_context, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    node.id.uuidString,
                    node.projectId.uuidString,
                    node.parentId?.uuidString,
                    node.x,
                    node.y,
                    node.title,
                    node.titleSource.rawValue,
                    node.description,
                    node.descriptionSource.rawValue,
                    node.conversationJSON,
                    node.prompt,
                    node.response,
                    node.ancestryJSON,
                    node.summary,
                    node.systemPromptSnapshot,
                    node.isExpanded,
                    node.isFrozenContext,
                    node.createdAt,
                    node.updatedAt
                ]
            )
        }
    }
    
    func loadNodes(projectId: UUID) throws -> [Node] {
        guard let dbQueue = dbQueue else { return [] }
        
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM nodes WHERE project_id = ?", arguments: [projectId.uuidString])
            
            return rows.map { row in
                Node(
                    id: UUID(uuidString: row["id"])!,
                    projectId: UUID(uuidString: row["project_id"])!,
                    parentId: (row["parent_id"] as String?).flatMap { UUID(uuidString: $0) },
                    x: row["x"],
                    y: row["y"],
                    title: row["title"],
                    titleSource: TextSource(rawValue: row["title_source"]) ?? .user,
                    description: row["description"],
                    descriptionSource: TextSource(rawValue: row["description_source"]) ?? .user,
                    conversationJSON: row["conversation_json"] ?? "[]",
                    prompt: row["prompt"],
                    response: row["response"],
                    ancestryJSON: row["ancestry_json"],
                    summary: row["summary"],
                    systemPromptSnapshot: row["system_prompt_snapshot"],
                    isExpanded: row["is_expanded"],
                    isFrozenContext: row["is_frozen_context"]
                )
            }
        }
    }
    
    func deleteNode(id: UUID) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM nodes WHERE id = ?", arguments: [id.uuidString])
        }
    }
    
    // MARK: - Edges
    
    func saveEdge(_ edge: Edge) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO edges 
                (id, project_id, source_id, target_id, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    edge.id.uuidString,
                    edge.projectId.uuidString,
                    edge.sourceId.uuidString,
                    edge.targetId.uuidString,
                    edge.createdAt
                ]
            )
        }
    }
    
    func loadEdges(projectId: UUID) throws -> [Edge] {
        guard let dbQueue = dbQueue else { return [] }
        
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM edges WHERE project_id = ?", arguments: [projectId.uuidString])
            
            return rows.map { row in
                Edge(
                    id: UUID(uuidString: row["id"])!,
                    projectId: UUID(uuidString: row["project_id"])!,
                    sourceId: UUID(uuidString: row["source_id"])!,
                    targetId: UUID(uuidString: row["target_id"])!
                )
            }
        }
    }
    
    func deleteEdge(id: UUID) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM edges WHERE id = ?", arguments: [id.uuidString])
        }
    }
    
    // MARK: - RAG
    
    func saveRAGDocument(_ document: RAGDocument) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO rag_documents 
                (id, project_id, filename, content, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    document.id.uuidString,
                    document.projectId.uuidString,
                    document.filename,
                    document.content,
                    document.createdAt
                ]
            )
            
            // Save chunks
            for chunk in document.chunks {
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO rag_chunks 
                    (id, document_id, content, embedding_json, chunk_index)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.id.uuidString,
                        chunk.documentId.uuidString,
                        chunk.content,
                        chunk.embeddingJSON,
                        chunk.chunkIndex
                    ]
                )
            }
        }
    }
    
    func loadRAGChunks(projectId: UUID) throws -> [RAGChunk] {
        guard let dbQueue = dbQueue else { return [] }
        
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.* FROM rag_chunks c
                JOIN rag_documents d ON c.document_id = d.id
                WHERE d.project_id = ?
                """, arguments: [projectId.uuidString])
            
            return rows.map { row in
                RAGChunk(
                    id: UUID(uuidString: row["id"])!,
                    documentId: UUID(uuidString: row["document_id"])!,
                    content: row["content"],
                    embeddingJSON: row["embedding_json"],
                    chunkIndex: row["chunk_index"]
                )
            }
        }
    }
}
