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
    
    // Services
    let geminiClient: GeminiClient
    let ragService: RAGService
    let database: Database
    let undoManager: CanvasUndoManager
    
    private var cancellables = Set<AnyCancellable>()
    private var autosaveTimer: Timer?
    
    // MARK: - Initialization
    
    init(project: Project, database: Database) {
        self.project = project
        self.database = database
        self.geminiClient = GeminiClient()
        self.ragService = RAGService(geminiClient: geminiClient, database: database)
        self.undoManager = CanvasUndoManager()
        
        loadProjectData()
        setupAutosave()
    }
    
    // MARK: - Data Loading
    
    private func loadProjectData() {
        do {
            let loadedNodes = try database.loadNodes(projectId: project.id)
            let loadedEdges = try database.loadEdges(projectId: project.id)
            
            nodes = Dictionary(uniqueKeysWithValues: loadedNodes.map { ($0.id, $0) })
            edges = Dictionary(uniqueKeysWithValues: loadedEdges.map { ($0.id, $0) })
        } catch {
            errorMessage = "Failed to load project: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Node Operations
    
    func createNode(at position: CGPoint, parentId: UUID? = nil, inheritContext: Bool = false) {
        var node = Node(
            projectId: project.id,
            parentId: parentId,
            x: position.x,
            y: position.y
        )
        
        // Set up ancestry and context
        if let parentId = parentId, let parent = nodes[parentId] {
            var ancestry = parent.ancestry
            ancestry.append(parentId)
            node.setAncestry(ancestry)
            node.systemPromptSnapshot = project.systemPrompt
            
            // Don't inherit conversation for branches - just use parent summary as hidden context
            // This gives a clean slate while maintaining context through the summary
            
            // Create edge to parent
            let edge = Edge(projectId: project.id, sourceId: parentId, targetId: node.id)
            edges[edge.id] = edge
            
            do {
                try database.saveEdge(edge)
                undoManager.record(.createEdge(edge))
            } catch {
                errorMessage = "Failed to save edge: \(error.localizedDescription)"
            }
        }
        
        nodes[node.id] = node
        
        // Auto-select newly created node
        selectedNodeId = node.id
        
        do {
            try database.saveNode(node)
            undoManager.record(.createNode(node))
        } catch {
            errorMessage = "Failed to save node: \(error.localizedDescription)"
        }
    }
    
    func createChildNode(parentId: UUID) {
        guard let parent = nodes[parentId] else { return }
        
        // Calculate position for child node (offset to the right and down)
        let childX = parent.x + Node.nodeWidth + 50
        let childY = parent.y + 100
        
        // Create branch without inheriting conversation (inheritContext: false)
        // The parent's summary will be used as context instead
        createNode(at: CGPoint(x: childX, y: childY), parentId: parentId, inheritContext: false)
        
        // Generate TLDR summary asynchronously to provide context for the branch
        Task {
            await generateTLDRSummary(for: parent.id)
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
            let role = msg.role == .user ? "User" : "AI"
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
            try database.saveNode(parent)
        } catch {
            print("Failed to generate TLDR summary: \(error)")
        }
    }
    
    func updateNode(_ node: Node) {
        guard let oldNode = nodes[node.id] else { return }
        
        var updatedNode = node
        updatedNode.updatedAt = Date()
        nodes[node.id] = updatedNode
        
        do {
            try database.saveNode(updatedNode)
            undoManager.record(.updateNode(oldNode: oldNode, newNode: updatedNode))
        } catch {
            errorMessage = "Failed to update node: \(error.localizedDescription)"
        }
    }
    
    func deleteNode(_ nodeId: UUID) {
        guard let node = nodes[nodeId] else { return }
        
        // Delete connected edges
        let connectedEdges = edges.values.filter { $0.sourceId == nodeId || $0.targetId == nodeId }
        for edge in connectedEdges {
            edges.removeValue(forKey: edge.id)
            try? database.deleteEdge(id: edge.id)
        }
        
        nodes.removeValue(forKey: nodeId)
        
        do {
            try database.deleteNode(id: nodeId)
            undoManager.record(.deleteNode(node))
        } catch {
            errorMessage = "Failed to delete node: \(error.localizedDescription)"
        }
    }
    
    func moveNode(_ nodeId: UUID, to position: CGPoint) {
        guard var node = nodes[nodeId] else { return }
        
        let oldPosition = CGPoint(x: node.x, y: node.y)
        node.x = position.x
        node.y = position.y
        node.updatedAt = Date()
        
        nodes[nodeId] = node
        
        do {
            try database.saveNode(node)
            undoManager.coalesceIfNeeded(.moveNode(id: nodeId, oldPosition: oldPosition, newPosition: position))
        } catch {
            errorMessage = "Failed to move node: \(error.localizedDescription)"
        }
    }
    
    // MARK: - AI Generation
    
    func generateResponse(for nodeId: UUID, prompt: String) {
        guard var node = nodes[nodeId] else { return }
        
        generatingNodeId = nodeId
        
        // Add user message to conversation
        node.addMessage(role: .user, content: prompt)
        // Also update legacy prompt field for backwards compatibility
        node.prompt = prompt
        nodes[nodeId] = node
        
        Task {
            do {
                let context = buildContext(for: node)
                var streamedResponse = ""
                
                geminiClient.generateStreaming(
                    prompt: prompt,
                    systemPrompt: node.systemPromptSnapshot ?? project.systemPrompt,
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
                                
                                try? self?.database.saveNode(finalNode)
                                
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
                    content: msg.content
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
            AI: \(node.response)
            
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
            try database.saveNode(node)
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
            
            do {
                try database.saveNode(newNode)
                undoManager.record(.createNode(newNode))
            } catch {
                errorMessage = "Failed to paste node: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Undo/Redo
    
    func undo() {
        guard let action = undoManager.undo() else { return }
        applyAction(action, reverse: true)
    }
    
    func redo() {
        guard let action = undoManager.redo() else { return }
        applyAction(action, reverse: false)
    }
    
    private func applyAction(_ action: CanvasAction, reverse: Bool) {
        switch action {
        case .createNode(let node):
            if reverse {
                nodes.removeValue(forKey: node.id)
                try? database.deleteNode(id: node.id)
            } else {
                nodes[node.id] = node
                try? database.saveNode(node)
            }
            
        case .deleteNode(let node):
            if reverse {
                nodes[node.id] = node
                try? database.saveNode(node)
            } else {
                nodes.removeValue(forKey: node.id)
                try? database.deleteNode(id: node.id)
            }
            
        case .updateNode(let oldNode, let newNode):
            let nodeToApply = reverse ? oldNode : newNode
            nodes[nodeToApply.id] = nodeToApply
            try? database.saveNode(nodeToApply)
            
        case .moveNode(let id, let oldPos, let newPos):
            guard var node = nodes[id] else { return }
            let position = reverse ? oldPos : newPos
            node.x = position.x
            node.y = position.y
            nodes[id] = node
            try? database.saveNode(node)
            
        case .createEdge(let edge):
            if reverse {
                edges.removeValue(forKey: edge.id)
                try? database.deleteEdge(id: edge.id)
            } else {
                edges[edge.id] = edge
                try? database.saveEdge(edge)
            }
            
        case .deleteEdge(let edge):
            if reverse {
                edges[edge.id] = edge
                try? database.saveEdge(edge)
            } else {
                edges.removeValue(forKey: edge.id)
                try? database.deleteEdge(id: edge.id)
            }
            
        case .updateProject(let oldProj, let newProj):
            project = reverse ? oldProj : newProj
            try? database.saveProject(project)
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
        do {
            try database.saveProject(project)
            // Save all nodes
            for node in nodes.values {
                try database.saveNode(node)
            }
            // Save all edges
            for edge in edges.values {
                try database.saveEdge(edge)
            }
        } catch {
            errorMessage = "Auto-save failed: \(error.localizedDescription)"
        }
    }
}
