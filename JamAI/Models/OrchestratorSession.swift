//
//  OrchestratorSession.swift
//  JamAI
//
//  Models for multi-agent orchestration (Jam Squad feature)
//

import Foundation

// MARK: - Orchestrator Status

/// Status of an orchestration session
enum OrchestratorStatus: String, Codable, Sendable {
    case proposing        // AI is analyzing and proposing roles
    case awaitingApproval // Waiting for user to approve proposed roles
    case spawning         // Creating delegate nodes and edges
    case consulting       // Delegate nodes are generating responses
    case synthesizing     // Master node is synthesizing responses
    case completed        // Orchestration finished successfully
    case cancelled        // User cancelled the orchestration
    case failed           // Orchestration failed due to error
    
    var displayName: String {
        switch self {
        case .proposing: return "Analyzing..."
        case .awaitingApproval: return "Awaiting Approval"
        case .spawning: return "Assembling Team..."
        case .consulting: return "Consulting Experts..."
        case .synthesizing: return "Synthesizing..."
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .proposing, .awaitingApproval, .spawning, .consulting, .synthesizing:
            return true
        case .completed, .cancelled, .failed:
            return false
        }
    }
    
    var icon: String {
        switch self {
        case .proposing: return "brain"
        case .awaitingApproval: return "checkmark.circle"
        case .spawning: return "plus.circle"
        case .consulting: return "bubble.left.and.bubble.right"
        case .synthesizing: return "arrow.triangle.merge"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Orchestrator Role

/// Role of a node in an orchestration session
enum OrchestratorRole: String, Codable, Sendable {
    case master    // The coordinating node that initiated the orchestration
    case delegate  // A specialist node spawned by the master
    
    var displayName: String {
        switch self {
        case .master: return "Orchestrator"
        case .delegate: return "Specialist"
        }
    }
}

// MARK: - Proposed Role

/// A role proposed by the AI for the expert panel
struct ProposedRole: Codable, Identifiable, Sendable {
    let id: UUID
    let roleId: String              // References Role.id from roles.json
    let roleName: String            // Display name for UI
    let justification: String       // Why this role is needed
    let tailoredQuestion: String    // Specific question for this specialist
    var isApproved: Bool            // User can toggle this
    
    init(
        id: UUID = UUID(),
        roleId: String,
        roleName: String,
        justification: String,
        tailoredQuestion: String,
        isApproved: Bool = true
    ) {
        self.id = id
        self.roleId = roleId
        self.roleName = roleName
        self.justification = justification
        self.tailoredQuestion = tailoredQuestion
        self.isApproved = isApproved
    }
}

// MARK: - Delegate Status

/// Tracks the status of each delegate node during consultation
struct DelegateStatus: Codable, Identifiable, Sendable {
    let id: UUID           // Same as the delegate node ID
    let roleId: String
    let roleName: String
    var status: DelegateConsultationStatus
    var responsePreview: String?  // First ~100 chars of response for UI
    
    init(
        id: UUID,
        roleId: String,
        roleName: String,
        status: DelegateConsultationStatus = .waiting,
        responsePreview: String? = nil
    ) {
        self.id = id
        self.roleId = roleId
        self.roleName = roleName
        self.status = status
        self.responsePreview = responsePreview
    }
}

enum DelegateConsultationStatus: String, Codable, Sendable {
    case waiting    // Waiting to start
    case thinking   // AI is generating response
    case responded  // Response complete
    case failed     // Generation failed
    
    var icon: String {
        switch self {
        case .waiting: return "clock"
        case .thinking: return "ellipsis.circle"
        case .responded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Orchestrator Session

/// Tracks a complete multi-agent orchestration session
struct OrchestratorSession: Codable, Identifiable, Sendable {
    let id: UUID
    let masterNodeId: UUID
    let projectId: UUID
    let originalPrompt: String
    var status: OrchestratorStatus
    var proposedRoles: [ProposedRole]
    var delegateStatuses: [DelegateStatus]
    
    // Node and edge tracking
    var delegateNodeIds: [UUID]
    var masterToDelegateEdgeIds: [UUID]
    var delegateToMasterEdgeIds: [UUID]
    
    // Timestamps
    var createdAt: Date
    var proposedAt: Date?
    var approvedAt: Date?
    var consultationStartedAt: Date?
    var synthesisStartedAt: Date?
    var completedAt: Date?
    
    // Error tracking
    var errorMessage: String?
    
    init(
        id: UUID = UUID(),
        masterNodeId: UUID,
        projectId: UUID,
        originalPrompt: String,
        status: OrchestratorStatus = .proposing,
        proposedRoles: [ProposedRole] = [],
        delegateStatuses: [DelegateStatus] = [],
        delegateNodeIds: [UUID] = [],
        masterToDelegateEdgeIds: [UUID] = [],
        delegateToMasterEdgeIds: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.masterNodeId = masterNodeId
        self.projectId = projectId
        self.originalPrompt = originalPrompt
        self.status = status
        self.proposedRoles = proposedRoles
        self.delegateStatuses = delegateStatuses
        self.delegateNodeIds = delegateNodeIds
        self.masterToDelegateEdgeIds = masterToDelegateEdgeIds
        self.delegateToMasterEdgeIds = delegateToMasterEdgeIds
        self.createdAt = createdAt
    }
    
    // MARK: - Computed Properties
    
    /// Roles that the user has approved
    var approvedRoles: [ProposedRole] {
        proposedRoles.filter { $0.isApproved }
    }
    
    /// Number of delegates that have responded
    var respondedCount: Int {
        delegateStatuses.filter { $0.status == .responded }.count
    }
    
    /// Total number of delegates
    var totalDelegates: Int {
        delegateStatuses.count
    }
    
    /// Whether all delegates have responded
    var allDelegatesResponded: Bool {
        !delegateStatuses.isEmpty && delegateStatuses.allSatisfy { $0.status == .responded }
    }
    
    /// Progress percentage (0.0 to 1.0)
    var progress: Double {
        guard totalDelegates > 0 else { return 0 }
        return Double(respondedCount) / Double(totalDelegates)
    }
    
    // MARK: - Mutating Methods
    
    /// Update the status of a specific delegate
    mutating func updateDelegateStatus(nodeId: UUID, status: DelegateConsultationStatus, responsePreview: String? = nil) {
        if let index = delegateStatuses.firstIndex(where: { $0.id == nodeId }) {
            delegateStatuses[index].status = status
            if let preview = responsePreview {
                delegateStatuses[index].responsePreview = String(preview.prefix(100))
            }
        }
    }
    
    /// Toggle approval for a proposed role
    mutating func toggleRoleApproval(roleId: UUID) {
        if let index = proposedRoles.firstIndex(where: { $0.id == roleId }) {
            proposedRoles[index].isApproved.toggle()
        }
    }
    
    /// Set all roles to approved or not approved
    mutating func setAllRolesApproval(_ approved: Bool) {
        for index in proposedRoles.indices {
            proposedRoles[index].isApproved = approved
        }
    }
}

// MARK: - AI Response Parsing

/// Structure for parsing AI's role proposal response
struct RoleProposalResponse: Codable {
    let needsPanel: Bool
    let reason: String
    let roles: [RoleProposal]
    
    struct RoleProposal: Codable {
        let roleId: String
        let justification: String
        let question: String
    }
}

/// Structure for parsing AI's synthesis prompt
struct SynthesisContext {
    let originalPrompt: String
    let expertResponses: [(roleName: String, response: String)]
    
    func buildSynthesisPrompt() -> String {
        var prompt = """
        You are synthesizing responses from multiple expert consultations to provide a comprehensive answer.
        
        ## Original Question
        \(originalPrompt)
        
        ## Expert Responses
        
        """
        
        for (roleName, response) in expertResponses {
            prompt += """
            ### \(roleName)
            \(response)
            
            """
        }
        
        prompt += """
        
        ## Your Task
        
        Provide a comprehensive synthesis that:
        1. **Integrates** all expert perspectives into a cohesive response
        2. **Highlights** areas of consensus between experts
        3. **Addresses** any conflicts or different approaches, recommending the best path
        4. **Provides** clear, actionable next steps
        
        Format your response with clear sections and be thorough but concise.
        """
        
        return prompt
    }
}
