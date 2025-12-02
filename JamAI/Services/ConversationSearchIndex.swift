//
//  ConversationSearchIndex.swift
//  JamAI
//
//  In-memory search index for fast conversation search
//

import Foundation

/// Reference to a specific location in the conversation data
struct IndexedMessageRef: Sendable {
    let nodeId: UUID
    let messageId: UUID
    let messageIndex: Int
    let position: Int // Character offset in the message content
}

/// A single search result with context
struct ConversationSearchResult: Identifiable, Sendable {
    let id: UUID
    let nodeId: UUID
    let nodeTitle: String
    let nodeColor: String
    let messageId: UUID
    let messageRole: MessageRole
    let snippet: String
    let matchRange: Range<String.Index>?
    let fullContent: String
    let timestamp: Date
    let nodePosition: CGPoint // For viewport-based ranking
    
    init(
        nodeId: UUID,
        nodeTitle: String,
        nodeColor: String,
        messageId: UUID,
        messageRole: MessageRole,
        snippet: String,
        matchRange: Range<String.Index>?,
        fullContent: String,
        timestamp: Date,
        nodePosition: CGPoint
    ) {
        self.id = UUID()
        self.nodeId = nodeId
        self.nodeTitle = nodeTitle
        self.nodeColor = nodeColor
        self.messageId = messageId
        self.messageRole = messageRole
        self.snippet = snippet
        self.matchRange = matchRange
        self.fullContent = fullContent
        self.timestamp = timestamp
        self.nodePosition = nodePosition
    }
}

/// Highlight information to pass to NodeView
struct NodeSearchHighlight: Equatable, Sendable {
    let nodeId: UUID
    let messageId: UUID
    let query: String
    let timestamp: Date // Used to detect changes even with same query
    
    init(nodeId: UUID, messageId: UUID, query: String) {
        self.nodeId = nodeId
        self.messageId = messageId
        self.query = query
        self.timestamp = Date()
    }
}

/// In-memory search index for conversation content
/// Uses a simple inverted index for fast token-based search
@MainActor
final class ConversationSearchIndex {
    
    // MARK: - Index Storage
    
    /// Token -> list of message references
    private var postings: [String: [IndexedMessageRef]] = [:]
    
    /// MessageId -> full text content (for snippet generation)
    private var messageTexts: [UUID: String] = [:]
    
    /// NodeId -> set of message IDs (for efficient node removal)
    private var nodeMessages: [UUID: Set<UUID>] = [:]
    
    /// Node metadata cache
    private var nodeMetadata: [UUID: (title: String, color: String, position: CGPoint)] = [:]
    
    // MARK: - Configuration
    
    private let maxSnippetContext = 60 // Characters before/after match
    private let maxResults = 100 // Cap results for performance
    
    // MARK: - Index Building
    
    /// Rebuild the entire index from a collection of nodes
    func rebuild(from nodes: [Node]) {
        // Clear existing index
        postings.removeAll()
        messageTexts.removeAll()
        nodeMessages.removeAll()
        nodeMetadata.removeAll()
        
        // Index each node
        for node in nodes {
            indexNode(node)
        }
    }
    
    /// Index a single node (for incremental updates)
    func indexNode(_ node: Node) {
        // Store node metadata
        nodeMetadata[node.id] = (
            title: node.title.isEmpty ? "Untitled" : node.title,
            color: node.color,
            position: CGPoint(x: node.x, y: node.y)
        )
        
        // Remove existing entries for this node first
        removeNode(nodeId: node.id)
        
        // Index node title
        indexText(node.title, nodeId: node.id, messageId: node.id, messageIndex: -1)
        
        // Index conversation messages
        let messages = node.conversation
        for (index, message) in messages.enumerated() {
            indexMessage(message, nodeId: node.id, messageIndex: index)
        }
        
        // Index note content (description field for notes)
        if node.type == .note && !node.description.isEmpty {
            indexText(node.description, nodeId: node.id, messageId: node.id, messageIndex: -2)
        }
    }
    
