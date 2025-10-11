//
//  Project.swift
//  JamAI
//
//  Represents a JamAI project (.jam file)
//

import Foundation
import SwiftUI

struct Project: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var createdAt: Date
    var updatedAt: Date
    
    // Context settings
    var kTurns: Int
    var includeSummaries: Bool
    var includeRAG: Bool
    var ragK: Int
    var ragMaxChars: Int
    
    // Appearance
    var appearanceMode: AppearanceMode
    
    // Canvas view state
    var canvasOffsetX: Double
    var canvasOffsetY: Double
    var canvasZoom: Double
    
    nonisolated init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String = "You are a helpful AI assistant.",
        kTurns: Int = 10,
        includeSummaries: Bool = true,
        includeRAG: Bool = false,
        ragK: Int = 5,
        ragMaxChars: Int = 2000,
        appearanceMode: AppearanceMode = .system,
        canvasOffsetX: Double = 0,
        canvasOffsetY: Double = 0,
        canvasZoom: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.kTurns = kTurns
        self.includeSummaries = includeSummaries
        self.includeRAG = includeRAG
        self.ragK = ragK
        self.ragMaxChars = ragMaxChars
        self.appearanceMode = appearanceMode
        self.canvasOffsetX = canvasOffsetX
        self.canvasOffsetY = canvasOffsetY
        self.canvasZoom = canvasZoom
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system = "System Auto"
    case light = "Light"
    case dark = "Dark"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - RAG Document
struct RAGDocument: Identifiable, Codable, Sendable {
    let id: UUID
    var projectId: UUID
    var filename: String
    var content: String
    var chunks: [RAGChunk]
    var createdAt: Date
    
    nonisolated init(
        id: UUID = UUID(),
        projectId: UUID,
        filename: String,
        content: String,
        chunks: [RAGChunk] = []
    ) {
        self.id = id
        self.projectId = projectId
        self.filename = filename
        self.content = content
        self.chunks = chunks
        self.createdAt = Date()
    }
}

struct RAGChunk: Identifiable, Codable, Sendable {
    let id: UUID
    var documentId: UUID
    var content: String
    var embeddingJSON: String // JSON array of floats
    var chunkIndex: Int
    
    nonisolated init(
        id: UUID = UUID(),
        documentId: UUID,
        content: String,
        embeddingJSON: String = "[]",
        chunkIndex: Int = 0
    ) {
        self.id = id
        self.documentId = documentId
        self.content = content
        self.embeddingJSON = embeddingJSON
        self.chunkIndex = chunkIndex
    }
    
    var embedding: [Float] {
        guard let data = embeddingJSON.data(using: .utf8),
              let array = try? JSONDecoder().decode([Float].self, from: data) else {
            return []
        }
        return array
    }
    
    mutating func setEmbedding(_ floats: [Float]) {
        if let data = try? JSONEncoder().encode(floats),
           let json = String(data: data, encoding: .utf8) {
            self.embeddingJSON = json
        }
    }
}
