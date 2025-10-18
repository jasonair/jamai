//
//  TeamMember.swift
//  JamAI
//
//  Represents a team member (AI persona) attached to a node
//

import Foundation

struct TeamMember: Codable, Equatable, Sendable {
    let roleId: String // Reference to Role.id
    var name: String? // Custom name (e.g., "Sarah")
    var experienceLevel: ExperienceLevel
    var promptAddendum: String? // Optional custom instructions to append to system prompt
    var knowledgePackIds: [String]? // Future: IDs of attached knowledge packs
    
    init(
        roleId: String,
        name: String? = nil,
        experienceLevel: ExperienceLevel = .intermediate,
        promptAddendum: String? = nil,
        knowledgePackIds: [String]? = nil
    ) {
        self.roleId = roleId
        self.name = name
        self.experienceLevel = experienceLevel
        self.promptAddendum = promptAddendum
        self.knowledgePackIds = knowledgePackIds
    }
    
    /// Display name combining custom name and role
    func displayName(with role: Role?) -> String {
        guard let role = role else {
            return name ?? "Team Member"
        }
        
        if let customName = name, !customName.isEmpty {
            return "\(customName) (\(experienceLevel.displayName) \(role.name))"
        } else {
            return "\(experienceLevel.displayName) \(role.name)"
        }
    }
    
    /// Assemble the full system prompt for this team member
    func assembleSystemPrompt(with role: Role?, baseSystemPrompt: String) -> String {
        guard let role = role,
              let rolePrompt = role.systemPrompt(for: experienceLevel) else {
            return baseSystemPrompt
        }
        
        var assembled = baseSystemPrompt
        
        // Add role-specific prompt
        assembled += "\n\n# Team Member Role\n"
        
        let roleDescription = "\(experienceLevel.displayName) \(role.name)"
        
        if let customName = name, !customName.isEmpty {
            assembled += "You are \(customName), a \(roleDescription).\n"
        } else {
            assembled += "You are acting as a \(roleDescription).\n"
        }
        assembled += "\n\(rolePrompt)"
        
        // Add custom instructions if present
        if let addendum = promptAddendum, !addendum.isEmpty {
            assembled += "\n\n# Additional Instructions\n\(addendum)"
        }
        
        return assembled
    }
}