    /// Remove a node from the index
    func removeNode(nodeId: UUID) {
        guard let messageIds = nodeMessages[nodeId] else { return }
        
        // Remove message texts
        for messageId in messageIds {
            messageTexts.removeValue(forKey: messageId)
        }
        
        // Remove from postings (expensive but necessary)
        for (token, refs) in postings {
            postings[token] = refs.filter { $0.nodeId != nodeId }
        }
        
        // Clean up empty posting lists
        postings = postings.filter { !$0.value.isEmpty }
        
        // Remove node tracking
        nodeMessages.removeValue(forKey: nodeId)
        nodeMetadata.removeValue(forKey: nodeId)
    }
    
    /// Update node metadata (position, title, color) without reindexing content
    func updateNodeMetadata(_ node: Node) {
        nodeMetadata[node.id] = (
            title: node.title.isEmpty ? "Untitled" : node.title,
            color: node.color,
            position: CGPoint(x: node.x, y: node.y)
        )
    }
    
    // MARK: - Private Indexing Helpers
    
    private func indexMessage(_ message: ConversationMessage, nodeId: UUID, messageIndex: Int) {
        // Store full text
        messageTexts[message.id] = message.content
        
        // Track message for this node
        if nodeMessages[nodeId] == nil {
            nodeMessages[nodeId] = []
        }
        nodeMessages[nodeId]?.insert(message.id)
        
        // Index the content
        indexText(message.content, nodeId: nodeId, messageId: message.id, messageIndex: messageIndex)
    }
    
    private func indexText(_ text: String, nodeId: UUID, messageId: UUID, messageIndex: Int) {
        let tokens = tokenize(text)
        
        for (position, token) in tokens.enumerated() {
            let ref = IndexedMessageRef(
                nodeId: nodeId,
                messageId: messageId,
                messageIndex: messageIndex,
                position: position
            )
            
            if postings[token] == nil {
                postings[token] = []
            }
            postings[token]?.append(ref)
        }
    }
    
    /// Tokenize text into searchable tokens
    private func tokenize(_ text: String) -> [String] {
        // Normalize: lowercase, split on whitespace and punctuation
        let normalized = text.lowercased()
        
        // Split on non-alphanumeric characters
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count >= 2 } // Filter out single chars and empty
        
