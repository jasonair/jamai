//
//  AnalyticsEvent.swift
//  JamAI
//
//  Analytics data models for tracking user activity, token usage, and costs
//

import Foundation

/// Detailed token usage event for AI generation
struct TokenUsageEvent: Codable, Identifiable {
    var id: String
    var userId: String
    var projectId: UUID
    var nodeId: UUID
    var teamMemberRoleId: String? // Which team member role was used
    var teamMemberExperienceLevel: String? // Experience level of team member
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var estimatedCostUSD: Double
    var modelUsed: String
    var timestamp: Date
    var generationType: GenerationType // chat, expand, auto-title, etc.
    
    enum GenerationType: String, Codable {
        case chat = "chat"
        case expand = "expand"
        case autoTitle = "auto_title"
        case autoDescription = "auto_description"
    }
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        projectId: UUID,
        nodeId: UUID,
        teamMemberRoleId: String? = nil,
        teamMemberExperienceLevel: String? = nil,
        inputTokens: Int,
        outputTokens: Int,
        modelUsed: String,
        generationType: GenerationType = .chat,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.projectId = projectId
        self.nodeId = nodeId
        self.teamMemberRoleId = teamMemberRoleId
        self.teamMemberExperienceLevel = teamMemberExperienceLevel
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = inputTokens + outputTokens
        self.modelUsed = modelUsed
        self.generationType = generationType
        self.timestamp = timestamp
        
        // Calculate cost based on Gemini 2.0 Flash pricing
        // Input: $0.075 per 1M tokens, Output: $0.30 per 1M tokens
        let inputCost = (Double(inputTokens) / 1_000_000.0) * 0.075
        let outputCost = (Double(outputTokens) / 1_000_000.0) * 0.30
        self.estimatedCostUSD = inputCost + outputCost
    }
}

/// Team member usage tracking
struct TeamMemberUsageEvent: Codable, Identifiable {
    var id: String
    var userId: String
    var projectId: UUID
    var nodeId: UUID
    var roleId: String // Role.id (e.g., "research_analyst")
    var roleName: String // Human-readable role name
    var roleCategory: String // Role category for grouping
    var experienceLevel: String // junior, intermediate, senior, expert
    var timestamp: Date
    var actionType: ActionType
    
    enum ActionType: String, Codable {
        case attached = "attached" // Team member attached to node
        case changed = "changed" // Team member role/level changed
        case removed = "removed" // Team member removed from node
        case used = "used" // Team member used in AI generation
    }
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        projectId: UUID,
        nodeId: UUID,
        roleId: String,
        roleName: String,
        roleCategory: String,
        experienceLevel: String,
        actionType: ActionType,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.projectId = projectId
        self.nodeId = nodeId
        self.roleId = roleId
        self.roleName = roleName
        self.roleCategory = roleCategory
        self.experienceLevel = experienceLevel
        self.actionType = actionType
        self.timestamp = timestamp
    }
}

/// Project activity tracking
struct ProjectActivityEvent: Codable, Identifiable {
    var id: String
    var userId: String
    var projectId: UUID
    var projectName: String
    var activityType: ActivityType
    var timestamp: Date
    var metadata: [String: String]?
    
    enum ActivityType: String, Codable {
        case created = "created"
        case opened = "opened"
        case closed = "closed"
        case renamed = "renamed"
        case deleted = "deleted"
    }
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        projectId: UUID,
        projectName: String,
        activityType: ActivityType,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.projectId = projectId
        self.projectName = projectName
        self.activityType = activityType
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

/// Node creation tracking (nodes, notes, edges)
struct NodeCreationEvent: Codable, Identifiable {
    var id: String
    var userId: String
    var projectId: UUID
    var nodeId: UUID
    var nodeType: String // "standard", "note", "edge"
    var creationMethod: CreationMethod
    var parentNodeId: UUID?
    var teamMemberRoleId: String? // If created with team member
    var timestamp: Date
    
    enum CreationMethod: String, Codable {
        case manual = "manual"
        case expand = "expand"
        case childNode = "child_node"
        case note = "note"
    }
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        projectId: UUID,
        nodeId: UUID,
        nodeType: String,
        creationMethod: CreationMethod,
        parentNodeId: UUID? = nil,
        teamMemberRoleId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.projectId = projectId
        self.nodeId = nodeId
        self.nodeType = nodeType
        self.creationMethod = creationMethod
        self.parentNodeId = parentNodeId
        self.teamMemberRoleId = teamMemberRoleId
        self.timestamp = timestamp
    }
}

/// Daily aggregated analytics for efficient dashboard queries
struct DailyAnalytics: Codable, Identifiable {
    var id: String // Format: "{userId}_{date}" e.g., "user123_2024-01-15"
    var userId: String
    var date: Date
    var totalTokensInput: Int
    var totalTokensOutput: Int
    var totalTokens: Int
    var totalCostUSD: Double
    var totalGenerations: Int
    var totalNodesCreated: Int
    var totalNotesCreated: Int
    var totalEdgesCreated: Int
    var totalProjectsCreated: Int
    var totalProjectsOpened: Int
    var uniqueTeamMembersUsed: Set<String> // Role IDs
    var teamMemberUsageCount: [String: Int] // Role ID -> count
    var generationsByType: [String: Int] // GenerationType -> count
    var lastUpdated: Date
    
    init(
        userId: String,
        date: Date
    ) {
        let dateString = ISO8601DateFormatter().string(from: date).prefix(10) // YYYY-MM-DD
        self.id = "\(userId)_\(dateString)"
        self.userId = userId
        self.date = date
        self.totalTokensInput = 0
        self.totalTokensOutput = 0
        self.totalTokens = 0
        self.totalCostUSD = 0.0
        self.totalGenerations = 0
        self.totalNodesCreated = 0
        self.totalNotesCreated = 0
        self.totalEdgesCreated = 0
        self.totalProjectsCreated = 0
        self.totalProjectsOpened = 0
        self.uniqueTeamMembersUsed = []
        self.teamMemberUsageCount = [:]
        self.generationsByType = [:]
        self.lastUpdated = Date()
    }
}

/// Plan analytics for tracking paid users and revenue
struct PlanAnalytics: Codable, Identifiable {
    var id: String // Date in YYYY-MM-DD format
    var date: Date
    var planCounts: [String: Int] // Plan name -> count
    var totalPaidUsers: Int // Premium + Pro
    var totalTrialUsers: Int
    var totalFreeUsers: Int
    var totalUsers: Int
    var totalCreditsUsed: Int
    var totalCreditsGranted: Int
    var estimatedRevenue: Double // Based on plan pricing
    var lastUpdated: Date
    
    init(date: Date) {
        let dateString = ISO8601DateFormatter().string(from: date).prefix(10)
        self.id = String(dateString)
        self.date = date
        self.planCounts = [:]
        self.totalPaidUsers = 0
        self.totalTrialUsers = 0
        self.totalFreeUsers = 0
        self.totalUsers = 0
        self.totalCreditsUsed = 0
        self.totalCreditsGranted = 0
        self.estimatedRevenue = 0.0
        self.lastUpdated = Date()
    }
}
