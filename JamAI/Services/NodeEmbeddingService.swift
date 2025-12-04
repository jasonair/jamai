//
//  NodeEmbeddingService.swift
//  JamAI
//
//  Service for generating and managing node embeddings for RAG-based context retrieval
//

import Foundation

/// Service for generating semantic embeddings for nodes
/// Used for RAG-based context retrieval when nodes are connected via edges
@MainActor
class NodeEmbeddingService {
    private let geminiClient: GeminiClient
    
    /// Maximum characters to include in embedding content (~7.5k tokens)
    private let maxEmbeddingChars = 30000
    
    /// Maximum conversation messages to include in embedding
    private let maxConversationMessages = 10
    
    init(geminiClient: GeminiClient) {
        self.geminiClient = geminiClient
    }
    
    // MARK: - Embedding Generation
    
    /// Generate embedding for a node's content
    /// - Parameter node: The node to generate embedding for
    /// - Returns: The embedding vector as an array of floats
    func generateEmbedding(for node: Node) async throws -> [Float] {
        let content = buildEmbeddingContent(from: node)
        
        guard !content.isEmpty else {
            throw EmbeddingError.emptyContent
        }
        
        return try await geminiClient.generateEmbedding(text: content)
    }
    
    /// Update a node's embedding if needed
    /// - Parameters:
    ///   - node: The node to update (inout)
    ///   - force: If true, regenerate even if embedding is current
    /// - Returns: True if embedding was updated, false if skipped
    @discardableResult
    func updateEmbeddingIfNeeded(for node: inout Node, force: Bool = false) async throws -> Bool {
        // Skip if embedding is current and not forced
        guard force || node.needsEmbeddingUpdate else {
            return false
        }
        
        // Skip nodes with no meaningful content
        let content = buildEmbeddingContent(from: node)
        guard !content.isEmpty else {
            return false
        }
        
        let embedding = try await generateEmbedding(for: node)
        node.setEmbedding(embedding)
        
        if Config.enableVerboseLogging {
            print("🧠 Generated embedding for node \(node.id) (\(embedding.count) dimensions)")
        }
        
        return true
    }
    
    // MARK: - Content Building
    
    /// Build text content from a node for embedding generation
    /// Combines title, description, and recent conversation
    private func buildEmbeddingContent(from node: Node) -> String {
        var parts: [String] = []
        
        // Include title if present
        if !node.title.isEmpty {
            parts.append("Title: \(node.title)")
        }
        
        // Include description if present
        if !node.description.isEmpty {
            parts.append("Description: \(node.description)")
        }
        
        // Include conversation (limit to recent for token efficiency)
        let recentMessages = Array(node.conversation.suffix(maxConversationMessages))
        for msg in recentMessages {
            let prefix = msg.role == .user ? "User" : "Assistant"
            parts.append("\(prefix): \(msg.content)")
        }
        
        // Combine and limit total length
        let combined = parts.joined(separator: "\n\n")
        return String(combined.prefix(maxEmbeddingChars))
    }
    
    // MARK: - Similarity Search
    
    /// Find the most relevant connected nodes for a query
    /// - Parameters:
    ///   - query: The search query (typically the user's prompt)
    ///   - connectedNodes: Nodes connected via incoming edges
    ///   - topK: Maximum number of results to return
    ///   - minSimilarity: Minimum similarity threshold (0-1)
    /// - Returns: Array of (node, similarity) tuples sorted by relevance
    func findRelevantNodes(
        query: String,
        connectedNodes: [Node],
        topK: Int = 3,
        minSimilarity: Float = 0.3
    ) async throws -> [(node: Node, similarity: Float)] {
        // Skip if no connected nodes have embeddings
        let nodesWithEmbeddings = connectedNodes.filter { $0.embedding != nil }
        guard !nodesWithEmbeddings.isEmpty else {
            return []
        }
        
        // Generate query embedding
        let queryEmbedding = try await geminiClient.generateEmbedding(text: query)
        
        // Calculate similarities
        var results: [(node: Node, similarity: Float)] = []
        
        for node in nodesWithEmbeddings {
            guard let nodeEmbedding = node.embedding else { continue }
            
            let similarity = VectorMath.cosineSimilarity(queryEmbedding, nodeEmbedding)
            
            if similarity >= minSimilarity {
                results.append((node, similarity))
            }
        }
        
        // Sort by similarity (descending) and take top-k
        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(topK))
    }
    
    /// Build a concise context snippet from a node for inclusion in AI context
    /// - Parameter node: The source node
    /// - Returns: A formatted context string
    func buildContextSnippet(from node: Node) -> String {
        var parts: [String] = []
        
        // Include title if present
        if !node.title.isEmpty && node.title != "Untitled" {
            parts.append("Topic: \(node.title)")
        }
        
        // Include description if present
        if !node.description.isEmpty {
            parts.append("Description: \(node.description)")
        }
        
        // Use summary if available (preferred - already condensed)
        if let summary = node.summary, !summary.isEmpty {
            parts.append("Summary: \(summary)")
        }
        
        // Include recent conversation (always include for context)
        let recentMessages = Array(node.conversation.suffix(6))
        if !recentMessages.isEmpty {
            var conversationParts: [String] = []
            for msg in recentMessages {
                let prefix = msg.role == .user ? "User" : "Assistant"
                // Truncate long messages
                let content = String(msg.content.prefix(800))
                conversationParts.append("\(prefix): \(content)")
            }
            parts.append("Conversation:\n\(conversationParts.joined(separator: "\n"))")
        }
        
        let result = parts.joined(separator: "\n\n")
        
        if Config.enableVerboseLogging {
            print("🔗 Built context snippet for node '\(node.title)': \(result.prefix(200))...")
        }
        
        return result
    }
    
    // MARK: - Multi-Hop Context
    
    /// Collect context from nodes connected via multiple hops
    /// - Parameters:
    ///   - node: The target node to collect context for
    ///   - edges: All edges in the project
    ///   - nodes: All nodes in the project
    ///   - maxHops: Maximum number of hops to traverse (default 2)
    /// - Returns: Array of (node, distance) tuples sorted by distance
    func collectMultiHopContext(
        for node: Node,
        edges: [UUID: Edge],
        nodes: [UUID: Node],
        maxHops: Int = 2
    ) -> [(node: Node, distance: Int)] {
        var visited: Set<UUID> = [node.id]
        var results: [(node: Node, distance: Int)] = []
        var currentLevel: [UUID] = [node.id]
        
        for hop in 1...maxHops {
            var nextLevel: [UUID] = []
            
            for nodeId in currentLevel {
                // Find all incoming edges to this node
                let incomingEdges = edges.values.filter { $0.targetId == nodeId }
                
                for edge in incomingEdges {
                    guard !visited.contains(edge.sourceId),
                          let sourceNode = nodes[edge.sourceId] else { continue }
                    
                    visited.insert(edge.sourceId)
                    nextLevel.append(edge.sourceId)
                    results.append((sourceNode, hop))
                }
            }
            
            currentLevel = nextLevel
        }
        
        return results
    }
}

// MARK: - Errors

enum EmbeddingError: LocalizedError {
    case emptyContent
    case embeddingGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Node has no content to generate embedding from"
        case .embeddingGenerationFailed:
            return "Failed to generate embedding"
        }
    }
}