        return tokens
    }
    
    // MARK: - Search
    
    /// Search for a query string across all indexed content
    /// Returns results sorted by relevance (title matches first, then by recency)
    func search(query: String, viewportCenter: CGPoint? = nil) -> [ConversationSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return [] }
        
        let queryTokens = tokenize(trimmedQuery)
        guard !queryTokens.isEmpty else {
            // Fall back to substring search if no valid tokens
            return substringSearch(query: trimmedQuery, viewportCenter: viewportCenter)
        }
        
        // Find messages that contain all query tokens
        var candidateMessages: Set<UUID>?
        
        for token in queryTokens {
            // Find all tokens that start with this token (prefix matching)
            let matchingRefs = postings
                .filter { $0.key.hasPrefix(token) }
                .flatMap { $0.value }
            
            let messageIds = Set(matchingRefs.map { $0.messageId })
            
            if candidateMessages == nil {
                candidateMessages = messageIds
            } else {
                candidateMessages = candidateMessages?.intersection(messageIds)
            }
            
            // Early exit if no matches
            if candidateMessages?.isEmpty == true {
                break
            }
        }
        
        guard let matchedMessageIds = candidateMessages, !matchedMessageIds.isEmpty else {
            // Fall back to substring search
            return substringSearch(query: trimmedQuery, viewportCenter: viewportCenter)
        }
        
        // Build results with snippets
        var results: [ConversationSearchResult] = []
        
        for messageId in matchedMessageIds {
            guard let fullText = messageTexts[messageId] else { continue }
            
            // Find the node this message belongs to
            guard let (nodeId, _) = nodeMessages.first(where: { $0.value.contains(messageId) }) else { continue }
            guard let metadata = nodeMetadata[nodeId] else { continue }
            
            // Find the actual match in the text for snippet generation
            if let range = fullText.range(of: trimmedQuery, options: .caseInsensitive) {
                let snippet = generateSnippet(text: fullText, matchRange: range)
                
                // Determine message role (default to user if not found in conversation)
                let messageRole: MessageRole = .user
                
                let result = ConversationSearchResult(
                    nodeId: nodeId,
                    nodeTitle: metadata.title,
                    nodeColor: metadata.color,
                    messageId: messageId,
                    messageRole: messageRole,
                    snippet: snippet,
                    matchRange: range,
                    fullContent: fullText,
                    timestamp: Date(),
                    nodePosition: metadata.position
                )
                results.append(result)
            }
        }
        
        // Sort results
        return sortResults(results, query: trimmedQuery, viewportCenter: viewportCenter)
    }
    
    /// Fallback substring search for queries that don't tokenize well
    private func substringSearch(query: String, viewportCenter: CGPoint?) -> [ConversationSearchResult] {
        var results: [ConversationSearchResult] = []
        let lowercaseQuery = query.lowercased()
        
        for (messageId, text) in messageTexts {
            guard let range = text.lowercased().range(of: lowercaseQuery) else { continue }
            
            // Map range back to original text
            let originalRange = Range(uncheckedBounds: (
                lower: text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: text.index(text.startIndex, offsetBy: text.lowercased().distance(from: text.lowercased().startIndex, to: range.lowerBound)))),
                upper: text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: text.index(text.startIndex, offsetBy: text.lowercased().distance(from: text.lowercased().startIndex, to: range.upperBound))))
            ))
            
            guard let (nodeId, _) = nodeMessages.first(where: { $0.value.contains(messageId) }) else { continue }
            guard let metadata = nodeMetadata[nodeId] else { continue }
            
            let snippet = generateSnippet(text: text, matchRange: originalRange)
            
            let result = ConversationSearchResult(
                nodeId: nodeId,
                nodeTitle: metadata.title,
                nodeColor: metadata.color,
                messageId: messageId,
                messageRole: .user,
                snippet: snippet,
                matchRange: originalRange,
                fullContent: text,
                timestamp: Date(),
                nodePosition: metadata.position
            )
            results.append(result)
            
            if results.count >= maxResults {
                break
            }
        }
        
        return sortResults(results, query: query, viewportCenter: viewportCenter)
    }
    
    // MARK: - Snippet Generation
    
    private func generateSnippet(text: String, matchRange: Range<String.Index>) -> String {
        let context = maxSnippetContext
        
        // Calculate bounds with context
        let lower = text.index(
            matchRange.lowerBound,
            offsetBy: -context,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        
        let upper = text.index(
            matchRange.upperBound,
            offsetBy: context,
            limitedBy: text.endIndex
        ) ?? text.endIndex
        
        var snippet = String(text[lower..<upper])
        
        // Clean up the snippet
        snippet = snippet.replacingOccurrences(of: "\n", with: " ")
        snippet = snippet.replacingOccurrences(of: "  ", with: " ")
        
        // Add ellipsis
        if lower > text.startIndex {
            snippet = "…" + snippet
        }
        if upper < text.endIndex {
            snippet = snippet + "…"
        }
        
        return snippet.trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Result Sorting
    
    private func sortResults(
        _ results: [ConversationSearchResult],
        query: String,
        viewportCenter: CGPoint?
    ) -> [ConversationSearchResult] {
        let lowercaseQuery = query.lowercased()
        
        return results.sorted { a, b in
            // Priority 1: Title matches rank higher
            let aInTitle = a.nodeTitle.lowercased().contains(lowercaseQuery)
            let bInTitle = b.nodeTitle.lowercased().contains(lowercaseQuery)
            if aInTitle != bInTitle {
                return aInTitle
            }
            
            // Priority 2: Exact matches rank higher
            let aExact = a.fullContent.lowercased().contains(lowercaseQuery)
            let bExact = b.fullContent.lowercased().contains(lowercaseQuery)
            if aExact != bExact {
                return aExact
            }
            
            // Priority 3: Distance to viewport center (if provided)
            if let center = viewportCenter {
                let aDist = hypot(a.nodePosition.x - center.x, a.nodePosition.y - center.y)
                let bDist = hypot(b.nodePosition.x - center.x, b.nodePosition.y - center.y)
                if abs(aDist - bDist) > 100 { // Only consider if significantly different
                    return aDist < bDist
                }
            }
            
            // Priority 4: More recent first
            return a.timestamp > b.timestamp
        }
        .prefix(maxResults)
        .map { $0 }
    }
    
    // MARK: - Statistics
    
    var indexedNodeCount: Int {
        nodeMessages.count
    }
    
    var indexedMessageCount: Int {
        messageTexts.count
    }
    
    var uniqueTokenCount: Int {
        postings.count
    }
}
