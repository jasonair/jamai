//
//  TeamMember.swift
//  JamAI
//
//  Represents a team member (AI persona) attached to a node
//

import Foundation

struct TeamMember: Codable, Equatable, Sendable {
    let roleId: String // Reference to Role.id
    var name: String? // Legacy custom name (no longer used in prompts/UI)
    var experienceLevel: ExperienceLevel
    var promptAddendum: String? // Optional custom instructions to append to system prompt
    var knowledgePackIds: [String]? // Future: IDs of attached knowledge packs
    
    init(
        roleId: String,
        name: String? = nil,
        experienceLevel: ExperienceLevel = .expert,
        promptAddendum: String? = nil,
        knowledgePackIds: [String]? = nil
    ) {
        self.roleId = roleId
        self.name = name
        // Normalize to expert for all new team members
        self.experienceLevel = .expert
        self.promptAddendum = promptAddendum
        self.knowledgePackIds = knowledgePackIds
    }
    
    /// Effective experience level used for prompts and display (currently always Expert)
    private var effectiveExperienceLevel: ExperienceLevel {
        .expert
    }
    
    /// Display name combining experience level and role (legacy helper)
    func displayName(with role: Role?) -> String {
        guard let role = role else {
            return "Team Member"
        }
        return role.name
    }
    
    /// Assemble the full system prompt for this team member
    /// Personality is applied at the node level and appended separately.
    func assembleSystemPrompt(with role: Role?, personality: Personality?, baseSystemPrompt: String) -> String {
        guard let role = role else {
            return baseSystemPrompt
        }
        
        // Prefer Expert prompt; gracefully fall back if missing
        let level = effectiveExperienceLevel
        let rolePrompt = role.systemPrompt(for: level)
            ?? role.systemPrompt(for: .senior)
            ?? role.systemPrompt(for: .intermediate)
            ?? role.systemPrompt(for: .junior)
        
        guard let rolePrompt else {
            return baseSystemPrompt
        }
        
        var assembled = baseSystemPrompt
        
        // Add role-specific prompt
        assembled += "\n\n# Team Member Role\n"
        
        let roleDescription = "\(level.displayName) \(role.name)"
        assembled += "You are acting as a \(roleDescription).\n"
        assembled += "\n\(rolePrompt)"
        
        // Add personality instructions if present
        if let personality {
            assembled += "\n\n# Personality\n\(personality.promptSnippet)"
        }
        
        // Add custom instructions if present
        if let addendum = promptAddendum, !addendum.isEmpty {
            assembled += "\n\n# Additional Instructions\n\(addendum)"
        }
        
        return assembled
    }
}
