//
//  CanvasViewModel.swift
//  JamAI
//
//  Main view model coordinating canvas state and operations
//

import Foundation
import SwiftUI
import Combine
import AppKit
import FirebaseAuth

@MainActor
class CanvasViewModel: ObservableObject {
    // MARK: - Published State
    
    @Published var project: Project
    @Published var nodes: [UUID: Node] = [:]
    @Published var edges: [UUID: Edge] = [:]
    @Published var selectedNodeId: UUID?
    @Published var generatingNodeId: UUID?
    @Published var errorMessage: String?
    
    // Canvas state
    @Published var offset: CGSize = .zero
    @Published var zoom: CGFloat = Config.defaultZoom
    @Published var showDots: Bool = false
    @Published var positionsVersion: Int = 0 // increment to force connector refresh
    @Published var isNavigating: Bool = false // true during animated navigation
    @Published var isZooming: Bool = false // true during active zoom gesture for performance optimization
    @Published var isPanning: Bool = false // true during active pan gesture for performance optimization
    @Published var selectedTool: CanvasTool = .select
    @Published var viewportSize: CGSize = CGSize(width: 1200, height: 800) // updated by CanvasView
    
    // Forward undo manager state for UI binding
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    // Services
    let geminiClient: GeminiClient
    let ragService: RAGService
    let database: Database
    let dbActor: DatabaseActor
    let undoManager: CanvasUndoManager
    
    private var cancellables = Set<AnyCancellable>()
    private var autosaveTimer: Timer?
    
    // Debounced write queue
    private var pendingNodeWrites: Set<UUID> = []
    private var pendingEdgeWrites: Set<UUID> = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3 // 300ms debounce
    
    // MARK: - Initialization
    
