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
    case product = "Product"
    case ai = "AI"
    case startup = "Startup"
    
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
        self.requiredTier = .free // All levels are free for now
    }
    
    // Custom Codable to default requiredTier to free if not in JSON
    enum CodingKeys: String, CodingKey {
        case level, systemPrompt, requiredTier
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(ExperienceLevel.self, forKey: .level)
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        requiredTier = try container.decodeIfPresent(PlanTier.self, forKey: .requiredTier) ?? .free
    }
}

/// A role definition (e.g., "Software Engineer", "Marketing Strategist")
/// Industry is applied per team member, not per role
struct Role: Identifiable, Codable, Sendable {
    let id: String // Unique identifier (e.g., "software-engineer")
    let name: String // Display name (e.g., "Software Engineer")
    let category: RoleCategory
    let icon: String // SF Symbol name
    let color: String // Color identifier (matches NodeColor)
    let description: String
    let levelPrompts: [LevelPrompt] // System prompts for each experience level
    let version: Int // For remote updates
    let isCustom: Bool // User-created roles
    
    // Custom init for programmatic creation
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
    
    // Custom Codable implementation to provide defaults for optional fields
    enum CodingKeys: String, CodingKey {
        case id, name, category, icon, color, description, levelPrompts, version, isCustom
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(RoleCategory.self, forKey: .category)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        description = try container.decode(String.self, forKey: .description)
        levelPrompts = try container.decode([LevelPrompt].self, forKey: .levelPrompts)
        // Provide defaults for fields that might not be in JSON
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
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
