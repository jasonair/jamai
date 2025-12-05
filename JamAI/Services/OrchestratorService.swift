//
//  OrchestratorService.swift
//  JamAI
//
//  Service for multi-agent orchestration (Jam Squad feature)
//  Coordinates master nodes spawning delegate specialist nodes,
//  asking tailored questions, and synthesizing responses.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class OrchestratorService: ObservableObject {
    static let shared = OrchestratorService()
    
    // MARK: - Published State
    
    var activeSessions: [UUID: OrchestratorSession] = [:]
    var isProcessing = false
    var errorMessage: String?
    
    // MARK: - Safeguards
    
    /// Prevents recursive routing operations
    private var isRoutingInProgress = false
    
    /// Maximum number of routing checks per minute (rate limiting)
    private let maxRoutingChecksPerMinute = 10
    private var routingCheckTimestamps: [Date] = []
    
    // MARK: - Constants
    
    private let verticalGap: CGFloat = 100  // Gap between bottom of master and top of delegates
    private let horizontalGap: CGFloat = 100  // Gap between delegate nodes (same as vertical)
    private let maxDelegates = 5  // Maximum number of delegate nodes
    
    private init() {}
    
    // MARK: - Session Management
    
    /// Get active session for a node (if it's a master)
    func session(for nodeId: UUID) -> OrchestratorSession? {
        activeSessions.values.first { $0.masterNodeId == nodeId }
    }
    
    /// Check if a node is part of any active orchestration
    func isNodeInActiveSession(_ nodeId: UUID) -> Bool {
        activeSessions.values.contains { session in
            session.masterNodeId == nodeId || session.delegateNodeIds.contains(nodeId)
        }
    }
    
    // MARK: - Step 1: Analyze and Propose Roles
    
    /// Analyze the user's prompt and propose expert roles
    /// Includes credit check and prevents concurrent orchestrations
    func analyzeAndPropose(
        nodeId: UUID,
        prompt: String,
        viewModel: CanvasViewModel
    ) async throws -> OrchestratorSession {
        // Safeguard: Prevent multiple concurrent orchestrations
        guard !isProcessing else {
            throw OrchestratorError.orchestrationInProgress
        }
        
        // Safeguard: Check if node is already in an orchestration
        guard !isNodeInActiveSession(nodeId) else {
            throw OrchestratorError.nodeAlreadyOrchestrating
        }
        
        // Safeguard: Check credits before starting (estimate ~15-20 credits for full orchestration)
        if AIProviderManager.shared.activeProvider != .local {
            guard CreditTracker.shared.canGenerateResponse() else {
                throw OrchestratorError.insufficientCredits
            }
        }
        
        guard let node = viewModel.nodes[nodeId] else {
            throw OrchestratorError.nodeNotFound
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Create initial session
        var session = OrchestratorSession(
            masterNodeId: nodeId,
            projectId: node.projectId,
            originalPrompt: prompt,
            status: .proposing
        )
        activeSessions[session.id] = session
        
        // Build the analysis prompt
        let analysisPrompt = buildAnalysisPrompt(for: prompt)
        
        // Call AI to analyze and propose roles
        do {
            let response = try await generateAnalysis(prompt: analysisPrompt, viewModel: viewModel)
            let proposedRoles = parseRoleProposal(from: response)
            
            session.proposedRoles = proposedRoles
            session.status = .awaitingApproval
            session.proposedAt = Date()
            activeSessions[session.id] = session
            
            return session
        } catch {
            session.status = .failed
            session.errorMessage = error.localizedDescription
            activeSessions[session.id] = session
            throw error
        }
    }
    
    // MARK: - Step 2: Execute Approved Plan (Spawn Nodes)
    
    /// Create delegate nodes for approved roles
    func executeApprovedPlan(
        session: inout OrchestratorSession,
        viewModel: CanvasViewModel
    ) async throws {
        guard session.status == .awaitingApproval else {
            throw OrchestratorError.invalidSessionState
        }
        
        let approvedRoles = session.approvedRoles
        guard !approvedRoles.isEmpty else {
            throw OrchestratorError.noRolesApproved
        }
        
        guard approvedRoles.count <= maxDelegates else {
            throw OrchestratorError.tooManyDelegates
        }
        
        session.status = .spawning
        session.approvedAt = Date()
        activeSessions[session.id] = session
        
        guard let masterNode = viewModel.nodes[session.masterNodeId] else {
            throw OrchestratorError.nodeNotFound
        }
        
        // Mark master node as orchestrator
        var updatedMaster = masterNode
        updatedMaster.orchestratorSessionId = session.id
        updatedMaster.orchestratorRole = .master
        viewModel.updateNode(updatedMaster)
        
        // Calculate positions for delegate nodes
        let delegatePositions = calculateDelegatePositions(
            masterNode: masterNode,
            delegateCount: approvedRoles.count
        )
        
        var delegateNodeIds: [UUID] = []
        var masterToDelegateEdgeIds: [UUID] = []
        var delegateToMasterEdgeIds: [UUID] = []
        var delegateStatuses: [DelegateStatus] = []
        
        // Create delegate nodes
        for (index, proposedRole) in approvedRoles.enumerated() {
            let position = delegatePositions[index]
            
            // Find the role from RoleManager
            guard let role = RoleManager.shared.role(withId: proposedRole.roleId) else {
                print("⚠️ Role not found: \(proposedRole.roleId), using fallback")
                continue
            }
            
            // Create the delegate node
            let delegateId = createDelegateNode(
                at: position,
                role: role,
                proposedRole: proposedRole,
                sessionId: session.id,
                masterNode: masterNode,
                viewModel: viewModel
            )
            
            delegateNodeIds.append(delegateId)
            
            // Add to orchestrating set for visual feedback (glow)
            viewModel.orchestratingNodeIds.insert(delegateId)
            
            // Create bidirectional edges
            // Master → Delegate (so delegate can see master's context)
            let edgeToDelegate = Edge(
                projectId: masterNode.projectId,
                sourceId: session.masterNodeId,
                targetId: delegateId,
                color: masterNode.color != "none" ? masterNode.color : nil
            )
            viewModel.addEdge(edgeToDelegate)
            masterToDelegateEdgeIds.append(edgeToDelegate.id)
            
            // Delegate → Master (so master can collect delegate's response)
            let edgeToMaster = Edge(
                projectId: masterNode.projectId,
                sourceId: delegateId,
                targetId: session.masterNodeId,
                color: role.color
            )
            viewModel.addEdge(edgeToMaster)
            delegateToMasterEdgeIds.append(edgeToMaster.id)
            
            // Track delegate status
            delegateStatuses.append(DelegateStatus(
                id: delegateId,
                roleId: role.id,
                roleName: role.name,
                status: .waiting
            ))
        }
        
        // Update session with created nodes and edges
        session.delegateNodeIds = delegateNodeIds
        session.masterToDelegateEdgeIds = masterToDelegateEdgeIds
        session.delegateToMasterEdgeIds = delegateToMasterEdgeIds
        session.delegateStatuses = delegateStatuses
        activeSessions[session.id] = session
    }
    
    // MARK: - Step 3: Consult Delegates
    
    /// Send tailored questions to each delegate and generate responses
    func consultDelegates(
        session: inout OrchestratorSession,
        viewModel: CanvasViewModel
    ) async throws {
        guard session.status == .spawning || session.status == .consulting else {
            throw OrchestratorError.invalidSessionState
        }
        
        session.status = .consulting
        session.consultationStartedAt = Date()
        activeSessions[session.id] = session
        
        // Process each delegate sequentially to avoid overwhelming the API
        for (index, delegateId) in session.delegateNodeIds.enumerated() {
            guard let proposedRole = session.approvedRoles[safe: index] else { continue }
            
            // Update status to thinking
            session.updateDelegateStatus(nodeId: delegateId, status: .thinking)
            activeSessions[session.id] = session
            
            do {
                // Send the tailored question to the delegate (skipRouting for delegates)
                viewModel.generateResponse(
                    for: delegateId,
                    prompt: proposedRole.tailoredQuestion,
                    skipRouting: true
                )
                
                // Wait for generation to complete
                try await waitForGeneration(nodeId: delegateId, viewModel: viewModel)
                
                // Get response preview
                if let node = viewModel.nodes[delegateId],
                   let lastMessage = node.conversation.last(where: { $0.role == .assistant }) {
                    session.updateDelegateStatus(
                        nodeId: delegateId,
                        status: .responded,
                        responsePreview: lastMessage.content
                    )
                } else {
                    session.updateDelegateStatus(nodeId: delegateId, status: .responded)
                }
                
                // Remove from orchestrating set - this delegate is done
                viewModel.orchestratingNodeIds.remove(delegateId)
                
            } catch {
                session.updateDelegateStatus(nodeId: delegateId, status: .failed)
                viewModel.orchestratingNodeIds.remove(delegateId)
                print("⚠️ Delegate \(delegateId) failed: \(error)")
            }
            
            activeSessions[session.id] = session
        }
    }
    
    // MARK: - Step 4: Synthesize Responses
    
    /// Collect all delegate responses and synthesize in master node
    func synthesizeResponses(
        session: inout OrchestratorSession,
        viewModel: CanvasViewModel
    ) async throws {
        guard session.allDelegatesResponded || session.status == .consulting else {
            throw OrchestratorError.delegatesNotComplete
        }
        
        session.status = .synthesizing
        session.synthesisStartedAt = Date()
        activeSessions[session.id] = session
        
        // Collect responses from all delegates
        var expertResponses: [(roleName: String, response: String)] = []
        
        for (index, delegateId) in session.delegateNodeIds.enumerated() {
            guard let node = viewModel.nodes[delegateId],
                  let delegateStatus = session.delegateStatuses[safe: index],
                  delegateStatus.status == .responded else {
                continue
            }
            
            // Get the last assistant message as the response
            if let lastResponse = node.conversation.last(where: { $0.role == .assistant }) {
                expertResponses.append((
                    roleName: delegateStatus.roleName,
                    response: lastResponse.content
                ))
            }
        }
        
        // Build synthesis context and prompt
        let synthesisContext = SynthesisContext(
            originalPrompt: session.originalPrompt,
            expertResponses: expertResponses
        )
        
        let synthesisPrompt = synthesisContext.buildSynthesisPrompt()
        
        // Ensure master is in orchestrating set for visual feedback during synthesis
        viewModel.orchestratingNodeIds.insert(session.masterNodeId)
        
        // Generate synthesis in master node (skipRouting prevents routing check)
        viewModel.generateResponse(
            for: session.masterNodeId,
            prompt: synthesisPrompt,
            skipRouting: true
        )
        
        // Wait for synthesis to complete
        try await waitForGeneration(nodeId: session.masterNodeId, viewModel: viewModel)
        
        // Mark session as complete
        session.status = .completed
        session.completedAt = Date()
        activeSessions[session.id] = session
        
        // Clear master from orchestrating set
        viewModel.orchestratingNodeIds.remove(session.masterNodeId)
    }
    
    // MARK: - Full Orchestration Flow
    
    /// Run the complete orchestration flow after user approves roles
    func runOrchestration(
        session: inout OrchestratorSession,
        viewModel: CanvasViewModel
    ) async throws {
        // Step 2: Spawn delegate nodes
        try await executeApprovedPlan(session: &session, viewModel: viewModel)
        
        // Step 3: Consult all delegates
        try await consultDelegates(session: &session, viewModel: viewModel)
        
        // Step 4: Synthesize responses
        try await synthesizeResponses(session: &session, viewModel: viewModel)
    }
    
    // MARK: - Cancel Session
    
    func cancelSession(_ sessionId: UUID) {
        guard var session = activeSessions[sessionId] else { return }
        session.status = .cancelled
        activeSessions[sessionId] = session
    }
    
    // MARK: - Expert Routing (Defer to Delegate)
    
    /// Result of checking if a question should be routed to an expert
    struct ExpertRoutingResult {
        let shouldRoute: Bool
        let delegateNodeId: UUID?
        let delegateRoleName: String?
        let refinedQuestion: String?
    }
    
    /// Check if a question from the master node should be routed to a specific delegate
    /// Includes rate limiting to prevent excessive token usage
    func checkForExpertRouting(
        masterNodeId: UUID,
        prompt: String,
        viewModel: CanvasViewModel
    ) async throws -> ExpertRoutingResult {
        // Rate limiting: Clean old timestamps and check rate
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        routingCheckTimestamps = routingCheckTimestamps.filter { $0 > oneMinuteAgo }
        
        guard routingCheckTimestamps.count < maxRoutingChecksPerMinute else {
            print("⚠️ Routing check rate limit reached (\(maxRoutingChecksPerMinute)/min), skipping")
            return ExpertRoutingResult(shouldRoute: false, delegateNodeId: nil, delegateRoleName: nil, refinedQuestion: nil)
        }
        
        // Record this check
        routingCheckTimestamps.append(Date())
        
        guard let masterNode = viewModel.nodes[masterNodeId],
              masterNode.orchestratorRole == .master else {
            return ExpertRoutingResult(shouldRoute: false, delegateNodeId: nil, delegateRoleName: nil, refinedQuestion: nil)
        }
        
        // Find connected delegate nodes via edges (works even after app restart)
        // Look for nodes that are delegates connected to this master
        let connectedDelegateIds = viewModel.edges.values
            .filter { $0.sourceId == masterNodeId }
            .map { $0.targetId }
        
        // Get the connected delegates and their roles
        let delegateInfo = connectedDelegateIds.compactMap { delegateId -> (UUID, String, String)? in
            guard let node = viewModel.nodes[delegateId],
                  node.orchestratorRole == .delegate,
                  let teamMember = node.teamMember,
                  let role = RoleManager.shared.role(withId: teamMember.roleId) else {
                return nil
            }
            return (delegateId, role.id, role.name)
        }
        
        guard !delegateInfo.isEmpty else {
            return ExpertRoutingResult(shouldRoute: false, delegateNodeId: nil, delegateRoleName: nil, refinedQuestion: nil)
        }
        
        // Build prompt to check if routing is needed
        let routingPrompt = buildRoutingCheckPrompt(userPrompt: prompt, delegates: delegateInfo)
        
        // Ask AI if this should be routed
        let response = try await generateAnalysis(prompt: routingPrompt, viewModel: viewModel)
        return parseRoutingResponse(from: response, delegates: delegateInfo)
    }
    
    /// Route a question to a delegate, get response, and return it to master
    /// Uses skipRouting: true to prevent recursive routing checks
    func routeToExpert(
        masterNodeId: UUID,
        delegateNodeId: UUID,
        question: String,
        viewModel: CanvasViewModel
    ) async throws {
        // Safeguard: Prevent routing if already routing
        guard !isRoutingInProgress else {
            print("⚠️ Routing already in progress, skipping")
            return
        }
        
        isRoutingInProgress = true
        defer { isRoutingInProgress = false }
        
        guard let _ = viewModel.nodes[masterNodeId],
              let delegateNode = viewModel.nodes[delegateNodeId] else {
            throw OrchestratorError.nodeNotFound
        }
        
        // Mark both nodes as orchestrating for visual feedback
        viewModel.orchestratingNodeIds.insert(masterNodeId)
        viewModel.orchestratingNodeIds.insert(delegateNodeId)
        
        // Send question to delegate (skipRouting prevents recursion)
        viewModel.generateResponse(for: delegateNodeId, prompt: question, skipRouting: true)
        
        // Wait for delegate response
        try await waitForGeneration(nodeId: delegateNodeId, viewModel: viewModel)
        
        // Get the delegate's response
        guard let updatedDelegate = viewModel.nodes[delegateNodeId],
              let delegateResponse = updatedDelegate.conversation.last(where: { $0.role == .assistant }) else {
            viewModel.orchestratingNodeIds.remove(masterNodeId)
            viewModel.orchestratingNodeIds.remove(delegateNodeId)
            throw OrchestratorError.delegatesNotComplete
        }
        
        // Clear delegate from orchestrating
        viewModel.orchestratingNodeIds.remove(delegateNodeId)
        
        // Get delegate role name and node title for attribution
        let roleName = delegateNode.teamMember.flatMap { RoleManager.shared.role(withId: $0.roleId)?.name } ?? "Expert"
        let delegateTitle = delegateNode.title.isEmpty ? roleName : delegateNode.title
        
        // Truncate long responses to save tokens (keep first ~2000 chars)
        let truncatedResponse: String
        let responseIsTruncated: Bool
        if delegateResponse.content.count > 2000 {
            truncatedResponse = String(delegateResponse.content.prefix(2000)) + "..."
            responseIsTruncated = true
        } else {
            truncatedResponse = delegateResponse.content
            responseIsTruncated = false
        }
        
        // Build synthesis prompt that attributes the response (concise to save tokens)
        let truncationNote = responseIsTruncated 
            ? "\n\n💡 *For the complete detailed response, check the \(delegateTitle) node directly.*"
            : ""
        
        let attributionPrompt = """
        The \(roleName) provided this response:
        
        \(truncatedResponse)
        
        Summarize the key points from the \(roleName), attributing the insights to them.\(truncationNote)
        """
        
        // Generate attributed response in master node (skipRouting prevents recursion)
        viewModel.generateResponse(for: masterNodeId, prompt: attributionPrompt, skipRouting: true)
        
        // Wait for master synthesis
        try await waitForGeneration(nodeId: masterNodeId, viewModel: viewModel)
        
        // Clear master from orchestrating
        viewModel.orchestratingNodeIds.remove(masterNodeId)
    }
    
    /// Build prompt to check if a question should be routed to an expert (concise to save tokens)
    private func buildRoutingCheckPrompt(userPrompt: String, delegates: [(UUID, String, String)]) -> String {
        let delegateList = delegates.map { "\($0.1): \($0.2)" }.joined(separator: ", ")
        
        return """
        Question: \(userPrompt)
        Experts: \(delegateList)
        
        Should this route to one expert? Look for "from X perspective", "ask the X", or domain-specific questions.
        JSON only: {"shouldRoute":bool,"roleId":"id-or-null","refinedQuestion":"question-or-null"}
        """
    }
    
    /// Parse the routing check response
    private func parseRoutingResponse(from response: String, delegates: [(UUID, String, String)]) -> ExpertRoutingResult {
        let jsonString = extractJSON(from: response)
        
        guard let data = jsonString.data(using: .utf8) else {
            return ExpertRoutingResult(shouldRoute: false, delegateNodeId: nil, delegateRoleName: nil, refinedQuestion: nil)
        }
        
        struct RoutingResponse: Codable {
            let shouldRoute: Bool
            let roleId: String?
            let reason: String?
            let refinedQuestion: String?
        }
        
        do {
            let parsed = try JSONDecoder().decode(RoutingResponse.self, from: data)
            
            if parsed.shouldRoute, let roleId = parsed.roleId {
                // Find the delegate with this role
                if let delegate = delegates.first(where: { $0.1 == roleId }) {
                    return ExpertRoutingResult(
                        shouldRoute: true,
                        delegateNodeId: delegate.0,
                        delegateRoleName: delegate.2,
                        refinedQuestion: parsed.refinedQuestion
                    )
                }
            }
            
            return ExpertRoutingResult(shouldRoute: false, delegateNodeId: nil, delegateRoleName: nil, refinedQuestion: nil)
        } catch {
            print("⚠️ Failed to parse routing response: \(error)")
            return ExpertRoutingResult(shouldRoute: false, delegateNodeId: nil, delegateRoleName: nil, refinedQuestion: nil)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Build the prompt for AI to analyze and propose roles
    private func buildAnalysisPrompt(for userPrompt: String) -> String {
        let availableRoles = RoleManager.shared.roles.map { role in
            "- \(role.id): \(role.name) (\(role.category.displayName)) - \(role.description)"
        }.joined(separator: "\n")
        
        return """
        You are an expert orchestrator that analyzes complex questions and assembles the right team of specialists.
        
        ## User's Question
        \(userPrompt)
        
        ## Available Specialist Roles
        \(availableRoles)
        
        ## Your Task
        Analyze this question and determine which 2-4 specialists would provide the most valuable perspectives.
        
        For each specialist you recommend:
        1. Choose from the available roles above (use the exact roleId)
        2. Explain briefly why this specialist is needed
        3. Write a specific, tailored question for them to answer
        
        Respond ONLY with valid JSON in this exact format:
        {
          "needsPanel": true,
          "reason": "Brief explanation of why multiple experts would help",
          "roles": [
            {
              "roleId": "exact-role-id-from-list",
              "justification": "Why this specialist is needed",
              "question": "Specific question tailored for this specialist's expertise"
            }
          ]
        }
        
        Important:
        - Choose 2-4 specialists maximum
        - Each question should be specific to that specialist's domain
        - Questions should be different angles on the same problem
        - Use exact roleId values from the list above
        """
    }
    
    /// Generate analysis using AI
    private func generateAnalysis(prompt: String, viewModel: CanvasViewModel) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var result = ""
            
            AIProviderManager.shared.client?.generateStreaming(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that responds only with valid JSON.",
                context: [],
                onChunk: { chunk in
                    result += chunk
                },
                onComplete: { completionResult in
                    switch completionResult {
                    case .success:
                        continuation.resume(returning: result)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )
        }
    }
    
    /// Parse AI response into proposed roles
    private func parseRoleProposal(from response: String) -> [ProposedRole] {
        // Try to extract JSON from the response
        let jsonString = extractJSON(from: response)
        
        guard let data = jsonString.data(using: .utf8) else {
            print("⚠️ Failed to convert response to data")
            return createFallbackRoles()
        }
        
        do {
            let proposal = try JSONDecoder().decode(RoleProposalResponse.self, from: data)
            
            return proposal.roles.compactMap { roleProposal in
                // Validate that the role exists
                guard let role = RoleManager.shared.role(withId: roleProposal.roleId) else {
                    print("⚠️ Unknown role ID: \(roleProposal.roleId)")
                    return nil
                }
                
                return ProposedRole(
                    roleId: role.id,
                    roleName: role.name,
                    justification: roleProposal.justification,
                    tailoredQuestion: roleProposal.question
                )
            }
        } catch {
            print("⚠️ Failed to parse role proposal: \(error)")
            return createFallbackRoles()
        }
    }
    
    /// Extract JSON from a response that might have extra text
    private func extractJSON(from text: String) -> String {
        // Try to find JSON object in the response
        if let startIndex = text.firstIndex(of: "{"),
           let endIndex = text.lastIndex(of: "}") {
            return String(text[startIndex...endIndex])
        }
        return text
    }
    
    /// Create fallback roles if parsing fails
    private func createFallbackRoles() -> [ProposedRole] {
        // Return a sensible default set
        return [
            ProposedRole(
                roleId: "research-analyst",
                roleName: "Research Analyst",
                justification: "To analyze and research the problem",
                tailoredQuestion: "Please analyze this problem and provide your research insights."
            )
        ]
    }
    
    /// Calculate positions for delegate nodes in org-chart layout
    /// Ensures middle delegate is centered under master node
    private func calculateDelegatePositions(
        masterNode: Node,
        delegateCount: Int
    ) -> [CGPoint] {
        guard delegateCount > 0 else { return [] }
        
        // Default delegate node width (same as master for visual consistency)
        let delegateWidth: CGFloat = masterNode.width
        
        // Calculate vertical position: below master node with gap
        let verticalPosition = masterNode.y + masterNode.height + verticalGap
        
        // Calculate horizontal spacing: delegate width + gap
        let totalSpacing = delegateWidth + horizontalGap
        
        // Center the delegates horizontally under master
        // For odd count: middle node aligns with master center
        // For even count: gap between middle two nodes aligns with master center
        let masterCenterX = masterNode.x + (masterNode.width / 2)
        
        // Total width from center of first delegate to center of last delegate
        let totalWidth = CGFloat(delegateCount - 1) * totalSpacing
        
        // Start X is the center of the first (leftmost) delegate
        let firstDelegateCenterX = masterCenterX - (totalWidth / 2)
        
        return (0..<delegateCount).map { index in
            let delegateCenterX = firstDelegateCenterX + (CGFloat(index) * totalSpacing)
            // Convert center X to top-left X (node position)
            let delegateX = delegateCenterX - (delegateWidth / 2)
            return CGPoint(
                x: delegateX,
                y: verticalPosition
            )
        }
    }
    
    /// Create a delegate node with the specified role
    private func createDelegateNode(
        at position: CGPoint,
        role: Role,
        proposedRole: ProposedRole,
        sessionId: UUID,
        masterNode: Node,
        viewModel: CanvasViewModel
    ) -> UUID {
        var node = Node(
            projectId: masterNode.projectId,
            x: position.x,
            y: position.y,
            title: role.name
        )
        
        // Set team member with the role
        let teamMember = TeamMember(
            roleId: role.id,
            experienceLevel: .expert
        )
        node.setTeamMember(teamMember)
        
        // Set orchestrator metadata
        node.orchestratorSessionId = sessionId
        node.orchestratorRole = .delegate
        
        // Use default node color (don't inherit role color)
        // node.color = role.color
        
        // Set personality to match master or default
        node.personality = masterNode.personality
        
        // Add to view model and save
        viewModel.nodes[node.id] = node
        viewModel.updateNode(node)
        
        // Bring to front
        viewModel.bringToFront([node.id])
        
        return node.id
    }
    
    /// Wait for AI generation to complete for a node
    private func waitForGeneration(nodeId: UUID, viewModel: CanvasViewModel) async throws {
        // Poll until generation is complete (max 90 seconds for longer responses)
        let maxWait: TimeInterval = 90
        let pollInterval: TimeInterval = 0.2  // Faster polling for more responsive UI
        var elapsed: TimeInterval = 0
        
        while elapsed < maxWait {
            // Check if generation is complete (generatingNodeId cleared or changed)
            if viewModel.generatingNodeId != nodeId {
                // Small delay to ensure UI has updated
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                return // Generation complete
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            elapsed += pollInterval
        }
        
        throw OrchestratorError.generationTimeout
    }
}

// MARK: - Errors

enum OrchestratorError: LocalizedError {
    case nodeNotFound
    case invalidSessionState
    case noRolesApproved
    case tooManyDelegates
    case delegatesNotComplete
    case generationTimeout
    case parsingFailed
    case orchestrationInProgress
    case nodeAlreadyOrchestrating
    case insufficientCredits
    
    var errorDescription: String? {
        switch self {
        case .nodeNotFound:
            return "The node could not be found"
        case .invalidSessionState:
            return "Invalid orchestration session state"
        case .noRolesApproved:
            return "No roles were approved for the panel"
        case .tooManyDelegates:
            return "Too many delegates selected (maximum 5)"
        case .delegatesNotComplete:
            return "Not all delegates have completed their responses"
        case .generationTimeout:
            return "AI generation timed out"
        case .parsingFailed:
            return "Failed to parse AI response"
        case .orchestrationInProgress:
            return "An orchestration is already in progress"
        case .nodeAlreadyOrchestrating:
            return "This node is already part of an orchestration"
        case .insufficientCredits:
            return "Insufficient credits for team orchestration"
        }
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