    init(project: Project, database: Database) {
        self.project = project
        self.database = database
        self.dbActor = DatabaseActor(db: database)
        self.geminiClient = GeminiClient()
        self.ragService = RAGService(geminiClient: geminiClient, database: database)
        self.undoManager = CanvasUndoManager()
        
        // Forward undo manager state changes with logging
        undoManager.$canUndo
            .sink { [weak self] value in
                if Config.enableVerboseLogging { print("🟢 ViewModel: canUndo changed to \(value)") }
                self?.canUndo = value
                // Force UI update
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        undoManager.$canRedo
            .sink { [weak self] value in
                if Config.enableVerboseLogging { print("🟢 ViewModel: canRedo changed to \(value)") }
                self?.canRedo = value
                // Force UI update
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        loadProjectData()
        setupAutosave()
    }
    
    deinit {
        // Cleanup GeminiClient to prevent hanging on app quit
        geminiClient.cleanup()
        autosaveTimer?.invalidate()
    }

    func createNoteFromSelection(parentId: UUID, selectedText: String) {
        guard let parent = nodes[parentId] else { return }
        let noteCountBefore = self.nodes.values.filter { $0.type == .note }.count
        if Config.enableVerboseLogging { print("📝 [NoteCreate] begin parent=\(parentId) notes_before=\(noteCountBefore) len=\(selectedText.count)") }

        let noteX = parent.x + parent.width + 50
        let noteY = parent.y + 40
        var note = Node(
            projectId: project.id,
            parentId: parentId,
            x: noteX,
            y: noteY,
            height: Node.collapsedHeight + 120,
            title: "Note",
            titleSource: .user,
            description: selectedText,
            descriptionSource: .user,
            isExpanded: true,
            isFrozenContext: false,
            color: "lightYellow",
            type: .note
        )
        var ancestry = parent.ancestry
        ancestry.append(parentId)
        note.setAncestry(ancestry)
        note.systemPromptSnapshot = self.project.systemPrompt
        if Config.enableVerboseLogging { print("📝 [NoteCreate] note id=\(note.id) x=\(note.x) y=\(note.y)") }
        
        self.nodes[note.id] = note
        self.selectedNodeId = note.id
        self.undoManager.record(.createNode(note))
        
        // Create edge with parent's color
        let parentColor = self.nodes[parentId]?.color
        let edgeColor = (parentColor != nil && parentColor != "none") ? parentColor : nil
        let edge = Edge(projectId: self.project.id, sourceId: parentId, targetId: note.id, color: edgeColor)
        self.edges[edge.id] = edge
        self.undoManager.record(.createEdge(edge))
        if Config.enableVerboseLogging { print("📝 [NoteCreate] edge id=\(edge.id) color=\(String(describing: edge.color))") }
        
        // Force edge refresh immediately to ensure wire appears
        Task { @MainActor in
            self.positionsVersion += 1
        }
        
        // Use debounced write system for reliable persistence
        self.scheduleDebouncedWrite(edgeId: edge.id)
        
        // Save node atomically
        let dbActor = self.dbActor
        Task { [dbActor, note] in
            do {
                if Config.enableVerboseLogging { print("📝 [NoteCreate] save begin node=\(note.id)") }
                try await dbActor.saveNode(note)
                if Config.enableVerboseLogging { print("📝 [NoteCreate] save node ok=\(note.id)") }
                
                // Track note creation analytics
                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                    await AnalyticsService.shared.trackNodeCreation(
                        userId: userId,
                        projectId: note.projectId,
                        nodeId: note.id,
                        nodeType: "note",
                        creationMethod: .note,
                        parentNodeId: parentId,
                        teamMemberRoleId: note.teamMember?.roleId
                    )
                }
            } catch {
                if Config.enableVerboseLogging { print("⚠️ Failed to save note: \(error.localizedDescription)") }
            }
        }
    }

    func expandFromNote(noteId: UUID) {
        guard let note = nodes[noteId] else { return }
        let text = note.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        expandSelectedText(parentId: noteId, selectedText: text)
    }
    
    // MARK: - Data Loading
    
    private func loadProjectData() {
        do {
            let loadedNodes = try database.loadNodes(projectId: project.id)
            let loadedEdges = try database.loadEdges(projectId: project.id)
            
            nodes = Dictionary(uniqueKeysWithValues: loadedNodes.map { ($0.id, $0) })
            
            // Filter out orphaned edges (edges that reference non-existent nodes)
            let validEdges = loadedEdges.filter { edge in
                nodes[edge.sourceId] != nil && nodes[edge.targetId] != nil
            }
            edges = Dictionary(uniqueKeysWithValues: validEdges.map { ($0.id, $0) })
            
            // Clean up orphaned edges from database
            let orphanedEdges = loadedEdges.filter { edge in
                nodes[edge.sourceId] == nil || nodes[edge.targetId] == nil
            }
            if !orphanedEdges.isEmpty {
                let dbActor = self.dbActor
                Task.detached(priority: .utility) { [dbActor, orphanedEdges] in
                    for edge in orphanedEdges {
                        try? await dbActor.deleteEdge(id: edge.id)
                    }
                }
            }
            
            // Restore canvas view state
            offset = CGSize(width: project.canvasOffsetX, height: project.canvasOffsetY)
            zoom = project.canvasZoom
            showDots = project.showDots
            
            // Force edge refresh to ensure wires render correctly on load
            positionsVersion += 1
        } catch {
            errorMessage = "Failed to load project: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Node Operations
    
    func calculateCenterPosition(viewportSize: CGSize = CGSize(width: 1200, height: 800)) -> CGPoint {
        // Calculate the canvas center position accounting for offset and zoom
        // Formula from CanvasView contextMenu
        let centerX = (viewportSize.width / 2 - offset.width) / zoom
        let centerY = (viewportSize.height / 2 - offset.height) / zoom
        return CGPoint(x: centerX, y: centerY)
    }
    
    func createNode(at position: CGPoint, parentId: UUID? = nil, inheritContext: Bool = false) {
        // Defer state changes to avoid publishing during view updates
        // Use .userInitiated QoS to match the calling context and avoid priority inversion
        Task(priority: .userInitiated) { @MainActor in
            var node = Node(
                projectId: self.project.id,
                parentId: parentId,
                x: position.x,
                y: position.y
            )
            
            // Set up ancestry and context
            if let parentId = parentId, let parent = self.nodes[parentId] {
                var ancestry = parent.ancestry
                ancestry.append(parentId)
                node.setAncestry(ancestry)
                node.systemPromptSnapshot = self.project.systemPrompt
                
                // Don't inherit conversation for branches - just use parent summary as hidden context
                // This gives a clean slate while maintaining context through the summary
                
                // Create edge to parent with parent's color
                let parentColor = parent.color != "none" ? parent.color : nil
                let edge = Edge(projectId: self.project.id, sourceId: parentId, targetId: node.id, color: parentColor)
                self.edges[edge.id] = edge
                self.undoManager.record(.createEdge(edge))
                // Use debounced write system to ensure reliable persistence
                self.scheduleDebouncedWrite(edgeId: edge.id)
            }
            
            self.nodes[node.id] = node
            
            // Auto-select newly created node
            self.selectedNodeId = node.id
            self.undoManager.record(.createNode(node))
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do {
                    try await dbActor.saveNode(node)

                    // Track node creation analytics
                    if let userId = FirebaseAuthService.shared.currentUser?.uid {
                        await AnalyticsService.shared.trackNodeCreation(
                            userId: userId,
                            projectId: node.projectId,
                            nodeId: node.id,
                            nodeType: "standard",
                            creationMethod: .manual,
                            parentNodeId: nil,
                            teamMemberRoleId: node.teamMember?.roleId
                        )
                    }
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to save node: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    @discardableResult
    private func createNodeImmediate(at position: CGPoint, parentId: UUID? = nil, inheritContext: Bool = false) -> UUID {
        var node = Node(
            projectId: self.project.id,
            parentId: parentId,
            x: position.x,
            y: position.y
        )
        // Set up ancestry and context
        if let parentId = parentId, let parent = self.nodes[parentId] {
            var ancestry = parent.ancestry
            ancestry.append(parentId)
            node.setAncestry(ancestry)
            node.systemPromptSnapshot = self.project.systemPrompt

            // Create edge to parent with parent's color
            let parentColor = parent.color != "none" ? parent.color : nil
            let edge = Edge(projectId: self.project.id, sourceId: parentId, targetId: node.id, color: parentColor)
            self.edges[edge.id] = edge
            self.undoManager.record(.createEdge(edge))
            // Use debounced write system to ensure reliable persistence
            self.scheduleDebouncedWrite(edgeId: edge.id)
        }

        self.nodes[node.id] = node
        // Auto-select newly created node
        self.selectedNodeId = node.id
        self.undoManager.record(.createNode(node))
        
        // Force positions refresh so edges render immediately
        self.positionsVersion += 1

        let dbActor = self.dbActor
        Task { [weak self, dbActor, node] in
            do {
                try await dbActor.saveNode(node)
                
                // Track node creation analytics
                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                    await AnalyticsService.shared.trackNodeCreation(
                        userId: userId,
                        projectId: node.projectId,
                        nodeId: node.id,
                        nodeType: "standard",
                        creationMethod: parentId != nil ? .childNode : .manual,
                        parentNodeId: parentId,
                        teamMemberRoleId: node.teamMember?.roleId
                    )
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to save node: \(error.localizedDescription)"
                }
            }
        }

        return node.id
    }

    // MARK: - Annotation Creation
    func createTextLabel(at position: CGPoint) {
        // Defer state changes to avoid publishing during view updates
        // Use .userInitiated QoS to match the calling context and avoid priority inversion
        Task(priority: .userInitiated) { @MainActor in
            let node = Node(
                projectId: self.project.id,
                parentId: nil,
                x: position.x,
                y: position.y,
                height: 60,
                title: "",
                titleSource: .user,
                description: "",
                descriptionSource: .user,
                isExpanded: false,
                color: "none",
                type: .text,
                fontSize: 24,
                isBold: false,
                fontFamily: nil,
                shapeKind: nil
            )
            self.nodes[node.id] = node
            self.selectedNodeId = node.id
            self.undoManager.record(.createNode(node))
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do { try await dbActor.saveNode(node) }
                catch {
                    await MainActor.run { self?.errorMessage = "Failed to save text: \(error.localizedDescription)" }
                }
            }
        }
    }

    func createShape(at position: CGPoint, kind: ShapeKind) {
        // Defer state changes to avoid publishing during view updates
        // Use .userInitiated QoS to match the calling context and avoid priority inversion
        Task(priority: .userInitiated) { @MainActor in
            let node = Node(
                projectId: self.project.id,
                parentId: nil,
                x: position.x,
                y: position.y,
                height: 120,
                title: "",
                titleSource: .user,
                description: "",
                descriptionSource: .user,
                isExpanded: false,
                color: "lightGray",
                type: .shape,
                fontSize: 16,
                isBold: false,
                fontFamily: nil,
                shapeKind: kind
            )
            self.nodes[node.id] = node
            self.selectedNodeId = node.id
            self.undoManager.record(.createNode(node))
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do { try await dbActor.saveNode(node) }
                catch {
                    await MainActor.run { self?.errorMessage = "Failed to save shape: \(error.localizedDescription)" }
                }
            }
        }
    }
    
    func createChildNode(parentId: UUID) {
        guard let parent = nodes[parentId] else { return }
        
        // Calculate position for child node (offset to the right and down)
        let childX = parent.x + parent.width + 50
        let childY = parent.y + 100
        
        // Create branch without inheriting conversation (inheritContext: false)
        // The parent's summary will be used as context instead
        let childId = createNodeImmediate(at: CGPoint(x: childX, y: childY), parentId: parentId, inheritContext: false)
        
        // Inherit team member from parent if present
        if let parentTeamMember = parent.teamMember {
            if var child = nodes[childId] {
                child.setTeamMember(parentTeamMember)
                updateNode(child, immediate: true)
            }
        }
        
        // Generate TLDR summary asynchronously to provide context for the branch
        Task {
            await generateTLDRSummary(for: parent.id)
        }
    }
    
    func expandSelectedText(parentId: UUID, selectedText: String) {
        guard let parent = nodes[parentId] else { return }
        
        // Calculate position for child node (offset to the right and down)
        let childX = parent.x + parent.width + 50
        let childY = parent.y + 100
        
        // Create branch without inheriting conversation immediately to avoid race with async creation
        let childId = createNodeImmediate(at: CGPoint(x: childX, y: childY), parentId: parentId, inheritContext: false)
        
        // Indicate generation immediately so UI shows spinner
        generatingNodeId = childId
        
        // Start tasks in parallel: title generation + TLDR context
        Task { [weak self] in
            guard let self = self else { return }
            await self.autoGenerateTitleFromSelectedText(for: childId, selectedText: selectedText)
        }
        Task { [weak self] in
            guard let self = self else { return }
            await self.generateTLDRSummary(for: parent.id)
        }
        
        // Build context-aware prompt for expansion (this won't be shown to user)
        let expansionPrompt = "Expand on this: \"\(selectedText)\". Provide a short, concise explanation with additional context."
        
        // Generate response without adding the prompt to conversation first
        Task { @MainActor [weak self] in
            self?.generateExpandedResponse(for: childId, prompt: expansionPrompt, selectedText: selectedText)

            // Track expand action analytics
            if let userId = FirebaseAuthService.shared.currentUser?.uid {
                await FirebaseDataService.shared.incrementUserMetadata(userId: userId, field: "totalExpandActions")
            }
        }
    }

    func jamWithSelectedText(parentId: UUID, selectedText: String) {
        guard let parent = nodes[parentId] else { return }
        
        // Calculate position for child node (offset to the right and down)
        let childX = parent.x + parent.width + 50
        let childY = parent.y + 100
        
        // Create branch immediately to avoid race; do not inherit conversation
        let childId = createNodeImmediate(at: CGPoint(x: childX, y: childY), parentId: parentId, inheritContext: false)
        
        // Get the newly created child
        guard var child = self.nodes[childId] else { return }
        
        // Set selected text as description; no auto response
        child.description = selectedText
        child.descriptionSource = .user
        child.prompt = ""
        child.response = ""
        updateNode(child, immediate: true)
        
        // Auto-generate a concise title from the selected text
        Task { [weak self] in
            await self?.autoGenerateTitleFromSelectedText(for: childId, selectedText: selectedText)
        }
        
        // Prepare context for future conversations: TLDR parent
        Task { [weak self] in
            await self?.generateTLDRSummary(for: parentId)
        }
    }
    

    private func generateExpandedResponse(for nodeId: UUID, prompt: String, selectedText: String) {
        guard let node = nodes[nodeId] else { return }
        
        // Check credit availability before generating
        guard CreditTracker.shared.canGenerateResponse() else {
            errorMessage = CreditTracker.shared.getRemainingCreditsMessage() ?? "Unable to generate response"
            return
        }
        
        generatingNodeId = nodeId
        
        // Do not store user prompt; expansions keep the conversation clean
        
        Task {
            do {
                let context = buildContext(for: node)
                var streamedResponse = ""
                
                // Assemble system prompt - use team member's prompt if available
                let baseSystemPrompt = node.systemPromptSnapshot ?? project.systemPrompt
                let finalSystemPrompt: String
                if let teamMember = node.teamMember,
                   let role = RoleManager.shared.roles.first(where: { $0.id == teamMember.roleId }) {
                    finalSystemPrompt = teamMember.assembleSystemPrompt(with: role, baseSystemPrompt: baseSystemPrompt)
                    
                    // Track team member usage in generation
                    self.trackTeamMemberUsage(
                        nodeId: nodeId,
                        roleId: role.id,
                        roleName: role.name,
                        roleCategory: role.category.rawValue,
                        experienceLevel: teamMember.experienceLevel.rawValue,
                        actionType: .used
                    )
                } else {
                    finalSystemPrompt = baseSystemPrompt
                }
                
                geminiClient.generateStreaming(
                    prompt: prompt,
                    systemPrompt: finalSystemPrompt,
                    context: context,
                    onChunk: { [weak self] chunk in
                        Task { @MainActor in
                            streamedResponse += chunk
                            // Temporarily show streaming response
                            guard var currentNode = self?.nodes[nodeId] else { return }
                            currentNode.response = streamedResponse
                            self?.nodes[nodeId] = currentNode
                        }
                    },
                    onComplete: { [weak self] result in
                        Task { @MainActor in
                            self?.generatingNodeId = nil
                            
                            switch result {
                            case .success(let fullResponse):
                                guard var finalNode = self?.nodes[nodeId] else { return }
                                // Only add assistant response to conversation (not the prompt)
                                finalNode.addMessage(role: .assistant, content: fullResponse)
                                finalNode.response = fullResponse
                                finalNode.updatedAt = Date()
                                self?.nodes[nodeId] = finalNode
                                if let dbActor = self?.dbActor {
                                    Task { [dbActor, finalNode] in
                                        try? await dbActor.saveNode(finalNode)
                                    }
                                }
                                
                                // Deduct credits before logging analytics
                                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                                    let creditsToDeduct = CreditTracker.shared.calculateCredits(promptText: prompt, responseText: fullResponse)
                                    _ = await FirebaseDataService.shared.deductCredits(userId: userId, amount: creditsToDeduct, description: "AI Expand Action")
                                }

                                // Track credit usage and analytics
                                await CreditTracker.shared.trackGeneration(
                                    promptText: prompt,
                                    responseText: fullResponse,
                                    nodeId: nodeId,
                                    projectId: self?.project.id ?? UUID(),
                                    teamMemberRoleId: finalNode.teamMember?.roleId,
                                    teamMemberExperienceLevel: finalNode.teamMember?.experienceLevel.rawValue,
                                    generationType: "expand"
                                )
                                
                                // Auto-generate title based on selected text
                                await self?.autoGenerateTitleForExpansion(for: nodeId, selectedText: selectedText)
                                
                            case .failure(let error):
                                self?.errorMessage = error.localizedDescription
                            }
                        }
                    }
                )
            }
        }
    }
    
    private func autoGenerateTitleFromSelectedText(for nodeId: UUID, selectedText: String) async {
        guard var node = nodes[nodeId] else { return }
        do {
            let prompt = "Create a short, clear title (max 40 chars) based only on this text: \"\(selectedText)\". Return only the title."
            let result = try await geminiClient.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that writes concise, descriptive titles."
            )
            let title = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                node.title = String(title.prefix(40))
                node.titleSource = .ai
                updateNode(node, immediate: true)
            }
        } catch {
            // Non-fatal if title generation fails
        }
    }
    
