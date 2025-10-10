//
//  RAGService.swift
//  JamAI
//
//  RAG (Retrieval Augmented Generation) service for document ingestion and search
//

import Foundation
import UniformTypeIdentifiers

class RAGService {
    private let geminiClient: GeminiClient
    private let database: Database
    
    init(geminiClient: GeminiClient, database: Database) {
        self.geminiClient = geminiClient
        self.database = database
    }
    
    // MARK: - Document Ingestion
    
    func ingestDocument(url: URL, projectId: UUID) async throws -> RAGDocument {
        let content = try loadDocument(from: url)
        let chunks = chunkText(content)
        
        var ragChunks: [RAGChunk] = []
        let documentId = UUID()
        
        for (index, chunkContent) in chunks.enumerated() {
            let embedding = try await geminiClient.generateEmbedding(text: chunkContent)
            
            var chunk = RAGChunk(
                documentId: documentId,
                content: chunkContent,
                chunkIndex: index
            )
            chunk.setEmbedding(embedding)
            ragChunks.append(chunk)
        }
        
        let document = RAGDocument(
            id: documentId,
            projectId: projectId,
            filename: url.lastPathComponent,
            content: content,
            chunks: ragChunks
        )
        
        try database.saveRAGDocument(document)
        return document
    }
    
    // MARK: - Search
    
    func search(query: String, projectId: UUID, k: Int, maxChars: Int) async throws -> String {
        // Generate embedding for query
        let queryEmbedding = try await geminiClient.generateEmbedding(text: query)
        
        // Load all chunks for project
        let chunks = try database.loadRAGChunks(projectId: projectId)
        
        guard !chunks.isEmpty else {
            return ""
        }
        
        // Calculate similarities and get top-k
        let chunkVectors = chunks.map { (id: $0.id, embedding: $0.embedding) }
        let topResults = VectorMath.topK(query: queryEmbedding, vectors: chunkVectors, k: k)
        
        // Build context string
        var contextParts: [String] = []
        var currentLength = 0
        
        for result in topResults {
            guard let chunk = chunks.first(where: { $0.id == result.id }) else { continue }
            
            let chunkText = "[\(result.similarity)]: \(chunk.content)"
            if currentLength + chunkText.count > maxChars {
                break
            }
            
            contextParts.append(chunkText)
            currentLength += chunkText.count
        }
        
        return contextParts.joined(separator: "\n\n")
    }
    
    // MARK: - Document Loading
    
    private func loadDocument(from url: URL) throws -> String {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "txt", "md":
            return try String(contentsOf: url, encoding: .utf8)
            
        case "pdf":
            return try loadPDF(from: url)
            
        case "docx":
            return try loadDOCX(from: url)
            
        default:
            throw RAGError.unsupportedFileType(fileExtension)
        }
    }
    
    private func loadPDF(from url: URL) throws -> String {
        // For now, return placeholder. Full PDF extraction requires PDFKit
        // TODO: Implement PDF extraction using PDFKit
        throw RAGError.unsupportedFileType("pdf")
    }
    
    private func loadDOCX(from url: URL) throws -> String {
        // For now, return placeholder. Full DOCX extraction requires additional parsing
        // TODO: Implement DOCX extraction
        throw RAGError.unsupportedFileType("docx")
    }
    
    // MARK: - Text Chunking
    
    private func chunkText(_ text: String) -> [String] {
        var chunks: [String] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        var currentChunk = ""
        var currentLength = 0
        
        for word in words {
            let wordLength = word.count + 1 // +1 for space
            
            if currentLength + wordLength > Config.ragChunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                
                // Start new chunk with overlap
                let overlapWords = currentChunk.components(separatedBy: .whitespacesAndNewlines)
                    .suffix(Config.ragChunkOverlap / 10) // Approximate word count
                currentChunk = overlapWords.joined(separator: " ") + " "
                currentLength = currentChunk.count
            }
            
            currentChunk += word + " "
            currentLength += wordLength
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return chunks
    }
}

// MARK: - Errors

enum RAGError: LocalizedError {
    case unsupportedFileType(String)
    case failedToReadFile
    case noChunksGenerated
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext)"
        case .failedToReadFile:
            return "Failed to read file contents"
        case .noChunksGenerated:
            return "No chunks generated from document"
        }
    }
}
