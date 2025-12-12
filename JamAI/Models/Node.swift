//
//  Node.swift
//  JamAI
//
//  Core node model representing a thought/conversation node in the canvas
//

import Foundation
import SwiftUI

enum TextSource: String, Codable, Sendable {
    case user
    case ai
}

// MARK: - Shapes
enum ShapeKind: String, Codable, Sendable {
    case rectangle
    case ellipse
}

enum NodeType: String, Codable, Sendable {
    case standard
    case note
    case text
    case title
    case shape
    case image
    case pdf
    case youtube
}

struct Node: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var projectId: UUID
    var parentId: UUID?
    
    // Position
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat // Custom width
    var height: CGFloat // Custom height when expanded
    
    // Content
    var title: String
    var titleSource: TextSource
    var description: String
    var descriptionSource: TextSource
    var conversationJSON: String // JSON array of conversation messages
    
    // Legacy fields for backwards compatibility
    var prompt: String
    var response: String
    
    // Context & history
    var ancestryJSON: String // JSON array of ancestor node IDs
    var summary: String?
    var systemPromptSnapshot: String?
    
    // Team Member
    var teamMemberJSON: String? // JSON representation of attached TeamMember
    var personalityRawValue: String? // Raw Personality value stored in database
    
    // UI State
    var isExpanded: Bool
    var isFrozenContext: Bool
    var color: String // Node color for organization (e.g., "blue", "red", "none")
    var type: NodeType
    // Annotation formatting
    var fontSize: CGFloat
    var isBold: Bool
    var fontFamily: String?
    var shapeKind: ShapeKind?
    
    // Image data (for image nodes)
    var imageData: Data?
    
    // PDF data (for pdf nodes)
    var pdfFileUri: String?      // Gemini File API URI (files/xxx)
    var pdfFileName: String?     // Original filename for display
    var pdfFileId: String?       // Gemini file ID for deletion
    var pdfData: Data?           // Local PDF data for persistence
    
    // YouTube data (for youtube nodes)
    var youtubeUrl: String?           // Full YouTube URL
    var youtubeVideoId: String?       // Extracted video ID (e.g., "dQw4w9WgXcQ")
    var youtubeTitle: String?         // Video title from oEmbed
    var youtubeThumbnailUrl: String?  // Thumbnail URL for display
    var youtubeTranscript: String?    // Cached transcript text
    var youtubeFileUri: String?       // Gemini File API URI (for RAG)
    var youtubeFileId: String?        // Gemini file ID for deletion/status
    
    // Embeddings for RAG
    var embeddingJSON: String? // JSON array of Float values for semantic search
    var embeddingUpdatedAt: Date? // When the embedding was last generated
    
    // Orchestrator (Jam Squad)
    var orchestratorSessionId: UUID? // ID of the orchestration session this node belongs to
    var orchestratorRoleRaw: String? // Raw OrchestratorRole value (master/delegate)
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    var displayOrder: Int? // Order for display in outline view (nil = use createdAt)
    
    nonisolated init(
        id: UUID = UUID(),
        projectId: UUID,
        parentId: UUID? = nil,
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat? = nil,
        height: CGFloat = Node.expandedHeight,
        title: String = "",
        titleSource: TextSource = .user,
        description: String = "",
        descriptionSource: TextSource = .user,
        conversationJSON: String = "[]",
        prompt: String = "",
        response: String = "",
        ancestryJSON: String = "[]",
        summary: String? = nil,
        systemPromptSnapshot: String? = nil,
        teamMemberJSON: String? = nil,
        personalityRawValue: String? = nil,
        isExpanded: Bool = true,
        isFrozenContext: Bool = false,
        color: String = "none",
        type: NodeType = .standard,
        fontSize: CGFloat = 16,
        isBold: Bool = false,
        fontFamily: String? = nil,
        shapeKind: ShapeKind? = nil,
        imageData: Data? = nil,
        pdfFileUri: String? = nil,
        pdfFileName: String? = nil,
        pdfFileId: String? = nil,
        pdfData: Data? = nil,
        youtubeUrl: String? = nil,
        youtubeVideoId: String? = nil,
        youtubeTitle: String? = nil,
        youtubeThumbnailUrl: String? = nil,
        youtubeTranscript: String? = nil,
        youtubeFileUri: String? = nil,
        youtubeFileId: String? = nil,
        embeddingJSON: String? = nil,
        embeddingUpdatedAt: Date? = nil,
        orchestratorSessionId: UUID? = nil,
        orchestratorRoleRaw: String? = nil,
        displayOrder: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.parentId = parentId
        self.x = x
        self.y = y
        let resolvedWidth = width ?? Node.width(for: type)
        let resolvedHeight: CGFloat
        if type == .note && height == Node.expandedHeight {
            // Default notes should be square by default
            resolvedHeight = Node.noteWidth
        } else {
            resolvedHeight = height
        }
        self.width = resolvedWidth
        self.height = resolvedHeight
        self.title = title
        self.titleSource = titleSource
        self.description = description
        self.descriptionSource = descriptionSource
        self.conversationJSON = conversationJSON
        self.prompt = prompt
        self.response = response
        self.ancestryJSON = ancestryJSON
        self.summary = summary
        self.systemPromptSnapshot = systemPromptSnapshot
        self.teamMemberJSON = teamMemberJSON
        self.personalityRawValue = personalityRawValue
        self.isExpanded = isExpanded
        self.isFrozenContext = isFrozenContext
        self.color = color
        self.type = type
        self.fontSize = fontSize
        self.isBold = isBold
        self.fontFamily = fontFamily
        self.shapeKind = shapeKind
        self.imageData = imageData
        self.pdfFileUri = pdfFileUri
        self.pdfFileName = pdfFileName
        self.pdfFileId = pdfFileId
        self.pdfData = pdfData
        self.youtubeUrl = youtubeUrl
        self.youtubeVideoId = youtubeVideoId
        self.youtubeTitle = youtubeTitle
        self.youtubeThumbnailUrl = youtubeThumbnailUrl
        self.youtubeTranscript = youtubeTranscript
        self.youtubeFileUri = youtubeFileUri
        self.youtubeFileId = youtubeFileId
        self.embeddingJSON = embeddingJSON
        self.embeddingUpdatedAt = embeddingUpdatedAt
        self.orchestratorSessionId = orchestratorSessionId
        self.orchestratorRoleRaw = orchestratorRoleRaw
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Computed properties
    var ancestry: [UUID] {
        guard let data = ancestryJSON.data(using: .utf8),
              let array = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return array
    }
    
    mutating func setAncestry(_ uuids: [UUID]) {
        if let data = try? JSONEncoder().encode(uuids),
           let json = String(data: data, encoding: .utf8) {
            self.ancestryJSON = json
        }
    }
    
    var conversation: [ConversationMessage] {
        guard let data = conversationJSON.data(using: .utf8),
              let array = try? JSONDecoder().decode([ConversationMessage].self, from: data) else {
            return []
        }
        return array
    }
    
    mutating func setConversation(_ messages: [ConversationMessage]) {
        if let data = try? JSONEncoder().encode(messages),
           let json = String(data: data, encoding: .utf8) {
            self.conversationJSON = json
        }
    }
    
    mutating func addMessage(
        role: MessageRole, 
        content: String, 
        imageData: Data? = nil, 
        imageMimeType: String? = nil,
        webSearchEnabled: Bool = false,
        searchResults: [SearchResult]? = nil,
        teamMemberRoleId: String? = nil,
        teamMemberRoleName: String? = nil,
        teamMemberExperienceLevel: String? = nil
    ) {
        var messages = conversation
        messages.append(ConversationMessage(
            role: role, 
            content: content,
            imageData: imageData,
            imageMimeType: imageMimeType,
            webSearchEnabled: webSearchEnabled,
            searchResults: searchResults,
            teamMemberRoleId: teamMemberRoleId,
            teamMemberRoleName: teamMemberRoleName,
            teamMemberExperienceLevel: teamMemberExperienceLevel
        ))
        setConversation(messages)
    }
    
    var teamMember: TeamMember? {
        guard let json = teamMemberJSON,
              let data = json.data(using: .utf8),
              let member = try? JSONDecoder().decode(TeamMember.self, from: data) else {
            return nil
        }
        return member
    }
    
    mutating func setTeamMember(_ member: TeamMember?) {
        if let member = member,
           let data = try? JSONEncoder().encode(member),
           let json = String(data: data, encoding: .utf8) {
            self.teamMemberJSON = json
        } else {
            self.teamMemberJSON = nil
        }
    }
    
    /// Per-node personality with a default of .balanced when unset or unknown
    var personality: Personality {
        get {
            if let raw = personalityRawValue, let value = Personality(rawValue: raw) {
                return value
            }
            return .balanced
        }
        set {
            personalityRawValue = newValue.rawValue
        }
    }
    
    // MARK: - Embedding Properties
    
    /// Decoded embedding vector for semantic search
    var embedding: [Float]? {
        guard let json = embeddingJSON,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([Float].self, from: data) else {
            return nil
        }
        return array
    }
    
    /// Set the embedding vector and update timestamp
    mutating func setEmbedding(_ embedding: [Float]) {
        if let data = try? JSONEncoder().encode(embedding),
           let json = String(data: data, encoding: .utf8) {
            self.embeddingJSON = json
            self.embeddingUpdatedAt = Date()
        }
    }
    
    /// Check if embedding needs to be updated (content changed since last embedding)
    var needsEmbeddingUpdate: Bool {
        guard let embeddingDate = embeddingUpdatedAt else { return true }
        return updatedAt > embeddingDate
    }
    
    // MARK: - Orchestrator Properties
    
    /// The role of this node in an orchestration session
    var orchestratorRole: OrchestratorRole? {
        get {
            guard let raw = orchestratorRoleRaw else { return nil }
            return OrchestratorRole(rawValue: raw)
        }
        set {
            orchestratorRoleRaw = newValue?.rawValue
        }
    }
    
    /// Whether this node is part of an orchestration session
    var isInOrchestration: Bool {
        orchestratorSessionId != nil
    }
    
    /// Whether this node is the master/orchestrator of a session
    var isOrchestrator: Bool {
        orchestratorRole == .master
    }
    
    /// Whether this node is a delegate/specialist in a session
    var isDelegate: Bool {
        orchestratorRole == .delegate
    }
    
    static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Node Display Constants
extension Node {
    nonisolated static let nodeWidth: CGFloat = 490.26 // Same width for both collapsed and expanded
    nonisolated static let noteWidth: CGFloat = 350 // Note default width
    nonisolated static let titleWidth: CGFloat = 700
    nonisolated static let textWidth: CGFloat = 200
    nonisolated static let shapeWidth: CGFloat = 160
    nonisolated static let pdfWidth: CGFloat = 400 // PDF nodes same width as YouTube
    nonisolated static let pdfHeight: CGFloat = 80  // Compact height for PDF nodes
    // YouTube nodes: width chosen so that the 16:9 thumbnail exactly fits without side cropping.
    // Height = 16:9 thumbnail height (225) + 60pt info bar = 285.
    nonisolated static let youtubeWidth: CGFloat = 400
    nonisolated static let youtubeHeight: CGFloat = 285
    nonisolated static let collapsedHeight: CGFloat = 654 // Same as expanded height - nodes stay at 490.26x654
    nonisolated static let expandedHeight: CGFloat = 654 // Default expanded height
    nonisolated static let minHeight: CGFloat = 654 // Minimum height when resizing
    nonisolated static let maxHeight: CGFloat = 800 // Maximum height when resizing
    nonisolated static let minWidth: CGFloat = 490.26 // Minimum width for standard nodes when resizing
    nonisolated static let minNoteWidth: CGFloat = 350 // Minimum width for notes when resizing
    nonisolated static let minNoteHeight: CGFloat = 200 // Minimum height for notes when resizing
    nonisolated static let maxWidth: CGFloat = 1200 // Maximum width for standard nodes when resizing
    nonisolated static let maxNoteWidth: CGFloat = 700 // Maximum width for notes when resizing
    nonisolated static let maxNoteHeight: CGFloat = 800 // Maximum height for notes when resizing
    nonisolated static let padding: CGFloat = 16
    nonisolated static let cornerRadius: CGFloat = 12
    nonisolated static let shadowRadius: CGFloat = 8
    
    nonisolated static func width(for type: NodeType) -> CGFloat {
        switch type {
        case .note: return noteWidth
        case .title: return titleWidth
        case .text: return textWidth
        case .shape: return shapeWidth
        case .image: return 300 // Default image width
        case .pdf: return pdfWidth
        case .youtube: return youtubeWidth
        case .standard: return nodeWidth
        }
    }
    
    // Legacy constants for backwards compatibility
    nonisolated static let collapsedWidth: CGFloat = nodeWidth
    nonisolated static let expandedWidth: CGFloat = nodeWidth
}
