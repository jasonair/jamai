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

enum NodeType: String, Codable, Sendable {
    case standard
    case note
}

struct Node: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var projectId: UUID
    var parentId: UUID?
    
    // Position
    var x: CGFloat
    var y: CGFloat
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
    
    // UI State
    var isExpanded: Bool
    var isFrozenContext: Bool
    var color: String // Node color for organization (e.g., "blue", "red", "none")
    var type: NodeType
    
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
        isExpanded: Bool = true,
        isFrozenContext: Bool = false,
        color: String = "none",
        type: NodeType = .standard,
        displayOrder: Int? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.parentId = parentId
        self.x = x
        self.y = y
        self.height = height
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
        self.isExpanded = isExpanded
        self.isFrozenContext = isFrozenContext
        self.color = color
        self.type = type
        self.displayOrder = displayOrder
        self.createdAt = Date()
        self.updatedAt = Date()
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
    
    mutating func addMessage(role: MessageRole, content: String) {
        var messages = conversation
        messages.append(ConversationMessage(role: role, content: content))
        setConversation(messages)
    }
    
    static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Node Display Constants
extension Node {
    nonisolated static let nodeWidth: CGFloat = 400 // Same width for both collapsed and expanded
    nonisolated static let noteWidth: CGFloat = nodeWidth / 2
    nonisolated static let collapsedHeight: CGFloat = 120 // Tall enough for title and description
    nonisolated static let expandedHeight: CGFloat = 400 // Default expanded height
    nonisolated static let minHeight: CGFloat = 300 // Minimum height when resizing
    nonisolated static let maxHeight: CGFloat = 800 // Maximum height when resizing
    nonisolated static let padding: CGFloat = 16
    nonisolated static let cornerRadius: CGFloat = 12
    nonisolated static let shadowRadius: CGFloat = 8
    
    nonisolated static func width(for type: NodeType) -> CGFloat {
        switch type {
        case .note: return noteWidth
        case .standard: return nodeWidth
        }
    }
    
    // Legacy constants for backwards compatibility
    nonisolated static let collapsedWidth: CGFloat = nodeWidth
    nonisolated static let expandedWidth: CGFloat = nodeWidth
}
