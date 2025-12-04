//
//  Database.swift
//  JamAI
//
//  SQLite database layer using GRDB
//

import Foundation
import GRDB

enum DatabaseError: Error {
    case readOnlyAccess
    case notInitialized
}

final class Database: Sendable {
    // GRDB's DatabaseQueue is thread-safe, so we can safely use it across actors
    nonisolated(unsafe) private var dbQueue: DatabaseQueue?
    private(set) var isReadOnly: Bool = false
    
    init() {}
    
    // MARK: - Setup
    
    func setup(at url: URL) throws {
        // Always try to open in read-write mode
        var config = Configuration()
        config.readonly = false
        
        do {
            dbQueue = try DatabaseQueue(path: url.path, configuration: config)
            isReadOnly = false
            if let dbQueue = dbQueue {
                do {
                    try dbQueue.inDatabase { db in
                        try db.execute(sql: "PRAGMA journal_mode=MEMORY")
                        try db.execute(sql: "PRAGMA temp_store=MEMORY")
                        if let mode = try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased() {
                            if Config.enableVerboseLogging { print("ℹ️ SQLite journal_mode after request: \(mode)") }
                        }
                        try? db.execute(sql: "PRAGMA synchronous=NORMAL")
                        try db.execute(sql: "PRAGMA foreign_keys=ON")
                    }
                } catch {
                    if Config.enableVerboseLogging { print("⚠️ Failed to set PRAGMAs pre-migration: \(error.localizedDescription). Proceeding with defaults.") }
                }
            }
            try migrate()
            // Diagnostics: check directory writability
            let dirURL = url.deletingLastPathComponent()
            let dirWritable = FileManager.default.isWritableFile(atPath: dirURL.path)
            if Config.enableVerboseLogging { print("ℹ️ Database directory: \(dirURL.path), writable: \(dirWritable)") }
            // Probe write to trigger journaling
            if let dbQueue = dbQueue {
                do {
                    try dbQueue.write { _ in /* no-op write to test journaling */ }
                } catch {
                    if Config.enableVerboseLogging { print("⚠️ Initial write failed: \(error.localizedDescription).") }
                }
            }
        } catch let dbError {
            // If opening in write mode fails, throw a clear error
            if Config.enableVerboseLogging {
                print("⚠️ Cannot open database in write mode: \(dbError)")
                print("⚠️ Database path: \(url.path)")
                print("⚠️ File exists: \(FileManager.default.fileExists(atPath: url.path))")
                print("⚠️ Is writable: \(FileManager.default.isWritableFile(atPath: url.path))")
            }
            
            // Try to get more info about permissions
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                if Config.enableVerboseLogging { print("⚠️ File permissions: \(attrs[.posixPermissions] ?? "unknown")") }
            }
            
            throw DatabaseError.readOnlyAccess
        }
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
                t.column("canvas_offset_x", .double).notNull().defaults(to: 0)
                t.column("canvas_offset_y", .double).notNull().defaults(to: 0)
                t.column("canvas_zoom", .double).notNull().defaults(to: 1.0)
                t.column("show_dots", .boolean).notNull().defaults(to: true)
                t.column("background_style", .text).notNull().defaults(to: "grid")
                t.column("background_color_id", .text)
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
                t.column("width", .double).notNull().defaults(to: 400)
                t.column("height", .double).notNull().defaults(to: 400)
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
                t.column("is_expanded", .boolean).notNull().defaults(to: true)
                t.column("is_frozen_context", .boolean).notNull().defaults(to: false)
                t.column("color", .text).notNull().defaults(to: "none")
                t.column("type", .text).notNull().defaults(to: "standard")
                t.column("font_size", .double).notNull().defaults(to: 16)
                t.column("is_bold", .boolean).notNull().defaults(to: false)
                t.column("font_family", .text)
                t.column("shape_kind", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            
            // Add conversation_json column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "conversation_json" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "conversation_json", .text).notNull().defaults(to: "[]")
                }
            }
            
            // Add height column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "height" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "height", .double).notNull().defaults(to: 400)
                }
            }
            
            // Add width column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "width" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "width", .double).notNull().defaults(to: 400)
                }
            }
            
            // Add canvas state columns if they don't exist (migration)
            if try db.columns(in: "projects").first(where: { $0.name == "canvas_offset_x" }) == nil {
                try db.alter(table: "projects") { t in
                    t.add(column: "canvas_offset_x", .double).notNull().defaults(to: 0)
                    t.add(column: "canvas_offset_y", .double).notNull().defaults(to: 0)
                    t.add(column: "canvas_zoom", .double).notNull().defaults(to: 1.0)
                }
            }
            
            // Add show_dots column if it doesn't exist (migration)
            if try db.columns(in: "projects").first(where: { $0.name == "show_dots" }) == nil {
                try db.alter(table: "projects") { t in
                    t.add(column: "show_dots", .boolean).notNull().defaults(to: true)
                }
            }
            
            // Add background_style column if it doesn't exist (migration)
            if try db.columns(in: "projects").first(where: { $0.name == "background_style" }) == nil {
                try db.alter(table: "projects") { t in
                    t.add(column: "background_style", .text).notNull().defaults(to: "grid")
                }
            }
            
            // Add background_color_id column if it doesn't exist (migration)
            if try db.columns(in: "projects").first(where: { $0.name == "background_color_id" }) == nil {
                try db.alter(table: "projects") { t in
                    t.add(column: "background_color_id", .text)
                }
            }
            
            // Add color column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "color" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "color", .text).notNull().defaults(to: "none")
                }
            }
            // Add type column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "type" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "type", .text).notNull().defaults(to: "standard")
                }
            }
            // Add text/shape formatting columns if they don't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "font_size" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "font_size", .double).notNull().defaults(to: 16)
                }
            }
            if try db.columns(in: "nodes").first(where: { $0.name == "is_bold" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "is_bold", .boolean).notNull().defaults(to: false)
                }
            }
            if try db.columns(in: "nodes").first(where: { $0.name == "font_family" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "font_family", .text)
                }
            }
            if try db.columns(in: "nodes").first(where: { $0.name == "shape_kind" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "shape_kind", .text)
                }
            }
            // Add display_order column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "display_order" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "display_order", .integer)
                }
            }
            // Add team_member_json column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "team_member_json" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "team_member_json", .text)
                }
            }
            // Add personality column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "personality" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "personality", .text)
                }
            }
            // Add image_data column if it doesn't exist (migration)
            if try db.columns(in: "nodes").first(where: { $0.name == "image_data" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "image_data", .blob)
                }
            }
            
            // Add embedding columns if they don't exist (migration for RAG)
            if try db.columns(in: "nodes").first(where: { $0.name == "embedding_json" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "embedding_json", .text)
                }
            }
            if try db.columns(in: "nodes").first(where: { $0.name == "embedding_updated_at" }) == nil {
                try db.alter(table: "nodes") { t in
                    t.add(column: "embedding_updated_at", .datetime)
                }
            }
            
            // Edges table
            try db.create(table: "edges", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
                t.column("source_id", .text).notNull().references("nodes", onDelete: .cascade)
                t.column("target_id", .text).notNull().references("nodes", onDelete: .cascade)
                t.column("color", .text)
                t.column("created_at", .datetime).notNull()
            }
            // Add color column to edges if it doesn't exist (migration)
            if try db.columns(in: "edges").first(where: { $0.name == "color" }) == nil {
                try db.alter(table: "edges") { t in
                    t.add(column: "color", .text)
                }
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
    
    nonisolated func saveProject(_ project: Project) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO projects 
                (id, name, system_prompt, k_turns, include_summaries, include_rag, rag_k, rag_max_chars, appearance_mode, canvas_offset_x, canvas_offset_y, canvas_zoom, show_dots, background_style, background_color_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    project.canvasOffsetX,
                    project.canvasOffsetY,
                    project.canvasZoom,
                    project.showDots,
                    project.backgroundStyle.rawValue,
                    project.backgroundColorId,
                    project.createdAt,
                    project.updatedAt
                ]
            )
        }
    }
    
    nonisolated func loadProject(id: UUID) throws -> Project? {
        guard let dbQueue = dbQueue else { return nil }
        
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM projects WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            
            let showDots: Bool = row["show_dots"] ?? true
            let backgroundStyle: CanvasBackgroundStyle
            if let raw: String = row["background_style"] {
                if raw == "color" {
                    // Legacy dedicated color mode now maps to blank pattern + tint
                    backgroundStyle = .blank
                } else if let parsed = CanvasBackgroundStyle(rawValue: raw) {
                    // If the DB was migrated from a version that only had show_dots,
                    // the new background_style column will default to "grid". In that
                    // case, preserve the user's dots preference.
                    if raw == "grid" && showDots {
                        backgroundStyle = .dots
                    } else {
                        backgroundStyle = parsed
                    }
                } else {
                    backgroundStyle = showDots ? .dots : .grid
                }
            } else {
                backgroundStyle = showDots ? .dots : .grid
            }
            let backgroundColorId: String? = row["background_color_id"]
            
            return Project(
                id: UUID(uuidString: row["id"])!,
                name: row["name"],
                systemPrompt: row["system_prompt"],
                kTurns: row["k_turns"],
                includeSummaries: row["include_summaries"],
                includeRAG: row["include_rag"],
                ragK: row["rag_k"],
                ragMaxChars: row["rag_max_chars"],
                appearanceMode: AppearanceMode(rawValue: row["appearance_mode"]) ?? .system,
                canvasOffsetX: row["canvas_offset_x"] ?? 0,
                canvasOffsetY: row["canvas_offset_y"] ?? 0,
                canvasZoom: row["canvas_zoom"] ?? 1.0,
                showDots: showDots,
                backgroundStyle: backgroundStyle,
                backgroundColorId: backgroundColorId
            )
        }
    }
    
    nonisolated func loadAnyProject() throws -> Project? {
        guard let dbQueue = dbQueue else { return nil }
        
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM projects LIMIT 1") else {
                return nil
            }
            
            let showDots: Bool = row["show_dots"] ?? true
            let backgroundStyle: CanvasBackgroundStyle
            if let raw: String = row["background_style"] {
                if raw == "color" {
                    backgroundStyle = .blank
                } else if let parsed = CanvasBackgroundStyle(rawValue: raw) {
                    if raw == "grid" && showDots {
                        backgroundStyle = .dots
                    } else {
                        backgroundStyle = parsed
                    }
                } else {
                    backgroundStyle = showDots ? .dots : .grid
                }
            } else {
                backgroundStyle = showDots ? .dots : .grid
            }
            let backgroundColorId: String? = row["background_color_id"]
            
            return Project(
                id: UUID(uuidString: row["id"])!,
                name: row["name"],
                systemPrompt: row["system_prompt"],
                kTurns: row["k_turns"],
                includeSummaries: row["include_summaries"],
                includeRAG: row["include_rag"],
                ragK: row["rag_k"],
                ragMaxChars: row["rag_max_chars"],
                appearanceMode: AppearanceMode(rawValue: row["appearance_mode"]) ?? .system,
                canvasOffsetX: row["canvas_offset_x"] ?? 0,
                canvasOffsetY: row["canvas_offset_y"] ?? 0,
                canvasZoom: row["canvas_zoom"] ?? 1.0,
                showDots: showDots,
                backgroundStyle: backgroundStyle,
                backgroundColorId: backgroundColorId
            )
        }
    }
    
    // MARK: - Nodes
    
    nonisolated func saveNode(_ node: Node) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO nodes 
                (id, project_id, parent_id, x, y, width, height, title, title_source, description, description_source, 
                 conversation_json, prompt, response, ancestry_json, summary, system_prompt_snapshot, team_member_json, personality, is_expanded, is_frozen_context, color, type, font_size, is_bold, font_family, shape_kind, image_data, embedding_json, embedding_updated_at, display_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    node.id.uuidString,
                    node.projectId.uuidString,
                    node.parentId?.uuidString,
                    node.x,
                    node.y,
                    node.width,
                    node.height,
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
                    node.teamMemberJSON,
                    node.personalityRawValue,
                    node.isExpanded,
                    node.isFrozenContext,
                    node.color,
                    node.type.rawValue,
                    node.fontSize,
                    node.isBold,
                    node.fontFamily,
                    node.shapeKind?.rawValue,
                    node.imageData,
                    node.embeddingJSON,
                    node.embeddingUpdatedAt,
                    node.displayOrder,
                    node.createdAt,
                    node.updatedAt
                ]
            )
        }
    }
    
    nonisolated func loadNodes(projectId: UUID) throws -> [Node] {
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
                    width: row["width"] ?? 400,
                    height: row["height"] ?? 400,
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
                    teamMemberJSON: row["team_member_json"] as String?,
                    personalityRawValue: row["personality"] as String?,
                    isExpanded: row["is_expanded"],
                    isFrozenContext: row["is_frozen_context"],
                    color: row["color"] ?? "none",
                    type: NodeType(rawValue: row["type"]) ?? .standard,
                    fontSize: row["font_size"] ?? 16,
                    isBold: row["is_bold"] ?? false,
                    fontFamily: row["font_family"] as String?,
                    shapeKind: (row["shape_kind"] as String?).flatMap { ShapeKind(rawValue: $0) },
                    imageData: row["image_data"] as Data?,
                    embeddingJSON: row["embedding_json"] as String?,
                    embeddingUpdatedAt: row["embedding_updated_at"] as Date?,
                    displayOrder: row["display_order"] as Int?,
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"]
                )
            }
        }
    }
    
    nonisolated func deleteNode(id: UUID) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM nodes WHERE id = ?", arguments: [id.uuidString])
        }
    }
    
    // MARK: - Edges
    
    nonisolated func saveEdge(_ edge: Edge) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO edges 
                (id, project_id, source_id, target_id, color, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    edge.id.uuidString,
                    edge.projectId.uuidString,
                    edge.sourceId.uuidString,
                    edge.targetId.uuidString,
                    edge.color,
                    edge.createdAt
                ]
            )
        }
    }
    
    nonisolated func loadEdges(projectId: UUID) throws -> [Edge] {
        guard let dbQueue = dbQueue else { return [] }
        
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM edges WHERE project_id = ?", arguments: [projectId.uuidString])
            
            return rows.map { row in
                Edge(
                    id: UUID(uuidString: row["id"])!,
                    projectId: UUID(uuidString: row["project_id"])!,
                    sourceId: UUID(uuidString: row["source_id"])!,
                    targetId: UUID(uuidString: row["target_id"])!,
                    color: row["color"] as String?,
                    createdAt: row["created_at"]
                )
            }
        }
    }
    
    nonisolated func deleteEdge(id: UUID) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM edges WHERE id = ?", arguments: [id.uuidString])
        }
    }
    
    // MARK: - RAG
    
    nonisolated func saveRAGDocument(_ document: RAGDocument) throws {
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
    
    nonisolated func loadRAGChunks(projectId: UUID) throws -> [RAGChunk] {
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