    private func autoGenerateTitleForExpansion(for nodeId: UUID, selectedText: String) async {
        guard var node = nodes[nodeId] else { return }
        
        do {
            let prompt = """
            Based on this expansion request about "\(selectedText)", and the response:
            \(node.response)
            
            Generate a concise title (max 50 chars) and description (max 150 chars).
            Format: TITLE: <title>
            DESCRIPTION: <description>
            """
            
            let result = try await geminiClient.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that creates concise titles and descriptions."
            )
            
            if let titleMatch = result.range(of: "TITLE: (.+)", options: .regularExpression),
               let title = result[titleMatch].components(separatedBy: "TITLE: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                node.title = String(title.prefix(50))
                node.titleSource = .ai
            }
            
            if let descMatch = result.range(of: "DESCRIPTION: (.+)", options: .regularExpression),
               let desc = result[descMatch].components(separatedBy: "DESCRIPTION: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                node.description = String(desc.prefix(150))
                node.descriptionSource = .ai
            }
            
            updateNode(node, immediate: true)
        } catch {
            if Config.enableVerboseLogging { print("Failed to auto-generate title/description: \(error)") }
        }
    }
    
    private func generateTLDRSummary(for parentId: UUID) async {
        guard var parent = nodes[parentId] else { return }
        
        // Get the last few conversation turns
        let recentConversation = Array(parent.conversation.suffix(6)) // Last 3 exchanges
        
        if recentConversation.isEmpty {
            return
        }
        
        // Build summary prompt
        var conversationText = ""
        for msg in recentConversation {
            let role = msg.role == .user ? "User" : "Jam"
            conversationText += "\(role): \(msg.content)\n\n"
        }
        
        let prompt = """
        Provide a concise TLDR summary (2-3 sentences max) of this conversation context:
        
        \(conversationText)
        
        Focus on key points and decisions. This will be used as hidden context for branching conversations.
        """
        
        do {
            let summary = try await geminiClient.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that creates concise summaries."
            )
            
            parent.summary = summary
            nodes[parentId] = parent
            let dbActor = self.dbActor
            Task { [weak self, dbActor, parent] in
                do {
                    try await dbActor.saveNode(parent)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to save summary: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            if Config.enableVerboseLogging { print("Failed to generate TLDR summary: \(error)") }
        }
    }
    
    func updateNode(_ node: Node, immediate: Bool = false) {
        guard let oldNode = nodes[node.id] else { return }
        
        var updatedNode = node
        updatedNode.updatedAt = Date()
        if Config.enableVerboseLogging && updatedNode.type == .note {
            print("📝 [NoteUpdate] node=\(updatedNode.id) immediate=\(immediate) desc_len=\(updatedNode.description.count)")
        }
        
        // Explicitly trigger objectWillChange before mutation
        objectWillChange.send()
        nodes[node.id] = updatedNode
        
        undoManager.record(.updateNode(oldNode: oldNode, newNode: updatedNode))
        
        // Check if a team member was removed
        if oldNode.teamMember != nil && updatedNode.teamMember == nil {
            if let userId = FirebaseAuthService.shared.currentUser?.uid {
                Task {
                    await FirebaseDataService.shared.decrementUserMetadata(userId: userId, field: "totalTeamMembersUsed")
                }
            }
        }

        // Debounce database write unless immediate
        if immediate {
            let dbActor = self.dbActor
            Task { [weak self, dbActor, updatedNode] in
                do {
                    try await dbActor.saveNode(updatedNode)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to update node: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            scheduleDebouncedWrite(nodeId: node.id)
        }
    }
    
    func updateEdge(_ edge: Edge, immediate: Bool = false) {
        guard edges[edge.id] != nil else { return }
        
        // Explicitly trigger objectWillChange before mutation
        objectWillChange.send()
        edges[edge.id] = edge
        positionsVersion += 1
        
        // Always use debounced write for reliable persistence
        scheduleDebouncedWrite(edgeId: edge.id)
    }
    
    func deleteNode(_ nodeId: UUID) {
        guard let node = nodes[nodeId] else { return }
        
        // Delete connected edges (remove from pending writes and schedule deletion)
        let connectedEdges = edges.values.filter { $0.sourceId == nodeId || $0.targetId == nodeId }
        for edge in connectedEdges {
            edges.removeValue(forKey: edge.id)
            // Remove from pending writes if queued
            pendingEdgeWrites.remove(edge.id)
            // Immediate delete for node deletion
            let dbActor = self.dbActor
            Task { [dbActor, edgeId = edge.id] in
                try? await dbActor.deleteEdge(id: edgeId)
            }
        }
        
        nodes.removeValue(forKey: nodeId)
        
        // Record node deletion with connected edges for proper undo
        undoManager.record(.deleteNode(node, connectedEdges: Array(connectedEdges)))
        let dbActor = self.dbActor
        Task { [weak self, dbActor, nodeId, node] in
            do {
                try await dbActor.deleteNode(id: nodeId)

                // Decrement the user-facing metadata stat
                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                    var fieldToDecrement: String?
                    switch node.type {
                    case .standard:
                        if node.parentId != nil {
                            fieldToDecrement = "totalChildNodesCreated"
                        } else {
                            fieldToDecrement = "totalNodesCreated"
                        }
                    case .note:
                        fieldToDecrement = "totalNotesCreated"
                    default:
                        break // Other types don't have counters
                    }

                    if let field = fieldToDecrement {
                        await FirebaseDataService.shared.decrementUserMetadata(userId: userId, field: field)
                    }

                    // Also decrement team member count if one was assigned
                    if node.teamMember != nil {
                        await FirebaseDataService.shared.decrementUserMetadata(userId: userId, field: "totalTeamMembersUsed")
                    }
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to delete node: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func moveNode(_ nodeId: UUID, to position: CGPoint) {
        guard var node = nodes[nodeId] else { return }
        
        let oldPosition = CGPoint(x: node.x, y: node.y)
        node.x = position.x
        node.y = position.y
        node.updatedAt = Date()
        
        // Explicitly trigger objectWillChange before mutation
        objectWillChange.send()
        nodes[nodeId] = node
        positionsVersion &+= 1 // signal to views that positions changed
        
        undoManager.coalesceIfNeeded(.moveNode(id: nodeId, oldPosition: oldPosition, newPosition: position))
        
        // Debounce database write during drag
        scheduleDebouncedWrite(nodeId: nodeId)
    }
    
    /// Get all team members from nodes in the current project, excluding a specific node
    func getProjectTeamMembers(excludingNodeId: UUID? = nil) -> [(nodeName: String, teamMember: TeamMember, role: Role?)] {
        let roleManager = RoleManager.shared
        return nodes.values
            .filter { node in
                // Exclude the specified node if provided
                if let excludeId = excludingNodeId, node.id == excludeId {
                    return false
                }
                // Only include nodes with team members
                return node.teamMember != nil
            }
            .compactMap { node in
                guard let teamMember = node.teamMember else { return nil }
                let role = roleManager.role(withId: teamMember.roleId)
                let nodeName = node.title.isEmpty ? "Untitled" : node.title
                return (nodeName: nodeName, teamMember: teamMember, role: role)
            }
    }
    
    // MARK: - AI Generation
    
    func generateResponse(for nodeId: UUID, prompt: String, imageData: Data? = nil, imageMimeType: String? = nil) {
        guard var node = nodes[nodeId] else { return }
        
        // Check credit availability before generating
        guard CreditTracker.shared.canGenerateResponse() else {
            errorMessage = CreditTracker.shared.getRemainingCreditsMessage() ?? "Unable to generate response"
            return
        }
        
        generatingNodeId = nodeId
        
        // Add user message to conversation with optional image
        node.addMessage(role: .user, content: prompt, imageData: imageData, imageMimeType: imageMimeType)
        // Also update legacy prompt field for backwards compatibility
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let context = self.buildContext(for: node)
                var streamedResponse = ""
                
                // Assemble system prompt
                let baseSystemPrompt = node.systemPromptSnapshot ?? self.project.systemPrompt
                let finalSystemPrompt: String
                if let teamMember = node.teamMember,
                   let role = RoleManager.shared.roles.first(where: { $0.id == teamMember.roleId }) {
                    finalSystemPrompt = teamMember.assembleSystemPrompt(with: role, baseSystemPrompt: baseSystemPrompt)
                    
                    // Track team member usage
                    self.trackTeamMemberUsage(
                        nodeId: nodeId,
                        roleId: role.id,
                        roleName: role.name,
                        roleCategory: role.category.rawValue,
                        experienceLevel: teamMember.experienceLevel.rawValue,
                        actionType: .used
                    )
                } else {
                    finalSystemPrompt = baseSystemPrompt
                }
                
                self.geminiClient.generateStreaming(
                    prompt: prompt,
                    systemPrompt: finalSystemPrompt,
                    context: context,
                    onChunk: { [weak self] chunk in
                        Task { @MainActor in
                            streamedResponse += chunk
                            // Temporarily show streaming response
                            guard var currentNode = self?.nodes[nodeId] else { return }
                            currentNode.response = streamedResponse
                            self?.nodes[nodeId] = currentNode
                        }
                    },
                    onComplete: { [weak self] result in
                        Task { @MainActor in
                            self?.generatingNodeId = nil
                            
                            switch result {
                            case .success(let fullResponse):
                                guard var finalNode = self?.nodes[nodeId] else { return }
                                // Add assistant message to conversation
                                finalNode.addMessage(role: .assistant, content: fullResponse)
                                // Also update legacy response field for backwards compatibility
                                finalNode.response = fullResponse
                                finalNode.updatedAt = Date()
                                self?.nodes[nodeId] = finalNode
                                if let dbActor = self?.dbActor {
                                    Task { [dbActor, finalNode] in
                                        try? await dbActor.saveNode(finalNode)
                                    }
                                }
                                
                                // Deduct credits before logging analytics
                                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                                    let creditsToDeduct = CreditTracker.shared.calculateCredits(promptText: prompt, responseText: fullResponse)
                                    _ = await FirebaseDataService.shared.deductCredits(userId: userId, amount: creditsToDeduct, description: "AI Chat Message")
                                }

                                // Track credit usage and analytics
                                await CreditTracker.shared.trackGeneration(
                                    promptText: prompt,
                                    responseText: fullResponse,
                                    nodeId: nodeId,
                                    projectId: self?.project.id ?? UUID(),
                                    teamMemberRoleId: finalNode.teamMember?.roleId,
                                    teamMemberExperienceLevel: finalNode.teamMember?.experienceLevel.rawValue,
                                    generationType: "chat"
                                )
                                
                                // Auto-generate title and description if empty
                                await self?.autoGenerateTitleAndDescription(for: nodeId)
                                
                            case .failure(let error):
                                self?.errorMessage = error.localizedDescription
                            }
                        }
                    }
                )
            }
        }
    }
    
    private func buildContext(for node: Node) -> [Message] {
        var messages: [Message] = []
        
        // Add parent summary as context if available
        if let parentId = node.parentId,
           let parent = nodes[parentId],
           let summary = parent.summary,
           !summary.isEmpty {
            messages.append(Message(
                role: "user",
                content: "Context from previous conversation: \(summary)"
            ))
        }
        
        // Use conversation history if available
        if !node.conversation.isEmpty {
            // Take last K conversation turns
            let recentMessages = Array(node.conversation.suffix(project.kTurns * 2))
            for msg in recentMessages {
                messages.append(Message(
                    role: msg.role == .user ? "user" : "model",
                    content: msg.content,
                    imageData: msg.imageData,
                    imageMimeType: msg.imageMimeType
                ))
            }
        } else {
            // Fallback to legacy ancestor-based context
            let ancestorNodes = node.ancestry.compactMap { nodes[$0] }
            let recentAncestors = Array(ancestorNodes.suffix(project.kTurns))
            
            for ancestor in recentAncestors {
                if !ancestor.prompt.isEmpty {
                    messages.append(Message(role: "user", content: ancestor.prompt))
                }
                if !ancestor.response.isEmpty {
                    messages.append(Message(role: "model", content: ancestor.response))
                }
            }
        }
        
        return messages
    }
    
    private func autoGenerateTitleAndDescription(for nodeId: UUID) async {
        guard var node = nodes[nodeId] else { return }
        guard node.title.isEmpty || node.description.isEmpty else { return }
        
        do {
            let prompt = """
            Based on this conversation:
            User: \(node.prompt)
            Jam: \(node.response)
            
            Generate a concise title (max 50 chars) and description (max 150 chars).
            Format: TITLE: <title>
            DESCRIPTION: <description>
            """
            
            let result = try await geminiClient.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that creates concise titles and descriptions."
            )
            
            if node.title.isEmpty {
                if let titleMatch = result.range(of: "TITLE: (.+)", options: .regularExpression),
                   let title = result[titleMatch].components(separatedBy: "TITLE: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    node.title = String(title.prefix(50))
                    node.titleSource = .ai
                }
            }
            
            if node.description.isEmpty {
                if let descMatch = result.range(of: "DESCRIPTION: (.+)", options: .regularExpression),
                   let desc = result[descMatch].components(separatedBy: "DESCRIPTION: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    node.description = String(desc.prefix(150))
                    node.descriptionSource = .ai
                }
            }
            
            nodes[nodeId] = node
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do {
                    try await dbActor.saveNode(node)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to auto-save node: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            print("Failed to auto-generate title/description: \(error)")
        }
    }
    
    // MARK: - Copy/Paste
    
    func copyNode(_ nodeId: UUID) {
        guard let node = nodes[nodeId] else { return }
        
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(node),
           let jsonString = String(data: data, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(jsonString, forType: .string)
        }
    }
    
    func pasteNode(at position: CGPoint) {
        let pasteboard = NSPasteboard.general
        guard let jsonString = pasteboard.string(forType: .string),
              let data = jsonString.data(using: .utf8) else { return }
        
        let decoder = JSONDecoder()
        if let originalNode = try? decoder.decode(Node.self, from: data) {
            // Create new node with new ID
            let newNode = Node(
                id: UUID(),
                projectId: originalNode.projectId,
                parentId: nil,
                x: position.x,
                y: position.y,
                height: originalNode.height,
                title: originalNode.title,
                titleSource: originalNode.titleSource,
                description: originalNode.description,
                descriptionSource: originalNode.descriptionSource,
                conversationJSON: originalNode.conversationJSON,
                prompt: originalNode.prompt,
                response: originalNode.response,
                ancestryJSON: "[]",
                summary: originalNode.summary,
                systemPromptSnapshot: originalNode.systemPromptSnapshot,
                isExpanded: originalNode.isExpanded,
                isFrozenContext: originalNode.isFrozenContext
            )
            
            nodes[newNode.id] = newNode
            
            let dbActor = self.dbActor
            undoManager.record(.createNode(newNode))
            Task { [weak self, dbActor, newNode] in
                do {
                    try await dbActor.saveNode(newNode)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to paste node: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // MARK: - Undo/Redo
    
    func undo() {
        if Config.enableVerboseLogging { print("🔄 Undo called - canUndo: \(undoManager.canUndo)") }
        guard let action = undoManager.undo() else {
            if Config.enableVerboseLogging { print("⚠️ No action to undo") }
            return
        }
        if Config.enableVerboseLogging { print("✅ Undoing action: \(action)") }
        applyAction(action, reverse: true)
    }
    
    func redo() {
        if Config.enableVerboseLogging { print("🔄 Redo called - canRedo: \(undoManager.canRedo)") }
        guard let action = undoManager.redo() else {
            if Config.enableVerboseLogging { print("⚠️ No action to redo") }
            return
        }
        if Config.enableVerboseLogging { print("✅ Redoing action: \(action)") }
        applyAction(action, reverse: false)
    }
    
    private func applyAction(_ action: CanvasAction, reverse: Bool) {
        switch action {
        case .createNode(let node):
            if reverse {
                nodes.removeValue(forKey: node.id)
                let dbActor = self.dbActor
                Task { [dbActor, nodeId = node.id] in
                    try? await dbActor.deleteNode(id: nodeId)
                }
            } else {
                nodes[node.id] = node
                let dbActor = self.dbActor
                Task { [dbActor, node] in
                    try? await dbActor.saveNode(node)
                }
            }
            
        case .deleteNode(let node, let connectedEdges):
            if reverse {
                // Undo: restore node and all connected edges
                nodes[node.id] = node
                let dbActor = self.dbActor
                Task { [dbActor, node] in
                    try? await dbActor.saveNode(node)
                }
                // Restore all connected edges using debounced write
                for edge in connectedEdges {
                    edges[edge.id] = edge
                    scheduleDebouncedWrite(edgeId: edge.id)
                }
            } else {
                // Redo: delete node and connected edges
                nodes.removeValue(forKey: node.id)
                let dbActor = self.dbActor
                Task { [dbActor, nodeId = node.id] in
                    try? await dbActor.deleteNode(id: nodeId)
                }
                // Delete all connected edges
                for edge in connectedEdges {
                    edges.removeValue(forKey: edge.id)
                    pendingEdgeWrites.remove(edge.id)
                    Task { [dbActor, edgeId = edge.id] in
                        try? await dbActor.deleteEdge(id: edgeId)
                    }
                }
            }
            
        case .updateNode(let oldNode, let newNode):
            let nodeToApply = reverse ? oldNode : newNode
            nodes[nodeToApply.id] = nodeToApply
            let dbActor = self.dbActor
            Task { [dbActor, nodeToApply] in
                try? await dbActor.saveNode(nodeToApply)
            }
            
        case .moveNode(let id, let oldPos, let newPos):
            guard var node = nodes[id] else { return }
            let position = reverse ? oldPos : newPos
            node.x = position.x
            node.y = position.y
            nodes[id] = node
            let dbActor = self.dbActor
            Task { [dbActor, node] in
                try? await dbActor.saveNode(node)
            }
            
        case .createEdge(let edge):
            if reverse {
                edges.removeValue(forKey: edge.id)
                pendingEdgeWrites.remove(edge.id)
                let dbActor = self.dbActor
                Task { [dbActor, edgeId = edge.id] in
                    try? await dbActor.deleteEdge(id: edgeId)
                }
            } else {
                edges[edge.id] = edge
                scheduleDebouncedWrite(edgeId: edge.id)
            }
            
        case .deleteEdge(let edge):
            if reverse {
                edges[edge.id] = edge
                scheduleDebouncedWrite(edgeId: edge.id)
            } else {
                edges.removeValue(forKey: edge.id)
                pendingEdgeWrites.remove(edge.id)
                let dbActor = self.dbActor
                Task { [dbActor, edgeId = edge.id] in
                    try? await dbActor.deleteEdge(id: edgeId)
                }
            }
            
        case .updateProject(let oldProj, let newProj):
            project = reverse ? oldProj : newProj
            let snapshotProject = project
            let dbActor = self.dbActor
            Task { [dbActor, snapshotProject] in
                try? await dbActor.saveProject(snapshotProject)
            }
        }
    }
    
    // MARK: - Navigation
    
    func navigateToNode(_ nodeId: UUID, viewportSize: CGSize = CGSize(width: 1200, height: 800)) {
        guard let node = nodes[nodeId] else { return }
        
        // Select the node
        selectedNodeId = nodeId
        
        // Calculate node center in world coordinates
        let nodeWidth = node.width
        let nodeHeight = node.height
        let nodeCenterX = node.x + nodeWidth / 2
        let nodeCenterY = node.y + nodeHeight / 2
        
        // Calculate target offset to center the node in viewport
        let targetZoom: CGFloat = 1.0
        let targetOffset = CGSize(
            width: viewportSize.width / 2 - nodeCenterX * targetZoom,
            height: viewportSize.height / 2 - nodeCenterY * targetZoom
        )
        
        // Animate the navigation
        withAnimation(.easeInOut(duration: 0.5)) {
            zoom = targetZoom
            offset = targetOffset
        }
        
        // Update edges after animation completes to ensure they're correctly positioned
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000) // 0.55s (0.5s animation + 0.05s buffer)
            positionsVersion &+= 1
        }
    }
    
    func toggleNodeSize(_ nodeId: UUID, viewportSize: CGSize = CGSize(width: 1200, height: 800)) {
        guard var node = nodes[nodeId] else { return }
        
        // Determine if node is currently at max size
        let maxWidth = node.type == .note ? Node.maxNoteWidth : Node.maxWidth
        let minWidth = node.type == .note ? Node.minNoteWidth : Node.minWidth
        let isMaximized = node.width >= maxWidth && node.height >= Node.maxHeight
        
        // Toggle between min and max size with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            if isMaximized {
                // Minimize: set to square dimensions (width = height)
                node.width = minWidth
                node.height = minWidth
            } else {
                // Maximize: set to maximum dimensions
                node.width = maxWidth
                node.height = Node.maxHeight
            }
            
            // Ensure node is expanded when resizing
            if !node.isExpanded {
                node.isExpanded = true
            }
            
            nodes[nodeId] = node
        }
        
        updateNode(node, immediate: true)
        
        // Calculate node center in world coordinates with new dimensions
        let nodeCenterX = node.x + node.width / 2
        let nodeCenterY = node.y + node.height / 2
        
        // Calculate target offset to center the node in viewport at 100% zoom
        let targetZoom: CGFloat = 1.0
        let targetOffset = CGSize(
            width: viewportSize.width / 2 - nodeCenterX * targetZoom,
            height: viewportSize.height / 2 - nodeCenterY * targetZoom
        )
        
        // Animate the navigation
        withAnimation(.easeInOut(duration: 0.5)) {
            zoom = targetZoom
            offset = targetOffset
        }
        
        // Update edges after animation completes to ensure they're correctly positioned
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000) // 0.55s (0.5s animation + 0.05s buffer)
            positionsVersion &+= 1
        }
    }
    
    // MARK: - Zoom Controls
    
    func zoomIn() {
        let newZoom = min(Config.maxZoom, zoom * 1.2)
        zoomToCenter(newZoom: newZoom)
    }
    
    func zoomOut() {
        let newZoom = max(Config.minZoom, zoom / 1.2)
        zoomToCenter(newZoom: newZoom)
    }
    
    func resetZoom() {
        zoomToCenter(newZoom: Config.defaultZoom)
    }
    
    func zoomToFit() {
        guard !nodes.isEmpty else {
            resetZoom()
            return
        }
        
        // Calculate bounding box of all nodes
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for node in nodes.values {
            let nodeWidth = node.width
            let nodeHeight = node.height
            
            minX = min(minX, node.x)
            minY = min(minY, node.y)
            maxX = max(maxX, node.x + nodeWidth)
            maxY = max(maxY, node.y + nodeHeight)
        }
        
        let contentWidth = maxX - minX
        let contentHeight = maxY - minY
        let contentCenterX = (minX + maxX) / 2
        let contentCenterY = (minY + maxY) / 2
        
        // Add padding (20% of content size)
        let padding: CGFloat = 1.2
        
        // Calculate zoom to fit content with padding
        let zoomX = viewportSize.width / (contentWidth * padding)
        let zoomY = viewportSize.height / (contentHeight * padding)
        let newZoom = max(Config.minZoom, min(Config.maxZoom, min(zoomX, zoomY)))
        
        // Calculate offset to center content
        let viewportCenterX = viewportSize.width / 2
        let viewportCenterY = viewportSize.height / 2
        let newOffset = CGSize(
            width: viewportCenterX - contentCenterX * newZoom,
            height: viewportCenterY - contentCenterY * newZoom
        )
        
        withAnimation(.easeOut(duration: 0.3)) {
            zoom = newZoom
            offset = newOffset
        }
    }
    
    private func zoomToCenter(newZoom: CGFloat) {
        let oldZoom = zoom
        // Calculate viewport center
        let centerX = viewportSize.width / 2
        let centerY = viewportSize.height / 2
        // Calculate world point at viewport center before zoom
        let worldX = (centerX - offset.width) / max(oldZoom, 0.001)
        let worldY = (centerY - offset.height) / max(oldZoom, 0.001)
        // Calculate new offset to keep that world point at viewport center after zoom
        let newOffset = CGSize(
            width: centerX - worldX * newZoom,
            height: centerY - worldY * newZoom
        )
        
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = newZoom
            offset = newOffset
        }
    }
    
    // MARK: - Outline Ordering
    
    func reorderNode(_ nodeId: UUID, from sourceIndex: Int, to destinationIndex: Int, in nodeIds: [UUID]) {
        guard sourceIndex != destinationIndex else { return }
        
        // Reassign display orders for all affected nodes
        var updates: [(UUID, Int)] = []
        
        if sourceIndex < destinationIndex {
            // Moving down: shift items between source and destination up
            for i in 0..<nodeIds.count {
                let id = nodeIds[i]
                if i == sourceIndex {
                    updates.append((id, destinationIndex))
                } else if i > sourceIndex && i <= destinationIndex {
                    updates.append((id, i - 1))
                } else {
                    updates.append((id, i))
                }
            }
        } else {
            // Moving up: shift items between destination and source down
            for i in 0..<nodeIds.count {
                let id = nodeIds[i]
                if i == sourceIndex {
                    updates.append((id, destinationIndex))
                } else if i >= destinationIndex && i < sourceIndex {
                    updates.append((id, i + 1))
                } else {
                    updates.append((id, i))
                }
            }
        }
        
        // Apply all updates
        for (id, newOrder) in updates {
            guard var node = nodes[id] else { continue }
            node.displayOrder = newOrder
            updateNode(node)
        }
    }
    
    // MARK: - Auto-save
    
    private func setupAutosave() {
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: Config.autoSaveInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.save()
            }
        }
    }
    
    func save() {
        // Flush any pending debounced writes first
        flushPendingWrites()
        
        // Update project's canvas state before saving
        project.canvasOffsetX = offset.width
        project.canvasOffsetY = offset.height
        project.canvasZoom = zoom
        project.showDots = showDots
        
        let snapshotProject = project
        let snapshotNodes = Array(nodes.values)
        let snapshotEdges = Array(edges.values)
        let dbActor = self.dbActor
        Task { [weak self, dbActor, snapshotProject, snapshotNodes, snapshotEdges] in
            do {
                try await dbActor.saveProject(snapshotProject)
                for node in snapshotNodes {
                    try await dbActor.saveNode(node)
                }
                for edge in snapshotEdges {
                    try await dbActor.saveEdge(edge)
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Auto-save failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func saveAndWait() async {
        project.canvasOffsetX = offset.width
        project.canvasOffsetY = offset.height
        project.canvasZoom = zoom
        project.showDots = showDots
        let snapshotProject = project
        let snapshotNodes = Array(nodes.values)
        let snapshotEdges = Array(edges.values)
        let nodeIds = pendingNodeWrites
        let edgeIds = pendingEdgeWrites
        pendingNodeWrites.removeAll()
        pendingEdgeWrites.removeAll()
        let nodesToSave = nodeIds.compactMap { nodes[$0] }
        let edgesToSave = edgeIds.compactMap { edges[$0] }
        let dbActor = self.dbActor
        do {
            try await dbActor.saveProject(snapshotProject)
            for node in nodesToSave { try await dbActor.saveNode(node) }
            for edge in edgesToSave { try await dbActor.saveEdge(edge) }
            for node in snapshotNodes { try await dbActor.saveNode(node) }
            for edge in snapshotEdges { try await dbActor.saveEdge(edge) }
        } catch {
            self.errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Debounced Writes
    
    private func scheduleDebouncedWrite(nodeId: UUID) {
        pendingNodeWrites.insert(nodeId)
        
        // Cancel previous debounce
        debounceWorkItem?.cancel()
        
        // Schedule new debounce
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingWrites()
            }
        }
        debounceWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    private func scheduleDebouncedWrite(edgeId: UUID) {
        pendingEdgeWrites.insert(edgeId)
        
        // Cancel previous debounce
        debounceWorkItem?.cancel()
        
        // Schedule new debounce
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingWrites()
            }
        }
        debounceWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    private func flushPendingWrites() {
        // Snapshot pending IDs and clear sets on main actor
        let nodeIds = pendingNodeWrites
        let edgeIds = pendingEdgeWrites
        pendingNodeWrites.removeAll()
        pendingEdgeWrites.removeAll()

        // Capture models to save
        let nodesToSave = nodeIds.compactMap { nodes[$0] }
        let edgesToSave = edgeIds.compactMap { edges[$0] }
        let dbActor = self.dbActor
        
        // Perform I/O off the main actor
        Task { [weak self, dbActor, nodesToSave, edgesToSave] in
            do {
                for node in nodesToSave {
                    try await dbActor.saveNode(node)
                }
                for edge in edgesToSave {
                    try await dbActor.saveEdge(edge)
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to save pending changes: \(error.localizedDescription)"
                }
            }
        }
        
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }
    
    // MARK: - Analytics Tracking
    
    /// Track team member attachment/change for analytics
    func trackTeamMemberUsage(
        nodeId: UUID,
        roleId: String,
        roleName: String,
        roleCategory: String,
        experienceLevel: String,
        actionType: TeamMemberUsageEvent.ActionType
    ) {
        guard let userId = FirebaseAuthService.shared.currentUser?.uid else { return }
        guard let node = nodes[nodeId] else { return }
        
        Task {
            await AnalyticsService.shared.trackTeamMemberUsage(
                userId: userId,
                projectId: project.id,
                nodeId: nodeId,
                roleId: roleId,
                roleName: roleName,
                roleCategory: roleCategory,
                experienceLevel: experienceLevel,
                actionType: actionType
            )
            
            // If team member was used in generation, update metadata
            if actionType == .used {
                if var metadata = FirebaseDataService.shared.userAccount?.metadata {
                    metadata.totalTeamMembersUsed += 1
                    await FirebaseDataService.shared.updateUserMetadata(userId: userId, metadata: metadata)
                }
            }
        }
    }
}
