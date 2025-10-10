//
//  Node.swift
//  JamAI
//
//  Core node model representing a thought/conversation node in the canvas
//

import Foundation
import SwiftUI

enum TextSource: String, Codable {
    case user
    case ai
}

struct Node: Identifiable, Codable, Equatable {
    let id: UUID
    var projectId: UUID
    var parentId: UUID?
    
    // Position
    var x: CGFloat
    var y: CGFloat
    
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
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        projectId: UUID,
        parentId: UUID? = nil,
        x: CGFloat = 0,
        y: CGFloat = 0,
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
        isExpanded: Bool = false,
        isFrozenContext: Bool = false
    ) {
        self.id = id
        self.projectId = projectId
        self.parentId = parentId
        self.x = x
        self.y = y
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
    static let nodeWidth: CGFloat = 400 // Same width for both collapsed and expanded
    static let collapsedHeight: CGFloat = 160
    static let expandedHeight: CGFloat = 600
    static let padding: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 8
    
    // Legacy constants for backwards compatibility
    static let collapsedWidth: CGFloat = nodeWidth
    static let expandedWidth: CGFloat = nodeWidth
}
