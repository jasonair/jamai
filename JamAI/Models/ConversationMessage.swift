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
    let webSearchEnabled: Bool
    let searchResults: [SearchResult]?
    
    // Team member info for assistant messages - stores the persona used for this response
    let teamMemberRoleId: String?
    let teamMemberRoleName: String?
    let teamMemberExperienceLevel: String?
    
    nonisolated init(
        id: UUID = UUID(), 
        role: MessageRole, 
        content: String, 
        timestamp: Date = Date(),
        imageData: Data? = nil,
        imageMimeType: String? = nil,
        webSearchEnabled: Bool = false,
        searchResults: [SearchResult]? = nil,
        teamMemberRoleId: String? = nil,
        teamMemberRoleName: String? = nil,
        teamMemberExperienceLevel: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.imageData = imageData
        self.imageMimeType = imageMimeType
        self.webSearchEnabled = webSearchEnabled
        self.searchResults = searchResults
        self.teamMemberRoleId = teamMemberRoleId
        self.teamMemberRoleName = teamMemberRoleName
        self.teamMemberExperienceLevel = teamMemberExperienceLevel
    }
    
    var hasImage: Bool {
        imageData != nil
    }
    
    var hasSearchResults: Bool {
        searchResults != nil && !(searchResults?.isEmpty ?? true)
    }
}

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}
