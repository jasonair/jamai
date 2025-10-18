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
    case shape
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
        isExpanded: Bool = true,
        isFrozenContext: Bool = false,
        color: String = "none",
        type: NodeType = .standard,
        fontSize: CGFloat = 16,
        isBold: Bool = false,
        fontFamily: String? = nil,
        shapeKind: ShapeKind? = nil,
        displayOrder: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.parentId = parentId
        self.x = x
        self.y = y
        self.width = width ?? Node.width(for: type)
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
        self.teamMemberJSON = teamMemberJSON
        self.isExpanded = isExpanded
        self.isFrozenContext = isFrozenContext
        self.color = color
        self.type = type
        self.fontSize = fontSize
        self.isBold = isBold
        self.fontFamily = fontFamily
        self.shapeKind = shapeKind
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
    
    mutating func addMessage(role: MessageRole, content: String, imageData: Data? = nil, imageMimeType: String? = nil) {
        var messages = conversation
        messages.append(ConversationMessage(
            role: role, 
            content: content,
            imageData: imageData,
            imageMimeType: imageMimeType
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
    
    static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Node Display Constants
extension Node {
    nonisolated static let nodeWidth: CGFloat = 400 // Same width for both collapsed and expanded
    nonisolated static let noteWidth: CGFloat = 350 // Note default width
    nonisolated static let textWidth: CGFloat = 200
    nonisolated static let shapeWidth: CGFloat = 160
    nonisolated static let collapsedHeight: CGFloat = 200 // Tall enough for title and full description
    nonisolated static let expandedHeight: CGFloat = 400 // Default expanded height
    nonisolated static let minHeight: CGFloat = 300 // Minimum height when resizing
    nonisolated static let maxHeight: CGFloat = 800 // Maximum height when resizing
    nonisolated static let minWidth: CGFloat = 420 // Minimum width for standard nodes when resizing
    nonisolated static let minNoteWidth: CGFloat = 350 // Minimum width for notes when resizing
    nonisolated static let maxWidth: CGFloat = 1200 // Maximum width for standard nodes when resizing
    nonisolated static let maxNoteWidth: CGFloat = 700 // Maximum width for notes when resizing
    nonisolated static let padding: CGFloat = 16
    nonisolated static let cornerRadius: CGFloat = 12
    nonisolated static let shadowRadius: CGFloat = 8
    
    nonisolated static func width(for type: NodeType) -> CGFloat {
        switch type {
        case .note: return noteWidth
        case .text: return textWidth
        case .shape: return shapeWidth
        case .standard: return nodeWidth
        }
    }
    
    // Legacy constants for backwards compatibility
    nonisolated static let collapsedWidth: CGFloat = nodeWidth
    nonisolated static let expandedWidth: CGFloat = nodeWidth
}
