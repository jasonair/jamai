//
//  ConversationMessage.swift
//  JamAI
//
//  Represents a single message in a conversation thread
//

import Foundation

struct ConversationMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    let imageData: Data?
    let imageMimeType: String?
    
    nonisolated init(
        id: UUID = UUID(), 
        role: MessageRole, 
        content: String, 
        timestamp: Date = Date(),
        imageData: Data? = nil,
        imageMimeType: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.imageData = imageData
        self.imageMimeType = imageMimeType
    }
    
    var hasImage: Bool {
        imageData != nil
    }
}

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}
