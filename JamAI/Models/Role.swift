//
//  Role.swift
//  JamAI
//
//  Represents an AI role/persona that can be assigned to a team member
//

import Foundation

/// Experience level for a role
enum ExperienceLevel: String, Codable, Sendable, CaseIterable {
    case junior = "Junior"
    case intermediate = "Intermediate"
    case senior = "Senior"
    case expert = "Expert"
    
    var displayName: String { rawValue }
    
    /// Order/index for sorting and progression
    var order: Int {
        switch self {
        case .junior: return 0
        case .intermediate: return 1
        case .senior: return 2
        case .expert: return 3
        }
    }
}

/// Category for organizing roles
enum RoleCategory: String, Codable, Sendable, CaseIterable {
    case business = "Business"
    case creative = "Creative"
    case technical = "Technical"
    case research = "Research"
    case marketing = "Marketing"
    case design = "Design"
    case education = "Education"
    case healthcare = "Healthcare"
    case legal = "Legal"
    case finance = "Finance"
    case other = "Other"
    
    var displayName: String { rawValue }
}

/// Plan tier required to access a role/level
enum PlanTier: String, Codable, Sendable {
    case free = "Free"
    case pro = "Pro"
    case enterprise = "Enterprise"
    
    var displayName: String { rawValue }
}

/// System prompt for a specific experience level of a role
struct LevelPrompt: Codable, Sendable {
    let level: ExperienceLevel
    let systemPrompt: String
    let requiredTier: PlanTier
    
    init(level: ExperienceLevel, systemPrompt: String, requiredTier: PlanTier = .free) {
        self.level = level
        self.systemPrompt = systemPrompt
        self.requiredTier = requiredTier
    }
}

/// A role definition (e.g., "Research Analyst", "Content Writer")
struct Role: Identifiable, Codable, Sendable {
    let id: String // Unique identifier (e.g., "research-analyst")
    let name: String // Display name (e.g., "Research Analyst")
    let category: RoleCategory
    let icon: String // SF Symbol name
    let color: String // Color identifier (matches NodeColor)
    let description: String
    let levelPrompts: [LevelPrompt] // System prompts for each experience level
    let version: Int // For remote updates
    let isCustom: Bool // User-created roles
    
    init(
        id: String,
        name: String,
        category: RoleCategory,
        icon: String = "person.circle.fill",
        color: String = "blue",
        description: String,
        levelPrompts: [LevelPrompt],
        version: Int = 1,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.color = color
        self.description = description
        self.levelPrompts = levelPrompts
        self.version = version
        self.isCustom = isCustom
    }
    
    /// Get system prompt for a specific level
    func systemPrompt(for level: ExperienceLevel) -> String? {
        levelPrompts.first(where: { $0.level == level })?.systemPrompt
    }
    
    /// Check if a specific level is available for the given plan tier
    func isLevelAvailable(_ level: ExperienceLevel, for tier: PlanTier) -> Bool {
        guard let prompt = levelPrompts.first(where: { $0.level == level }) else {
            return false
        }
        
        // Simple tier hierarchy: Free < Pro < Enterprise
        let tierOrder: [PlanTier: Int] = [.free: 0, .pro: 1, .enterprise: 2]
        let requiredOrder = tierOrder[prompt.requiredTier] ?? 0
        let currentOrder = tierOrder[tier] ?? 0
        
        return currentOrder >= requiredOrder
    }
}
