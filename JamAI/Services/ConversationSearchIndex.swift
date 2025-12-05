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

/// Match type for search results
enum SearchMatchType: Sendable {
    case title          // Match in node title
    case teamMember     // Match in team member role name
    case conversation   // Match in conversation content
    case note           // Match in note content
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
    let matchType: SearchMatchType
    let teamMemberRoleName: String? // For display in results
    
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
        nodePosition: CGPoint,
        matchType: SearchMatchType = .conversation,
        teamMemberRoleName: String? = nil
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
        self.matchType = matchType
        self.teamMemberRoleName = teamMemberRoleName
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
    
    /// Node metadata cache (includes team member role name for search)
    private var nodeMetadata: [UUID: (title: String, color: String, position: CGPoint, teamMemberRoleName: String?)] = [:]
    
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
        // Get team member role name if present
        var teamMemberRoleName: String? = nil
        if let teamMember = node.teamMember,
           let role = RoleManager.shared.role(withId: teamMember.roleId) {
            teamMemberRoleName = role.name
        }
        
        // Store node metadata
        nodeMetadata[node.id] = (
            title: node.title.isEmpty ? "Untitled" : node.title,
            color: node.color,
            position: CGPoint(x: node.x, y: node.y),
            teamMemberRoleName: teamMemberRoleName
        )
        
        // Remove existing entries for this node first
        removeNode(nodeId: node.id)
        
        // Index node title (use special messageIndex -1)
        indexText(node.title, nodeId: node.id, messageId: node.id, messageIndex: -1)
        
        // Index team member role name (use special messageIndex -3)
        if let roleName = teamMemberRoleName {
            let teamMemberMessageId = UUID(uuidString: "00000000-0000-0000-0000-\(node.id.uuidString.suffix(12))") ?? UUID()
            indexText(roleName, nodeId: node.id, messageId: teamMemberMessageId, messageIndex: -3)
            messageTexts[teamMemberMessageId] = "Team Member: \(roleName)"
            if nodeMessages[node.id] == nil {
                nodeMessages[node.id] = []
            }
            nodeMessages[node.id]?.insert(teamMemberMessageId)
        }
        
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
        // Get team member role name if present
        var teamMemberRoleName: String? = nil
        if let teamMember = node.teamMember,
           let role = RoleManager.shared.role(withId: teamMember.roleId) {
            teamMemberRoleName = role.name
        }
        
        nodeMetadata[node.id] = (
            title: node.title.isEmpty ? "Untitled" : node.title,
            color: node.color,
            position: CGPoint(x: node.x, y: node.y),
            teamMemberRoleName: teamMemberRoleName
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
                
                // Determine match type based on content
                let matchType = determineMatchType(
                    fullText: fullText,
                    messageId: messageId,
                    nodeId: nodeId,
                    nodeTitle: metadata.title
                )
                
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
                    nodePosition: metadata.position,
                    matchType: matchType,
                    teamMemberRoleName: metadata.teamMemberRoleName
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
            
            // Determine match type based on content
            let matchType = determineMatchType(
                fullText: text,
                messageId: messageId,
                nodeId: nodeId,
                nodeTitle: metadata.title
            )
            
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
                nodePosition: metadata.position,
                matchType: matchType,
                teamMemberRoleName: metadata.teamMemberRoleName
            )
            results.append(result)
            
            if results.count >= maxResults {
                break
            }
        }
        
        return sortResults(results, query: query, viewportCenter: viewportCenter)
    }
    
    // MARK: - Match Type Detection
    
    /// Determine the type of match based on content and context
    private func determineMatchType(
        fullText: String,
        messageId: UUID,
        nodeId: UUID,
        nodeTitle: String
    ) -> SearchMatchType {
        // Check if this is a title match (messageId equals nodeId for title entries)
        if messageId == nodeId {
            return .title
        }
        
        // Check if this is a team member match (text starts with "Team Member:")
        if fullText.hasPrefix("Team Member:") {
            return .teamMember
        }
        
        // Check if this is a note match (would need to track note content separately)
        // For now, default to conversation
        return .conversation
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
        
        // Strip markdown formatting
        snippet = stripMarkdown(snippet)
        
        // Add ellipsis
        if lower > text.startIndex {
            snippet = "…" + snippet
        }
        if upper < text.endIndex {
            snippet = snippet + "…"
        }
        
        return snippet.trimmingCharacters(in: .whitespaces)
    }
    
    /// Strip common markdown formatting from text for clean display
    private func stripMarkdown(_ text: String) -> String {
        var result = text
        
        // Remove bold/italic markers: **text**, *text*, __text__, _text_
        // Handle bold first (** and __), then italic (* and _)
        result = result.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "_([^_]+)_", with: "$1", options: .regularExpression)
        
        // Remove inline code: `code`
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        
        // Remove headers: # ## ### etc at start of lines
        result = result.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        
        // Remove bullet points: - * at start
        result = result.replacingOccurrences(of: "^[\\-\\*]\\s+", with: "", options: .regularExpression)
        
        // Remove numbered lists: 1. 2. etc
        result = result.replacingOccurrences(of: "^\\d+\\.\\s+", with: "", options: .regularExpression)
        
        // Remove links: [text](url) -> text
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        
        // Remove standalone asterisks that might remain
        result = result.replacingOccurrences(of: "\\s\\*\\s", with: " ", options: .regularExpression)
        
        // Clean up any double spaces created
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        
        return result
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
